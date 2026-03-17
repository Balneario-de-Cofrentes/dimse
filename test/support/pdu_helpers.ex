defmodule Dimse.Test.PduHelpers do
  @moduledoc """
  Test helpers for building DICOM PDU binaries and structs.
  """

  alias Dimse.Pdu

  @verification_uid "1.2.840.10008.1.1"
  @implicit_vr_le "1.2.840.10008.1.2"
  @explicit_vr_le "1.2.840.10008.1.2.1"
  def verification_uid, do: @verification_uid
  def implicit_vr_le, do: @implicit_vr_le
  def explicit_vr_le, do: @explicit_vr_le

  @doc "Builds a minimal A-ASSOCIATE-RQ struct for Verification."
  def build_associate_rq(opts \\ []) do
    %Pdu.AssociateRq{
      protocol_version: 1,
      called_ae_title: Keyword.get(opts, :called_ae, "DIMSE"),
      calling_ae_title: Keyword.get(opts, :calling_ae, "TEST_SCU"),
      presentation_contexts: [
        %Pdu.PresentationContext{
          id: 1,
          abstract_syntax: Keyword.get(opts, :abstract_syntax, @verification_uid),
          transfer_syntaxes:
            Keyword.get(opts, :transfer_syntaxes, [@implicit_vr_le, @explicit_vr_le])
        }
      ],
      user_information: %Pdu.UserInformation{
        max_pdu_length: Keyword.get(opts, :max_pdu_length, 16_384),
        implementation_uid: "1.2.3.4.5",
        implementation_version: "TEST_0.1"
      }
    }
  end

  @doc "Builds a minimal A-ASSOCIATE-AC struct."
  def build_associate_ac(opts \\ []) do
    %Pdu.AssociateAc{
      protocol_version: 1,
      called_ae_title: Keyword.get(opts, :called_ae, "DIMSE"),
      calling_ae_title: Keyword.get(opts, :calling_ae, "TEST_SCU"),
      presentation_contexts: [
        %Pdu.PresentationContext{
          id: 1,
          result: 0,
          transfer_syntaxes: [Keyword.get(opts, :transfer_syntax, @implicit_vr_le)]
        }
      ],
      user_information: %Pdu.UserInformation{
        max_pdu_length: Keyword.get(opts, :max_pdu_length, 16_384),
        implementation_uid: "1.2.3.4.5",
        implementation_version: "TEST_0.1"
      }
    }
  end

  @doc "Builds a C-ECHO-RQ command set."
  def echo_rq_command(message_id \\ 1) do
    %{
      {0x0000, 0x0002} => @verification_uid,
      {0x0000, 0x0100} => 0x0030,
      {0x0000, 0x0110} => message_id,
      {0x0000, 0x0800} => 0x0101
    }
  end

  @doc "Builds a C-ECHO-RSP command set."
  def echo_rsp_command(message_id \\ 1) do
    %{
      {0x0000, 0x0002} => @verification_uid,
      {0x0000, 0x0100} => 0x8030,
      {0x0000, 0x0120} => message_id,
      {0x0000, 0x0800} => 0x0101,
      {0x0000, 0x0900} => 0x0000
    }
  end

  @doc "Pads an AE title to exactly 16 bytes (space-padded)."
  def pad_ae(ae) when is_binary(ae) do
    ae |> String.slice(0, 16) |> String.pad_trailing(16)
  end

  @doc "Builds an A-ASSOCIATE-RQ binary with presentation contexts."
  def associate_rq_binary(opts \\ []) do
    rq = build_associate_rq(opts)
    IO.iodata_to_binary(Dimse.Pdu.Encoder.encode(rq))
  end

  @doc "Builds an A-RELEASE-RQ binary."
  def release_rq_binary do
    <<0x05, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00>>
  end

  @doc "Builds an A-RELEASE-RP binary."
  def release_rp_binary do
    <<0x06, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00>>
  end

  @doc "Builds an A-ABORT binary."
  def abort_binary(source \\ 0, reason \\ 0) do
    <<0x07, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, source, reason>>
  end

  @doc "Builds an A-ASSOCIATE-RJ binary."
  def associate_rj_binary(result \\ 1, source \\ 1, reason \\ 1) do
    <<0x03, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, result, source, reason>>
  end

  @doc "Builds a P-DATA-TF binary from a list of PDV items."
  def p_data_binary(pdv_items) do
    pdv_data =
      Enum.map(pdv_items, fn %{context_id: ctx, is_command: cmd, is_last: last, data: data} ->
        flags = pdv_flags(cmd, last)
        pdv_length = 2 + byte_size(data)
        <<pdv_length::32, ctx::8, flags::8, data::binary>>
      end)

    payload = IO.iodata_to_binary(pdv_data)
    <<0x04, 0x00, byte_size(payload)::32, payload::binary>>
  end

  defp pdv_flags(true, true), do: 0x03
  defp pdv_flags(true, false), do: 0x01
  defp pdv_flags(false, true), do: 0x02
  defp pdv_flags(false, false), do: 0x00
end
