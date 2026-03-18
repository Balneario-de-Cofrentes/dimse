defmodule Dimse.Pdu.ExtendedNegotiationTest do
  use ExUnit.Case, async: true

  alias Dimse.Pdu
  alias Dimse.Pdu.{Encoder, Decoder}

  @ct_uid "1.2.840.10008.5.1.4.1.1.2"
  @sr_uid "1.2.840.10008.5.1.4.1.2.2.1"
  @verify_uid "1.2.840.10008.1.1"
  @ts_uid "1.2.840.10008.1.2"

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp base_ui(extra) do
    struct(
      Pdu.UserInformation,
      [max_pdu_length: 16_384, implementation_uid: "1.2.3"] ++ extra
    )
  end

  defp base_rq(ui) do
    %Pdu.AssociateRq{
      protocol_version: 1,
      called_ae_title: "SCP",
      calling_ae_title: "SCU",
      presentation_contexts: [
        %Pdu.PresentationContext{
          id: 1,
          abstract_syntax: @verify_uid,
          transfer_syntaxes: [@ts_uid]
        }
      ],
      user_information: ui
    }
  end

  defp base_ac(ui) do
    %Pdu.AssociateAc{
      protocol_version: 1,
      called_ae_title: "SCP",
      calling_ae_title: "SCU",
      presentation_contexts: [
        %Pdu.PresentationContext{id: 1, result: 0, transfer_syntaxes: [@ts_uid]}
      ],
      user_information: ui
    }
  end

  defp roundtrip(pdu) do
    binary = IO.iodata_to_binary(Encoder.encode(pdu))
    assert {:ok, decoded, <<>>} = Decoder.decode(binary)
    decoded
  end

  # Builds raw A-ASSOCIATE-RQ/AC binaries with custom user_info bytes appended
  # after the standard max_length + impl_uid sub-items. Used for malformed tests.
  defp rq_binary_with_raw_ui(extra_ui_bytes),
    do: pdu_binary_with_raw_ui(0x01, 0x20, extra_ui_bytes)

  defp ac_binary_with_raw_ui(extra_ui_bytes),
    do: pdu_binary_with_raw_ui(0x02, 0x21, extra_ui_bytes)

  defp pdu_binary_with_raw_ui(pdu_type, pc_type, extra_ui_bytes) do
    impl_uid = "1.2.3"

    ui_content =
      <<0x51, 0x00, 4::16, 16_384::32>> <>
        <<0x52, 0x00, byte_size(impl_uid)::16, impl_uid::binary>> <>
        extra_ui_bytes

    ui_item = <<0x50, 0x00, byte_size(ui_content)::16>> <> ui_content

    app_ctx_uid = "1.2.840.10008.3.1.1.1"
    app_ctx = <<0x10, 0x00, byte_size(app_ctx_uid)::16, app_ctx_uid::binary>>
    ts_item = <<0x40, 0x00, byte_size(@ts_uid)::16, @ts_uid::binary>>

    # RQ (0x20) includes Abstract Syntax sub-item; AC (0x21) has transfer syntax only
    pc_body =
      if pdu_type == 0x01 do
        as_item = <<0x30, 0x00, byte_size(@verify_uid)::16, @verify_uid::binary>>
        <<1::8, 0::8, 0::8, 0::8>> <> as_item <> ts_item
      else
        <<1::8, 0::8, 0::8, 0::8>> <> ts_item
      end

    pc_item = <<pc_type, 0x00, byte_size(pc_body)::16>> <> pc_body

    payload =
      <<1::16, 0::16>> <>
        String.pad_trailing("SCP", 16) <>
        String.pad_trailing("SCU", 16) <>
        <<0::256>> <>
        app_ctx <>
        pc_item <>
        ui_item

    <<pdu_type, 0x00, byte_size(payload)::32>> <> payload
  end

  # ── RoleSelection (0x54) ─────────────────────────────────────────────────────

  describe "RoleSelection (0x54)" do
    test "SCU=true SCP=false roundtrip" do
      rs = %Pdu.RoleSelection{sop_class_uid: @ct_uid, scu_role: true, scp_role: false}
      decoded = roundtrip(base_rq(base_ui(role_selections: [rs])))
      [dec] = decoded.user_information.role_selections
      assert dec.sop_class_uid == @ct_uid
      assert dec.scu_role == true
      assert dec.scp_role == false
    end

    test "SCU=false SCP=true roundtrip" do
      rs = %Pdu.RoleSelection{sop_class_uid: @ct_uid, scu_role: false, scp_role: true}
      decoded = roundtrip(base_rq(base_ui(role_selections: [rs])))
      [dec] = decoded.user_information.role_selections
      assert dec.scu_role == false
      assert dec.scp_role == true
    end

    test "both roles true roundtrip" do
      rs = %Pdu.RoleSelection{sop_class_uid: @ct_uid, scu_role: true, scp_role: true}
      decoded = roundtrip(base_rq(base_ui(role_selections: [rs])))
      [dec] = decoded.user_information.role_selections
      assert dec.scu_role == true
      assert dec.scp_role == true
    end

    test "multiple role selections preserved in order" do
      rs1 = %Pdu.RoleSelection{sop_class_uid: @ct_uid, scu_role: true, scp_role: false}
      rs2 = %Pdu.RoleSelection{sop_class_uid: @sr_uid, scu_role: false, scp_role: true}
      decoded = roundtrip(base_rq(base_ui(role_selections: [rs1, rs2])))
      roles = decoded.user_information.role_selections
      assert length(roles) == 2
      assert Enum.any?(roles, &(&1.sop_class_uid == @ct_uid && &1.scu_role == true))
      assert Enum.any?(roles, &(&1.sop_class_uid == @sr_uid && &1.scp_role == true))
    end

    test "decode from raw wire binary" do
      uid = @ct_uid
      uid_len = byte_size(uid)
      item_len = 2 + uid_len + 2
      role_item = <<0x54, 0x00, item_len::16, uid_len::16, uid::binary, 1::8, 0::8>>
      assert {:ok, rq, <<>>} = Decoder.decode(rq_binary_with_raw_ui(role_item))
      assert [rs] = rq.user_information.role_selections
      assert rs.sop_class_uid == uid
      assert rs.scu_role == true
      assert rs.scp_role == false
    end

    test "malformed binary (stated uid_len > available bytes) returns error" do
      uid = @ct_uid
      uid_len = byte_size(uid)
      # Outer item provides uid_len bytes of uid + scu + scp,
      # but the inner uid_length field claims 100 bytes — sub-parser can't match.
      bogus_uid_len = 100
      item_data = <<bogus_uid_len::16, uid::binary-size(uid_len), 1::8, 0::8>>
      item_len = byte_size(item_data)
      role_item = <<0x54, 0x00, item_len::16>> <> item_data
      assert {:error, _} = Decoder.decode(rq_binary_with_raw_ui(role_item))
    end
  end

  # ── SopClassExtendedNegotiation (0x56) ───────────────────────────────────────

  describe "SopClassExtendedNegotiation (0x56)" do
    test "with non-empty app_info roundtrip" do
      en = %Pdu.SopClassExtendedNegotiation{
        sop_class_uid: @ct_uid,
        service_class_application_info: <<0x01, 0x02, 0x03>>
      }

      decoded = roundtrip(base_rq(base_ui(sop_class_extended: [en])))
      [dec] = decoded.user_information.sop_class_extended
      assert dec.sop_class_uid == @ct_uid
      assert dec.service_class_application_info == <<0x01, 0x02, 0x03>>
    end

    test "with empty app_info roundtrip" do
      en = %Pdu.SopClassExtendedNegotiation{
        sop_class_uid: @ct_uid,
        service_class_application_info: <<>>
      }

      decoded = roundtrip(base_rq(base_ui(sop_class_extended: [en])))
      [dec] = decoded.user_information.sop_class_extended
      assert dec.sop_class_uid == @ct_uid
      assert dec.service_class_application_info == <<>>
    end

    test "multiple entries roundtrip" do
      entries = [
        %Pdu.SopClassExtendedNegotiation{
          sop_class_uid: @ct_uid,
          service_class_application_info: <<0x01>>
        },
        %Pdu.SopClassExtendedNegotiation{
          sop_class_uid: @sr_uid,
          service_class_application_info: <<0x02>>
        }
      ]

      decoded = roundtrip(base_rq(base_ui(sop_class_extended: entries)))
      assert length(decoded.user_information.sop_class_extended) == 2
      uids = Enum.map(decoded.user_information.sop_class_extended, & &1.sop_class_uid)
      assert @ct_uid in uids
      assert @sr_uid in uids
    end

    test "malformed binary (stated uid_len > available bytes) returns error" do
      # uid_len claims 100 but only 2 bytes of uid provided
      item_data = <<100::16, "AB"::binary>>
      item_len = byte_size(item_data)
      ext_item = <<0x56, 0x00, item_len::16>> <> item_data
      assert {:error, _} = Decoder.decode(rq_binary_with_raw_ui(ext_item))
    end
  end

  # ── SopClassCommonExtendedNegotiation (0x57) ──────────────────────────────────

  describe "SopClassCommonExtendedNegotiation (0x57)" do
    test "with zero related UIDs roundtrip" do
      en = %Pdu.SopClassCommonExtendedNegotiation{
        sop_class_uid: @ct_uid,
        service_class_uid: @sr_uid,
        related_general_sop_class_uids: []
      }

      decoded = roundtrip(base_rq(base_ui(sop_class_common_extended: [en])))
      [dec] = decoded.user_information.sop_class_common_extended
      assert dec.sop_class_uid == @ct_uid
      assert dec.service_class_uid == @sr_uid
      assert dec.related_general_sop_class_uids == []
    end

    test "with two related UIDs roundtrip" do
      rel1 = "1.2.840.10008.5.1.4.1.1.1"
      rel2 = "1.2.840.10008.5.1.4.1.1.3"

      en = %Pdu.SopClassCommonExtendedNegotiation{
        sop_class_uid: @ct_uid,
        service_class_uid: @sr_uid,
        related_general_sop_class_uids: [rel1, rel2]
      }

      decoded = roundtrip(base_rq(base_ui(sop_class_common_extended: [en])))
      [dec] = decoded.user_information.sop_class_common_extended
      assert dec.related_general_sop_class_uids == [rel1, rel2]
    end

    test "malformed binary (stated sop_class_uid_len > available bytes) returns error" do
      item_data = <<100::16, "AB"::binary>>
      item_len = byte_size(item_data)
      ext_item = <<0x57, 0x00, item_len::16>> <> item_data
      assert {:error, _} = Decoder.decode(rq_binary_with_raw_ui(ext_item))
    end
  end

  # ── UserIdentity (0x58 — RQ) ──────────────────────────────────────────────────

  describe "UserIdentity (0x58 RQ)" do
    test "type 1 (username only) with empty secondary field roundtrip" do
      ui = %Pdu.UserIdentity{
        identity_type: 1,
        positive_response_requested: false,
        primary_field: "alice",
        secondary_field: ""
      }

      decoded = roundtrip(base_rq(base_ui(user_identity: ui)))
      dec = decoded.user_information.user_identity
      assert dec.identity_type == 1
      assert dec.positive_response_requested == false
      assert dec.primary_field == "alice"
      assert dec.secondary_field == ""
    end

    test "type 2 (username+password) with positive_response_requested=true roundtrip" do
      ui = %Pdu.UserIdentity{
        identity_type: 2,
        positive_response_requested: true,
        primary_field: "bob",
        secondary_field: "secret"
      }

      decoded = roundtrip(base_rq(base_ui(user_identity: ui)))
      dec = decoded.user_information.user_identity
      assert dec.identity_type == 2
      assert dec.positive_response_requested == true
      assert dec.primary_field == "bob"
      assert dec.secondary_field == "secret"
    end

    test "positive_response_requested flag preserved" do
      for requested <- [true, false] do
        ui = %Pdu.UserIdentity{
          identity_type: 1,
          positive_response_requested: requested,
          primary_field: "user",
          secondary_field: ""
        }

        decoded = roundtrip(base_rq(base_ui(user_identity: ui)))
        assert decoded.user_information.user_identity.positive_response_requested == requested
      end
    end

    test "malformed binary (stated primary_field_len > available bytes) returns error" do
      # primary_field_len claims 100 but only 3 bytes of primary_field provided
      item_data = <<1::8, 0::8, 100::16, "bob"::binary, 0::16>>
      item_len = byte_size(item_data)
      id_item = <<0x58, 0x00, item_len::16>> <> item_data
      assert {:error, _} = Decoder.decode(rq_binary_with_raw_ui(id_item))
    end
  end

  # ── UserIdentityAc (0x59) ─────────────────────────────────────────────────────

  describe "UserIdentityAc (0x59)" do
    test "with non-empty server_response roundtrip" do
      uiac = %Pdu.UserIdentityAc{server_response: "server-token"}
      decoded = roundtrip(base_ac(base_ui(user_identity_ac: uiac)))
      assert decoded.user_information.user_identity_ac.server_response == "server-token"
    end

    test "with empty server_response roundtrip" do
      uiac = %Pdu.UserIdentityAc{server_response: <<>>}
      decoded = roundtrip(base_ac(base_ui(user_identity_ac: uiac)))
      assert decoded.user_information.user_identity_ac.server_response == <<>>
    end

    test "malformed binary (stated server_response_len > available bytes) returns error" do
      # server_response_len claims 100 but only 3 bytes provided
      item_data = <<100::16, "tok"::binary>>
      item_len = byte_size(item_data)
      ac_item = <<0x59, 0x00, item_len::16>> <> item_data
      assert {:error, _} = Decoder.decode(ac_binary_with_raw_ui(ac_item))
    end
  end

  # ── Full PDU roundtrips ────────────────────────────────────────────────────────

  describe "Full AssociateRq roundtrip with extended negotiation" do
    test "role_selections + user_identity preserved" do
      rs = %Pdu.RoleSelection{sop_class_uid: @ct_uid, scu_role: true, scp_role: false}

      uid_req = %Pdu.UserIdentity{
        identity_type: 1,
        positive_response_requested: true,
        primary_field: "alice",
        secondary_field: ""
      }

      ui = base_ui(role_selections: [rs], user_identity: uid_req)
      decoded = roundtrip(base_rq(ui))

      [dec_rs] = decoded.user_information.role_selections
      assert dec_rs.sop_class_uid == @ct_uid
      assert dec_rs.scu_role == true

      dec_uid = decoded.user_information.user_identity
      assert dec_uid.primary_field == "alice"
      assert dec_uid.positive_response_requested == true
    end

    test "all five extended fields roundtrip together" do
      rs = %Pdu.RoleSelection{sop_class_uid: @ct_uid, scu_role: true, scp_role: true}

      se = %Pdu.SopClassExtendedNegotiation{
        sop_class_uid: @ct_uid,
        service_class_application_info: <<0xFF>>
      }

      sce = %Pdu.SopClassCommonExtendedNegotiation{
        sop_class_uid: @ct_uid,
        service_class_uid: @sr_uid,
        related_general_sop_class_uids: [@verify_uid]
      }

      uid_req = %Pdu.UserIdentity{
        identity_type: 2,
        positive_response_requested: true,
        primary_field: "user",
        secondary_field: "pass"
      }

      ui =
        base_ui(
          role_selections: [rs],
          sop_class_extended: [se],
          sop_class_common_extended: [sce],
          user_identity: uid_req
        )

      decoded = roundtrip(base_rq(ui))

      assert [d_rs] = decoded.user_information.role_selections
      assert d_rs.sop_class_uid == @ct_uid

      assert [d_se] = decoded.user_information.sop_class_extended
      assert d_se.service_class_application_info == <<0xFF>>

      assert [d_sce] = decoded.user_information.sop_class_common_extended
      assert d_sce.related_general_sop_class_uids == [@verify_uid]

      assert decoded.user_information.user_identity.secondary_field == "pass"
    end
  end

  describe "Full AssociateAc roundtrip with extended negotiation" do
    test "role_selections + user_identity_ac preserved" do
      rs = %Pdu.RoleSelection{sop_class_uid: @ct_uid, scu_role: true, scp_role: false}
      uiac = %Pdu.UserIdentityAc{server_response: "server-token"}
      ui = base_ui(role_selections: [rs], user_identity_ac: uiac)
      decoded = roundtrip(base_ac(ui))

      [dec_rs] = decoded.user_information.role_selections
      assert dec_rs.sop_class_uid == @ct_uid

      assert decoded.user_information.user_identity_ac.server_response == "server-token"
    end
  end

  # ── Encoder edge cases ────────────────────────────────────────────────────────

  describe "Encoder empty-list guards" do
    test "encode_role_selections([]) produces same result as nil" do
      rq_nil = base_rq(base_ui(role_selections: nil))
      rq_empty = base_rq(base_ui(role_selections: []))

      assert IO.iodata_to_binary(Encoder.encode(rq_nil)) ==
               IO.iodata_to_binary(Encoder.encode(rq_empty))
    end

    test "encode_sop_class_extended_list([]) produces same result as nil" do
      rq_nil = base_rq(base_ui(sop_class_extended: nil))
      rq_empty = base_rq(base_ui(sop_class_extended: []))

      assert IO.iodata_to_binary(Encoder.encode(rq_nil)) ==
               IO.iodata_to_binary(Encoder.encode(rq_empty))
    end

    test "encode_sop_class_common_extended_list([]) produces same result as nil" do
      rq_nil = base_rq(base_ui(sop_class_common_extended: nil))
      rq_empty = base_rq(base_ui(sop_class_common_extended: []))

      assert IO.iodata_to_binary(Encoder.encode(rq_nil)) ==
               IO.iodata_to_binary(Encoder.encode(rq_empty))
    end

    test "pdv_flags catch-all: nil boolean fields default to 0x00" do
      pdv = %Pdu.PresentationDataValue{context_id: 1, is_command: nil, is_last: nil, data: <<1>>}
      pdata = %Pdu.PDataTf{pdv_items: [pdv]}
      binary = IO.iodata_to_binary(Encoder.encode(pdata))
      assert {:ok, %Pdu.PDataTf{pdv_items: [decoded]}, <<>>} = Decoder.decode(binary)
      # nil treated as false/false → flags byte = 0x00 → is_command=false, is_last=false
      assert decoded.is_command == false
      assert decoded.is_last == false
    end
  end

  # ── Decoder malformed uid_list ─────────────────────────────────────────────

  describe "SopClassCommonExtendedNegotiation malformed related UIDs" do
    test "malformed uid_list (stated uid_len > available bytes in block) returns error" do
      # Build a 0x57 item where the related_uids block claims uid_len=100 but only has 2 bytes
      sop_uid = @ct_uid
      svc_uid = @sr_uid
      sop_len = byte_size(sop_uid)
      svc_len = byte_size(svc_uid)
      # related block: uid_len=100 but only 2 bytes follow → parse_uid_list fails
      related_block = <<100::16, "AB"::binary>>

      item_data =
        <<sop_len::16, sop_uid::binary, svc_len::16, svc_uid::binary,
          byte_size(related_block)::16, related_block::binary>>

      item_len = byte_size(item_data)
      ext_item = <<0x57, 0x00, item_len::16>> <> item_data
      assert {:error, _} = Decoder.decode(rq_binary_with_raw_ui(ext_item))
    end
  end
end
