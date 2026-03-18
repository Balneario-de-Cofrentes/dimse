defmodule Dimse.Scu.MoveTest do
  use ExUnit.Case, async: true

  alias Dimse.Scu.Move
  alias Dimse.Command.Fields

  describe "sop_class_uid/1" do
    test "returns Patient Root C-MOVE UID for :patient" do
      assert Move.sop_class_uid(:patient) == "1.2.840.10008.5.1.4.1.2.1.2"
    end

    test "returns Study Root C-MOVE UID for :study" do
      assert Move.sop_class_uid(:study) == "1.2.840.10008.5.1.4.1.2.2.2"
    end

    test "returns nil for unknown level" do
      assert Move.sop_class_uid(:unknown) == nil
    end
  end

  describe "build_command_set/4" do
    test "builds a valid C-MOVE-RQ command set" do
      sop_class = "1.2.840.10008.5.1.4.1.2.2.2"
      cmd = Move.build_command_set(sop_class, 42, "DEST_AE")

      assert cmd[{0x0000, 0x0002}] == sop_class
      assert cmd[{0x0000, 0x0100}] == Fields.c_move_rq()
      assert cmd[{0x0000, 0x0110}] == 42
      assert cmd[{0x0000, 0x0600}] == "DEST_AE"
      assert cmd[{0x0000, 0x0700}] == 0x0000
      assert cmd[{0x0000, 0x0800}] == 0x0000
    end

    test "accepts custom priority" do
      cmd = Move.build_command_set("1.2.3", 1, "DEST", priority: 0x0002)
      assert cmd[{0x0000, 0x0700}] == 0x0002
    end
  end
end
