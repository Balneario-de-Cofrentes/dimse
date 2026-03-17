defmodule Dimse.CommandTest do
  use ExUnit.Case, async: true

  alias Dimse.Command
  alias Dimse.Command.Fields
  alias Dimse.Command.Status

  describe "Command.encode/1" do
    test "returns {:error, :not_implemented}" do
      assert {:error, :not_implemented} = Command.encode(%{})
    end
  end

  describe "Command.decode/1" do
    test "returns {:error, :not_implemented}" do
      assert {:error, :not_implemented} = Command.decode(<<>>)
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
  end
end
