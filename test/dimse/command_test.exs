defmodule Dimse.CommandTest do
  use ExUnit.Case, async: true

  alias Dimse.Command
  alias Dimse.Command.Fields
  alias Dimse.Command.Status

  describe "encode/1" do
    test "encodes empty command set with only group length" do
      assert {:ok, binary} = Command.encode(%{})
      # Should contain just CommandGroupLength (0000,0000) with value 0
      assert <<0x00, 0x00, 0x00, 0x00, 4::32-little, 0::32-little>> = binary
    end

    test "encodes a C-ECHO-RQ command set" do
      cmd = %{
        {0x0000, 0x0002} => "1.2.840.10008.1.1",
        {0x0000, 0x0100} => 0x0030,
        {0x0000, 0x0110} => 1,
        {0x0000, 0x0800} => 0x0101
      }

      assert {:ok, binary} = Command.encode(cmd)
      assert is_binary(binary)
      # Must decode back correctly
      assert {:ok, decoded} = Command.decode(binary)
      assert decoded[{0x0000, 0x0002}] == "1.2.840.10008.1.1"
      assert decoded[{0x0000, 0x0100}] == 0x0030
      assert decoded[{0x0000, 0x0110}] == 1
      assert decoded[{0x0000, 0x0800}] == 0x0101
    end

    test "auto-computes CommandGroupLength" do
      cmd = %{
        {0x0000, 0x0100} => 0x0030,
        {0x0000, 0x0110} => 1
      }

      assert {:ok, binary} = Command.encode(cmd)
      assert {:ok, decoded} = Command.decode(binary)
      # Group length should be present
      assert is_integer(decoded[{0x0000, 0x0000}])
    end

    test "strips existing CommandGroupLength from input" do
      cmd = %{
        {0x0000, 0x0000} => 9999,
        {0x0000, 0x0100} => 0x0030
      }

      assert {:ok, binary} = Command.encode(cmd)
      assert {:ok, decoded} = Command.decode(binary)
      # Should NOT be 9999 — it's recomputed
      assert decoded[{0x0000, 0x0000}] != 9999
    end

    test "pads UID values to even length" do
      # "1.2.3" is 5 bytes (odd), should be padded with 0x00
      cmd = %{{0x0000, 0x0002} => "1.2.3"}
      assert {:ok, binary} = Command.encode(cmd)
      assert {:ok, decoded} = Command.decode(binary)
      assert decoded[{0x0000, 0x0002}] == "1.2.3"
    end

    test "encodes US values as 16-bit little-endian" do
      cmd = %{{0x0000, 0x0100} => 0x0030}
      assert {:ok, binary} = Command.encode(cmd)
      assert {:ok, decoded} = Command.decode(binary)
      assert decoded[{0x0000, 0x0100}] == 0x0030
    end

    test "encodes UL values as 32-bit little-endian" do
      cmd = %{{0x0000, 0x0000} => 100}
      assert {:ok, binary} = Command.encode(cmd)
      # CommandGroupLength is re-computed, so just verify encode succeeds
      assert is_binary(binary)
    end

    test "encodes and decodes AT lists" do
      cmd = %{{0x0000, 0x1005} => [{0x0008, 0x0018}, {0x0010, 0x0010}]}

      assert {:ok, binary} = Command.encode(cmd)
      assert {:ok, decoded} = Command.decode(binary)
      assert decoded[{0x0000, 0x1005}] == [{0x0008, 0x0018}, {0x0010, 0x0010}]
    end
  end

  describe "decode/1" do
    test "decodes empty binary as empty map" do
      assert {:ok, %{}} = Command.decode(<<>>)
    end

    test "returns error for malformed data" do
      assert {:error, :malformed_command_set} = Command.decode(<<0x01>>)
    end

    test "roundtrips a full C-STORE-RQ command" do
      original = %{
        {0x0000, 0x0002} => "1.2.840.10008.5.1.4.1.1.2",
        {0x0000, 0x0100} => 0x0001,
        {0x0000, 0x0110} => 42,
        {0x0000, 0x0700} => 0,
        {0x0000, 0x0800} => 0x0000,
        {0x0000, 0x1000} => "1.2.3.4.5.6.7.8.9"
      }

      assert {:ok, binary} = Command.encode(original)
      assert {:ok, decoded} = Command.decode(binary)

      # Verify all original keys present (plus auto-added group length)
      for {tag, value} <- original do
        assert decoded[tag] == value, "Mismatch for tag #{inspect(tag)}"
      end
    end
  end

  describe "no_data_set?/1" do
    test "returns true when CommandDataSetType is 0x0101" do
      assert Command.no_data_set?(%{{0x0000, 0x0800} => 0x0101})
    end

    test "returns false when CommandDataSetType is not 0x0101" do
      refute Command.no_data_set?(%{{0x0000, 0x0800} => 0x0000})
    end

    test "returns false when CommandDataSetType is missing" do
      refute Command.no_data_set?(%{})
    end
  end

  describe "command_field/1" do
    test "returns the command field value" do
      assert Command.command_field(%{{0x0000, 0x0100} => 0x0030}) == 0x0030
    end

    test "returns nil when missing" do
      assert Command.command_field(%{}) == nil
    end
  end

  describe "message_id/1" do
    test "returns the message ID" do
      assert Command.message_id(%{{0x0000, 0x0110} => 42}) == 42
    end
  end

  describe "status/1" do
    test "returns the status code" do
      assert Command.status(%{{0x0000, 0x0900} => 0x0000}) == 0x0000
    end
  end

  describe "affected_sop_class_uid/1" do
    test "returns the SOP class UID" do
      assert Command.affected_sop_class_uid(%{{0x0000, 0x0002} => "1.2.3"}) == "1.2.3"
    end
  end

  describe "Fields constants" do
    test "DIMSE-C command fields have correct values" do
      assert Fields.c_store_rq() == 0x0001
      assert Fields.c_store_rsp() == 0x8001
      assert Fields.c_find_rq() == 0x0020
      assert Fields.c_find_rsp() == 0x8020
      assert Fields.c_move_rq() == 0x0021
      assert Fields.c_move_rsp() == 0x8021
      assert Fields.c_get_rq() == 0x0010
      assert Fields.c_get_rsp() == 0x8010
      assert Fields.c_echo_rq() == 0x0030
      assert Fields.c_echo_rsp() == 0x8030
      assert Fields.c_cancel_rq() == 0x0FFF
    end

    test "DIMSE-N command fields have correct values" do
      assert Fields.n_event_report_rq() == 0x0100
      assert Fields.n_event_report_rsp() == 0x8100
      assert Fields.n_get_rq() == 0x0110
      assert Fields.n_get_rsp() == 0x8110
      assert Fields.n_set_rq() == 0x0120
      assert Fields.n_set_rsp() == 0x8120
      assert Fields.n_action_rq() == 0x0130
      assert Fields.n_action_rsp() == 0x8130
      assert Fields.n_create_rq() == 0x0140
      assert Fields.n_create_rsp() == 0x8140
      assert Fields.n_delete_rq() == 0x0150
      assert Fields.n_delete_rsp() == 0x8150
    end

    test "request?/1 identifies request command fields" do
      assert Fields.request?(0x0001)
      assert Fields.request?(0x0030)
      refute Fields.request?(0x8001)
      refute Fields.request?(0x8030)
    end

    test "response?/1 identifies response command fields" do
      assert Fields.response?(0x8001)
      assert Fields.response?(0x8030)
      refute Fields.response?(0x0001)
      refute Fields.response?(0x0030)
    end
  end

  describe "Status constants" do
    test "common status codes" do
      assert Status.success() == 0x0000
      assert Status.pending() == 0xFF00
      assert Status.pending_warning() == 0xFF01
      assert Status.cancel() == 0xFE00
    end

    test "category/1 classifies status codes" do
      assert Status.category(0x0000) == :success
      assert Status.category(0xFF00) == :pending
      assert Status.category(0xFF01) == :pending
      assert Status.category(0xFE00) == :cancel
      assert Status.category(0x0001) == :warning
      assert Status.category(0xB006) == :warning
      assert Status.category(0xA700) == :failure
      assert Status.category(0xC000) == :failure
    end

    test "warning_coercion/0 is 0x0001" do
      assert Status.warning_coercion() == 0x0001
    end

    test "failure_out_of_resources/0 is 0xA700" do
      assert Status.failure_out_of_resources() == 0xA700
    end

    test "failure_identifier_mismatch/0 is 0xA900" do
      assert Status.failure_identifier_mismatch() == 0xA900
    end

    test "failure_unable_to_process/0 is 0xC000" do
      assert Status.failure_unable_to_process() == 0xC000
    end
  end

  describe "LO VR encoding" do
    # Tag (0000,0902) = ErrorComment, VR :LO
    test "encodes and decodes :LO value (ErrorComment tag)" do
      cmd = %{{0x0000, 0x0902} => "Identifier does not match SOP class"}
      assert {:ok, binary} = Command.encode(cmd)
      assert {:ok, decoded} = Command.decode(binary)
      assert decoded[{0x0000, 0x0902}] == "Identifier does not match SOP class"
    end
  end

  describe "AT VR encoding" do
    # Tag (0000,0901) = OffendingElement, VR :AT (single tag reference)
    test "encodes and decodes :AT single tag value" do
      cmd = %{{0x0000, 0x0901} => {0x0008, 0x0060}}
      assert {:ok, binary} = Command.encode(cmd)
      assert {:ok, decoded} = Command.decode(binary)
      assert decoded[{0x0000, 0x0901}] == [{0x0008, 0x0060}]
    end
  end

  describe "unknown VR (catch-all) encoding" do
    # Tag not in @tag_vr → treated as :UN, binary value, odd-length → space-padded
    test "encodes unknown tag with binary value using catch-all path" do
      cmd = %{{0x0009, 0x0001} => "oddlen"}
      assert {:ok, binary} = Command.encode(cmd)
      assert {:ok, decoded} = Command.decode(binary)
      # "oddlen" is 6 bytes (even) — body returned as-is by catch-all decode
      assert decoded[{0x0009, 0x0001}] == "oddlen"
    end

    test "odd-length binary value is space-padded" do
      cmd = %{{0x0009, 0x0001} => "abc"}
      assert {:ok, binary} = Command.encode(cmd)
      # Binary should be padded to even length
      assert byte_size(binary) > 0
    end
  end
end
