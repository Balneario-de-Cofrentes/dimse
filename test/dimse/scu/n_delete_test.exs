defmodule Dimse.Scu.NDeleteTest do
  use ExUnit.Case, async: true

  alias Dimse.Scu.NDelete
  alias Dimse.Command.Fields

  defmodule FakeAssociation do
    use GenServer

    def start_link(response), do: GenServer.start_link(__MODULE__, response)

    @impl true
    def init(response), do: {:ok, response}

    @impl true
    def handle_call({:dimse_request, _command_set, _data}, _from, response) do
      {:reply, response, response}
    end
  end

  describe "send/4 transport error" do
    test "propagates transport-level error from association" do
      {:ok, assoc} = FakeAssociation.start_link({:error, :timeout})
      assert {:error, :timeout} = NDelete.send(assoc, "1.2.3", "4.5.6")
    end
  end

  describe "build_command_set/3" do
    test "uses RequestedSOPClassUID (0000,0003)" do
      cmd = NDelete.build_command_set("1.2.3", "1.2.3.4", 1)

      assert cmd[{0x0000, 0x0003}] == "1.2.3"
      refute Map.has_key?(cmd, {0x0000, 0x0002})
    end

    test "uses RequestedSOPInstanceUID (0000,1001)" do
      cmd = NDelete.build_command_set("1.2.3", "1.2.3.4.5", 1)

      assert cmd[{0x0000, 0x1001}] == "1.2.3.4.5"
      refute Map.has_key?(cmd, {0x0000, 0x1000})
    end

    test "sets CommandField to N-DELETE-RQ (0x0150)" do
      cmd = NDelete.build_command_set("1.2.3", "1.2.3.4", 1)
      assert cmd[{0x0000, 0x0100}] == Fields.n_delete_rq()
    end

    test "sets MessageID" do
      cmd = NDelete.build_command_set("1.2.3", "1.2.3.4", 13)
      assert cmd[{0x0000, 0x0110}] == 13
    end

    test "sets CommandDataSetType to no data set (0x0101)" do
      cmd = NDelete.build_command_set("1.2.3", "1.2.3.4", 1)
      assert cmd[{0x0000, 0x0800}] == 0x0101
    end
  end
end
