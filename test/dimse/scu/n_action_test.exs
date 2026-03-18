defmodule Dimse.Scu.NActionTest do
  use ExUnit.Case, async: true

  alias Dimse.Scu.NAction
  alias Dimse.Command.Fields

  describe "build_command_set/4" do
    test "uses RequestedSOPClassUID (0000,0003)" do
      cmd = NAction.build_command_set("1.2.3", "1.2.3.4", 1, 1)

      assert cmd[{0x0000, 0x0003}] == "1.2.3"
      refute Map.has_key?(cmd, {0x0000, 0x0002})
    end

    test "uses RequestedSOPInstanceUID (0000,1001)" do
      cmd = NAction.build_command_set("1.2.3", "1.2.3.4.5", 1, 1)

      assert cmd[{0x0000, 0x1001}] == "1.2.3.4.5"
      refute Map.has_key?(cmd, {0x0000, 0x1000})
    end

    test "sets CommandField to N-ACTION-RQ (0x0130)" do
      cmd = NAction.build_command_set("1.2.3", "1.2.3.4", 1, 1)
      assert cmd[{0x0000, 0x0100}] == Fields.n_action_rq()
    end

    test "sets ActionTypeID (0000,1008)" do
      cmd = NAction.build_command_set("1.2.3", "1.2.3.4", 1, 3)
      assert cmd[{0x0000, 0x1008}] == 3
    end

    test "sets CommandDataSetType to data set present (0x0000)" do
      cmd = NAction.build_command_set("1.2.3", "1.2.3.4", 1, 1)
      assert cmd[{0x0000, 0x0800}] == 0x0000
    end

    test "sets MessageID" do
      cmd = NAction.build_command_set("1.2.3", "1.2.3.4", 99, 1)
      assert cmd[{0x0000, 0x0110}] == 99
    end
  end
end
