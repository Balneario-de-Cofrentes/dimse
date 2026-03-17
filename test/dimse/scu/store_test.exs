defmodule Dimse.Scu.StoreTest do
  use ExUnit.Case, async: true

  alias Dimse.Command.Fields
  alias Dimse.Test.PduHelpers

  describe "command construction" do
    test "builds a valid C-STORE-RQ command set" do
      sop_class = PduHelpers.ct_image_storage()
      sop_instance = "1.2.3.4.5.6.7.8.9"

      cmd = PduHelpers.store_rq_command(sop_class, sop_instance)

      assert cmd[{0x0000, 0x0002}] == sop_class
      assert cmd[{0x0000, 0x0100}] == Fields.c_store_rq()
      assert cmd[{0x0000, 0x0700}] == 0x0000
      assert cmd[{0x0000, 0x0800}] == 0x0000
      assert cmd[{0x0000, 0x1000}] == sop_instance
    end

    test "command set indicates data set follows" do
      cmd = PduHelpers.store_rq_command("1.2.3", "4.5.6")
      # 0x0000 means data set present (not 0x0101 which means no data set)
      assert cmd[{0x0000, 0x0800}] == 0x0000
      refute Dimse.Command.no_data_set?(cmd)
    end

    test "C-STORE-RQ command field is 0x0001" do
      assert Fields.c_store_rq() == 0x0001
      assert Fields.request?(0x0001)
      refute Fields.response?(0x0001)
    end

    test "C-STORE-RSP command field is 0x8001" do
      assert Fields.c_store_rsp() == 0x8001
      assert Fields.response?(0x8001)
      refute Fields.request?(0x8001)
    end
  end
end
