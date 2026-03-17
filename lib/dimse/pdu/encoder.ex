defmodule Dimse.Pdu.Encoder do
  @moduledoc """
  Encodes `Dimse.Pdu` structs into binary iodata for transmission.

  Produces iodata (not flat binaries) to avoid unnecessary copying. The caller
  can pass the result directly to `:gen_tcp.send/2` which accepts iodata.

  Implements the wire format defined in PS3.8 Section 9.3.

  ## Usage

      iodata = Dimse.Pdu.Encoder.encode(%Dimse.Pdu.AssociateRq{...})
      :ok = :gen_tcp.send(socket, iodata)
  """

  alias Dimse.Pdu

  @dicom_application_context "1.2.840.10008.3.1.1.1"

  # PDU type bytes
  @associate_rq 0x01
  @associate_ac 0x02
  @associate_rj 0x03
  @p_data_tf 0x04
  @release_rq 0x05
  @release_rp 0x06
  @abort 0x07

  # Sub-item type bytes
  @application_context_item 0x10
  @presentation_context_rq_item 0x20
  @presentation_context_ac_item 0x21
  @abstract_syntax_item 0x30
  @transfer_syntax_item 0x40
  @user_information_item 0x50
  @max_length_item 0x51
  @implementation_uid_item 0x52
  @implementation_version_item 0x55

  @doc """
  Encodes a PDU struct into iodata.

  Returns iodata suitable for sending over a TCP socket.
  """
  @spec encode(struct()) :: iodata()
  def encode(%Pdu.AssociateRq{} = pdu), do: encode_associate_rq(pdu)
  def encode(%Pdu.AssociateAc{} = pdu), do: encode_associate_ac(pdu)
  def encode(%Pdu.AssociateRj{} = pdu), do: encode_associate_rj(pdu)
  def encode(%Pdu.PDataTf{} = pdu), do: encode_p_data_tf(pdu)
  def encode(%Pdu.ReleaseRq{}), do: encode_release_rq()
  def encode(%Pdu.ReleaseRp{}), do: encode_release_rp()
  def encode(%Pdu.Abort{} = pdu), do: encode_abort(pdu)

  ## A-ASSOCIATE-RQ (type 0x01) — PS3.8 Section 9.3.2

  defp encode_associate_rq(pdu) do
    app_context =
      encode_application_context(pdu.application_context || @dicom_application_context)

    pres_contexts =
      Enum.map(pdu.presentation_contexts || [], &encode_presentation_context_rq/1)

    user_info = encode_user_information(pdu.user_information)

    payload =
      IO.iodata_to_binary([
        <<pdu.protocol_version || 1::16>>,
        <<0::16>>,
        pad_ae(pdu.called_ae_title || ""),
        pad_ae(pdu.calling_ae_title || ""),
        <<0::256>>,
        app_context,
        pres_contexts,
        user_info
      ])

    [<<@associate_rq, 0x00, byte_size(payload)::32>>, payload]
  end

  ## A-ASSOCIATE-AC (type 0x02) — PS3.8 Section 9.3.3

  defp encode_associate_ac(pdu) do
    app_context =
      encode_application_context(pdu.application_context || @dicom_application_context)

    pres_contexts =
      Enum.map(pdu.presentation_contexts || [], &encode_presentation_context_ac/1)

    user_info = encode_user_information(pdu.user_information)

    payload =
      IO.iodata_to_binary([
        <<pdu.protocol_version || 1::16>>,
        <<0::16>>,
        pad_ae(pdu.called_ae_title || ""),
        pad_ae(pdu.calling_ae_title || ""),
        <<0::256>>,
        app_context,
        pres_contexts,
        user_info
      ])

    [<<@associate_ac, 0x00, byte_size(payload)::32>>, payload]
  end

  ## A-ASSOCIATE-RJ (type 0x03) — PS3.8 Section 9.3.4

  defp encode_associate_rj(pdu) do
    <<@associate_rj, 0x00, 4::32, 0x00, pdu.result, pdu.source, pdu.reason>>
  end

  ## P-DATA-TF (type 0x04) — PS3.8 Section 9.3.5

  defp encode_p_data_tf(pdu) do
    pdv_data = Enum.map(pdu.pdv_items || [], &encode_pdv/1)
    payload = IO.iodata_to_binary(pdv_data)
    [<<@p_data_tf, 0x00, byte_size(payload)::32>>, payload]
  end

  defp encode_pdv(%Pdu.PresentationDataValue{} = pdv) do
    flags = pdv_flags(pdv.is_command, pdv.is_last)
    data = pdv.data || <<>>
    # PDV length includes context_id (1 byte) + flags (1 byte) + data
    pdv_length = 2 + byte_size(data)
    [<<pdv_length::32, pdv.context_id::8, flags::8>>, data]
  end

  defp pdv_flags(true, true), do: 0x03
  defp pdv_flags(true, false), do: 0x01
  defp pdv_flags(false, true), do: 0x02
  defp pdv_flags(false, false), do: 0x00
  defp pdv_flags(_, _), do: 0x00

  ## A-RELEASE-RQ (type 0x05) — PS3.8 Section 9.3.6

  defp encode_release_rq do
    <<@release_rq, 0x00, 4::32, 0::32>>
  end

  ## A-RELEASE-RP (type 0x06) — PS3.8 Section 9.3.7

  defp encode_release_rp do
    <<@release_rp, 0x00, 4::32, 0::32>>
  end

  ## A-ABORT (type 0x07) — PS3.8 Section 9.3.8

  defp encode_abort(pdu) do
    <<@abort, 0x00, 4::32, 0x00, 0x00, pdu.source || 0, pdu.reason || 0>>
  end

  ## Sub-item encoders

  defp encode_application_context(uid) do
    <<@application_context_item, 0x00, byte_size(uid)::16, uid::binary>>
  end

  defp encode_presentation_context_rq(%Pdu.PresentationContext{} = pc) do
    abstract = encode_abstract_syntax(pc.abstract_syntax)

    transfers =
      Enum.map(pc.transfer_syntaxes || [], &encode_transfer_syntax/1)

    items = IO.iodata_to_binary([abstract | transfers])
    payload = <<pc.id::8, 0x00, 0x00, 0x00, items::binary>>
    <<@presentation_context_rq_item, 0x00, byte_size(payload)::16, payload::binary>>
  end

  defp encode_presentation_context_ac(%Pdu.PresentationContext{} = pc) do
    transfer =
      case pc.transfer_syntaxes do
        [ts | _] -> encode_transfer_syntax(ts)
        _ -> <<>>
      end

    items = IO.iodata_to_binary(transfer)
    payload = <<pc.id::8, 0x00, pc.result || 0::8, 0x00, items::binary>>
    <<@presentation_context_ac_item, 0x00, byte_size(payload)::16, payload::binary>>
  end

  defp encode_abstract_syntax(uid) do
    <<@abstract_syntax_item, 0x00, byte_size(uid)::16, uid::binary>>
  end

  defp encode_transfer_syntax(uid) do
    <<@transfer_syntax_item, 0x00, byte_size(uid)::16, uid::binary>>
  end

  defp encode_user_information(nil) do
    encode_user_information(%Pdu.UserInformation{})
  end

  defp encode_user_information(%Pdu.UserInformation{} = ui) do
    items =
      IO.iodata_to_binary([
        encode_max_length(ui.max_pdu_length || 16_384),
        encode_implementation_uid(ui.implementation_uid || "1.2.826.0.1.3680043.8.498.1"),
        encode_implementation_version(ui.implementation_version)
      ])

    <<@user_information_item, 0x00, byte_size(items)::16, items::binary>>
  end

  defp encode_max_length(length) do
    <<@max_length_item, 0x00, 4::16, length::32>>
  end

  defp encode_implementation_uid(uid) do
    <<@implementation_uid_item, 0x00, byte_size(uid)::16, uid::binary>>
  end

  defp encode_implementation_version(nil), do: <<>>

  defp encode_implementation_version(version) do
    <<@implementation_version_item, 0x00, byte_size(version)::16, version::binary>>
  end

  ## Helpers

  @doc false
  def pad_ae(ae_title) when is_binary(ae_title) do
    ae_title
    |> String.slice(0, 16)
    |> String.pad_trailing(16)
  end
end
