defmodule Dimse.Scu.FindTest do
  use ExUnit.Case, async: true

  alias Dimse.Scu.Find

  @study_root_find "1.2.840.10008.5.1.4.1.2.2.1"
  @patient_root_find "1.2.840.10008.5.1.4.1.2.1.1"
  @worklist_find "1.2.840.10008.5.1.4.31"

  describe "sop_class_uid/1" do
    test "maps :patient to Patient Root Q/R - FIND" do
      assert Find.sop_class_uid(:patient) == @patient_root_find
    end

    test "maps :study to Study Root Q/R - FIND" do
      assert Find.sop_class_uid(:study) == @study_root_find
    end

    test "maps :worklist to Modality Worklist - FIND" do
      assert Find.sop_class_uid(:worklist) == @worklist_find
    end

    test "returns nil for unknown level" do
      assert Find.sop_class_uid(:unknown) == nil
    end
  end

  describe "build_command_set/3" do
    test "builds correct C-FIND-RQ command set" do
      cmd = Find.build_command_set(@study_root_find, 42)

      # AffectedSOPClassUID
      assert cmd[{0x0000, 0x0002}] == @study_root_find
      # CommandField = C-FIND-RQ (0x0020)
      assert cmd[{0x0000, 0x0100}] == 0x0020
      # MessageID
      assert cmd[{0x0000, 0x0110}] == 42
      # Priority = MEDIUM (default)
      assert cmd[{0x0000, 0x0700}] == 0x0000
      # CommandDataSetType = data set present (query identifier follows)
      assert cmd[{0x0000, 0x0800}] == 0x0000
    end

    test "applies priority option" do
      cmd = Find.build_command_set(@study_root_find, 1, priority: 0x0001)

      assert cmd[{0x0000, 0x0700}] == 0x0001
    end
  end
end
