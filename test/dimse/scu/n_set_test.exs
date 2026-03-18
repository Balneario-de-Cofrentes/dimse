defmodule Dimse.Scu.NSetTest do
  use ExUnit.Case, async: true

  alias Dimse.Scu.NSet
  alias Dimse.Command.Fields

  describe "build_command_set/3" do
    test "uses RequestedSOPClassUID (0000,0003)" do
      cmd = NSet.build_command_set("1.2.3", "1.2.3.4", 1)

      assert cmd[{0x0000, 0x0003}] == "1.2.3"
      refute Map.has_key?(cmd, {0x0000, 0x0002})
    end

    test "uses RequestedSOPInstanceUID (0000,1001)" do
      cmd = NSet.build_command_set("1.2.3", "1.2.3.4.5", 1)

      assert cmd[{0x0000, 0x1001}] == "1.2.3.4.5"
      refute Map.has_key?(cmd, {0x0000, 0x1000})
    end

    test "sets CommandField to N-SET-RQ (0x0120)" do
      cmd = NSet.build_command_set("1.2.3", "1.2.3.4", 1)
      assert cmd[{0x0000, 0x0100}] == Fields.n_set_rq()
    end

    test "sets MessageID" do
      cmd = NSet.build_command_set("1.2.3", "1.2.3.4", 7)
      assert cmd[{0x0000, 0x0110}] == 7
    end

    test "sets CommandDataSetType to data set present (0x0000)" do
      cmd = NSet.build_command_set("1.2.3", "1.2.3.4", 1)
      assert cmd[{0x0000, 0x0800}] == 0x0000
    end
  end
end
