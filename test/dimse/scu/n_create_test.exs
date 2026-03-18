defmodule Dimse.Scu.NCreateTest do
  use ExUnit.Case, async: true

  alias Dimse.Scu.NCreate
  alias Dimse.Command.Fields

  describe "build_command_set/3" do
    test "uses AffectedSOPClassUID (0000,0002)" do
      cmd = NCreate.build_command_set("1.2.3", 1)

      assert cmd[{0x0000, 0x0002}] == "1.2.3"
      refute Map.has_key?(cmd, {0x0000, 0x0003})
    end

    test "sets CommandField to N-CREATE-RQ (0x0140)" do
      cmd = NCreate.build_command_set("1.2.3", 1)
      assert cmd[{0x0000, 0x0100}] == Fields.n_create_rq()
    end

    test "sets MessageID" do
      cmd = NCreate.build_command_set("1.2.3", 55)
      assert cmd[{0x0000, 0x0110}] == 55
    end

    test "sets CommandDataSetType to data set present (0x0000)" do
      cmd = NCreate.build_command_set("1.2.3", 1)
      assert cmd[{0x0000, 0x0800}] == 0x0000
    end

    test "includes AffectedSOPInstanceUID when provided" do
      cmd = NCreate.build_command_set("1.2.3", 1, sop_instance_uid: "1.2.3.4.5")
      assert cmd[{0x0000, 0x1000}] == "1.2.3.4.5"
    end

    test "omits AffectedSOPInstanceUID when not provided" do
      cmd = NCreate.build_command_set("1.2.3", 1)
      refute Map.has_key?(cmd, {0x0000, 0x1000})
    end
  end
end
