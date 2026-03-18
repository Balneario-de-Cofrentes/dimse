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
  @role_selection_item 0x54
  @implementation_version_item 0x55
  @sop_class_extended_item 0x56
  @sop_class_common_extended_item 0x57
  @user_identity_item 0x58
  @user_identity_ac_item 0x59

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

    # Keep as iodata — use iolist_size to avoid flattening twice
    payload = [
      <<pdu.protocol_version || 1::16, 0::16>>,
      pad_ae(pdu.called_ae_title || ""),
      pad_ae(pdu.calling_ae_title || ""),
      <<0::256>>,
      app_context,
      pres_contexts,
      user_info
    ]

    [<<@associate_rq, 0x00, :erlang.iolist_size(payload)::32>>, payload]
  end

  ## A-ASSOCIATE-AC (type 0x02) — PS3.8 Section 9.3.3

  defp encode_associate_ac(pdu) do
    app_context =
      encode_application_context(pdu.application_context || @dicom_application_context)

    pres_contexts =
      Enum.map(pdu.presentation_contexts || [], &encode_presentation_context_ac/1)

    user_info = encode_user_information(pdu.user_information)

    payload = [
      <<pdu.protocol_version || 1::16, 0::16>>,
      pad_ae(pdu.called_ae_title || ""),
      pad_ae(pdu.calling_ae_title || ""),
      <<0::256>>,
      app_context,
      pres_contexts,
      user_info
    ]

    [<<@associate_ac, 0x00, :erlang.iolist_size(payload)::32>>, payload]
  end

  ## A-ASSOCIATE-RJ (type 0x03) — PS3.8 Section 9.3.4

  defp encode_associate_rj(pdu) do
    <<@associate_rj, 0x00, 4::32, 0x00, pdu.result, pdu.source, pdu.reason>>
  end

  ## P-DATA-TF (type 0x04) — PS3.8 Section 9.3.5

  # Fast path for single PDV (most common case — avoids Enum.map list allocation)
  defp encode_p_data_tf(%Pdu.PDataTf{pdv_items: [pdv]}) do
    encoded = encode_pdv(pdv)
    [<<@p_data_tf, 0x00, :erlang.iolist_size(encoded)::32>>, encoded]
  end

  defp encode_p_data_tf(pdu) do
    payload = Enum.map(pdu.pdv_items || [], &encode_pdv/1)
    [<<@p_data_tf, 0x00, :erlang.iolist_size(payload)::32>>, payload]
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
    transfers = Enum.map(pc.transfer_syntaxes || [], &encode_transfer_syntax/1)
    items = [abstract | transfers]
    # 4 bytes fixed header (id, 3 reserved)
    items_size = :erlang.iolist_size(items)

    [
      <<@presentation_context_rq_item, 0x00, items_size + 4::16, pc.id::8, 0x00, 0x00, 0x00>>,
      items
    ]
  end

  defp encode_presentation_context_ac(%Pdu.PresentationContext{} = pc) do
    transfer =
      case pc.transfer_syntaxes do
        [ts | _] -> encode_transfer_syntax(ts)
        _ -> <<>>
      end

    transfer_size = :erlang.iolist_size(transfer)

    [
      <<@presentation_context_ac_item, 0x00, transfer_size + 4::16, pc.id::8, 0x00,
        pc.result || 0::8, 0x00>>,
      transfer
    ]
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
    items = [
      encode_max_length(ui.max_pdu_length || 16_384),
      encode_implementation_uid(ui.implementation_uid || "1.2.826.0.1.3680043.8.498.1"),
      encode_implementation_version(ui.implementation_version),
      encode_role_selections(ui.role_selections),
      encode_sop_class_extended_list(ui.sop_class_extended),
      encode_sop_class_common_extended_list(ui.sop_class_common_extended),
      encode_user_identity(ui.user_identity),
      encode_user_identity_ac(ui.user_identity_ac)
    ]

    [<<@user_information_item, 0x00, :erlang.iolist_size(items)::16>>, items]
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

  ## Extended Negotiation sub-item encoders

  defp encode_role_selections(nil), do: <<>>
  defp encode_role_selections([]), do: <<>>
  defp encode_role_selections(list), do: Enum.map(list, &encode_role_selection/1)

  defp encode_role_selection(%Pdu.RoleSelection{} = rs) do
    uid = rs.sop_class_uid || ""
    uid_len = byte_size(uid)
    # item_len = 2 (uid_len field) + uid_len + 2 (scu + scp)
    item_len = 2 + uid_len + 2
    scu = if rs.scu_role, do: 1, else: 0
    scp = if rs.scp_role, do: 1, else: 0
    <<@role_selection_item, 0x00, item_len::16, uid_len::16, uid::binary, scu::8, scp::8>>
  end

  defp encode_sop_class_extended_list(nil), do: <<>>
  defp encode_sop_class_extended_list([]), do: <<>>
  defp encode_sop_class_extended_list(list), do: Enum.map(list, &encode_sop_class_extended/1)

  defp encode_sop_class_extended(%Pdu.SopClassExtendedNegotiation{} = en) do
    uid = en.sop_class_uid || ""
    uid_len = byte_size(uid)
    app_info = en.service_class_application_info || <<>>
    # item_len = 2 (uid_len field) + uid_len + len(app_info)
    item_len = 2 + uid_len + byte_size(app_info)
    <<@sop_class_extended_item, 0x00, item_len::16, uid_len::16, uid::binary, app_info::binary>>
  end

  defp encode_sop_class_common_extended_list(nil), do: <<>>
  defp encode_sop_class_common_extended_list([]), do: <<>>

  defp encode_sop_class_common_extended_list(list) do
    Enum.map(list, &encode_sop_class_common_extended/1)
  end

  defp encode_sop_class_common_extended(%Pdu.SopClassCommonExtendedNegotiation{} = en) do
    uid = en.sop_class_uid || ""
    uid_len = byte_size(uid)
    svc_uid = en.service_class_uid || ""
    svc_uid_len = byte_size(svc_uid)
    related = encode_uid_list(en.related_general_sop_class_uids || [])
    related_len = :erlang.iolist_size(related)

    header = <<
      @sop_class_common_extended_item,
      0x00,
      2 + uid_len + 2 + svc_uid_len + 2 + related_len::16,
      uid_len::16,
      uid::binary,
      svc_uid_len::16,
      svc_uid::binary,
      related_len::16
    >>

    [header, related]
  end

  defp encode_uid_list(uids) do
    Enum.map(uids, fn uid ->
      <<byte_size(uid)::16, uid::binary>>
    end)
  end

  defp encode_user_identity(nil), do: <<>>

  defp encode_user_identity(%Pdu.UserIdentity{} = identity) do
    primary = identity.primary_field || ""
    secondary = identity.secondary_field || ""
    pf_len = byte_size(primary)
    sf_len = byte_size(secondary)
    resp_req = if identity.positive_response_requested, do: 1, else: 0
    identity_type = identity.identity_type || 1
    # item_len = 1 (type) + 1 (resp_req) + 2 (pf_len) + pf_len + 2 (sf_len) + sf_len
    item_len = 1 + 1 + 2 + pf_len + 2 + sf_len

    <<@user_identity_item, 0x00, item_len::16, identity_type::8, resp_req::8, pf_len::16,
      primary::binary, sf_len::16, secondary::binary>>
  end

  defp encode_user_identity_ac(nil), do: <<>>

  defp encode_user_identity_ac(%Pdu.UserIdentityAc{} = uiac) do
    response = uiac.server_response || <<>>
    resp_len = byte_size(response)
    # item_len = 2 (resp_len) + resp_len
    item_len = 2 + resp_len
    <<@user_identity_ac_item, 0x00, item_len::16, resp_len::16, response::binary>>
  end

  ## Helpers

  # 16 space bytes used as padding source — binary_part avoids allocation
  @spaces "                "

  @doc false
  def pad_ae(ae_title) when is_binary(ae_title) do
    len = min(byte_size(ae_title), 16)
    <<binary_part(ae_title, 0, len)::binary, binary_part(@spaces, 0, 16 - len)::binary>>
  end
end
