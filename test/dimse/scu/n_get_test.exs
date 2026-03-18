defmodule Dimse.Scu.NGetTest do
  use ExUnit.Case, async: true

  alias Dimse.Scu.NGet
  alias Dimse.Command.Fields

  describe "build_command_set/3" do
    test "uses RequestedSOPClassUID (0000,0003)" do
      sop_class = "1.2.840.10008.5.1.4.1.1.1"
      sop_instance = "1.2.3.4.5"
      cmd = NGet.build_command_set(sop_class, sop_instance, 1)

      assert cmd[{0x0000, 0x0003}] == sop_class
      refute Map.has_key?(cmd, {0x0000, 0x0002})
    end

    test "uses RequestedSOPInstanceUID (0000,1001)" do
      sop_instance = "1.2.3.4.5"
      cmd = NGet.build_command_set("1.2.3", sop_instance, 1)

      assert cmd[{0x0000, 0x1001}] == sop_instance
      refute Map.has_key?(cmd, {0x0000, 0x1000})
    end

    test "sets CommandField to N-GET-RQ (0x0110)" do
      cmd = NGet.build_command_set("1.2.3", "1.2.3.4", 1)
      assert cmd[{0x0000, 0x0100}] == Fields.n_get_rq()
    end

    test "sets MessageID" do
      cmd = NGet.build_command_set("1.2.3", "1.2.3.4", 42)
      assert cmd[{0x0000, 0x0110}] == 42
    end

    test "sets CommandDataSetType to no data set (0x0101)" do
      cmd = NGet.build_command_set("1.2.3", "1.2.3.4", 1)
      assert cmd[{0x0000, 0x0800}] == 0x0101
    end

    test "includes AttributeIdentifierList when provided" do
      attrs = [{0x0010, 0x0010}, {0x0010, 0x0020}]
      cmd = NGet.build_command_set("1.2.3", "1.2.3.4", 1, attribute_identifier_list: attrs)

      assert cmd[{0x0000, 0x1005}] == attrs
    end

    test "omits AttributeIdentifierList when not provided" do
      cmd = NGet.build_command_set("1.2.3", "1.2.3.4", 1)
      refute Map.has_key?(cmd, {0x0000, 0x1005})
    end
  end
end
