defmodule Dimse.Scu.NEventReportTest do
  use ExUnit.Case, async: true

  alias Dimse.Scu.NEventReport
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

  describe "send/6 transport error" do
    test "propagates transport-level error from association" do
      {:ok, assoc} = FakeAssociation.start_link({:error, :timeout})
      assert {:error, :timeout} = NEventReport.send(assoc, "1.2.3", "4.5.6", 1, nil)
    end
  end

  describe "build_command_set/4" do
    test "uses AffectedSOPClassUID (0000,0002)" do
      cmd = NEventReport.build_command_set("1.2.3", "1.2.3.4", 1, 1)

      assert cmd[{0x0000, 0x0002}] == "1.2.3"
      refute Map.has_key?(cmd, {0x0000, 0x0003})
    end

    test "uses AffectedSOPInstanceUID (0000,1000)" do
      cmd = NEventReport.build_command_set("1.2.3", "1.2.3.4.5", 1, 1)

      assert cmd[{0x0000, 0x1000}] == "1.2.3.4.5"
      refute Map.has_key?(cmd, {0x0000, 0x1001})
    end

    test "sets CommandField to N-EVENT-REPORT-RQ (0x0100)" do
      cmd = NEventReport.build_command_set("1.2.3", "1.2.3.4", 1, 1)
      assert cmd[{0x0000, 0x0100}] == Fields.n_event_report_rq()
    end

    test "sets EventTypeID (0000,1002)" do
      cmd = NEventReport.build_command_set("1.2.3", "1.2.3.4", 1, 5)
      assert cmd[{0x0000, 0x1002}] == 5
    end

    test "sets CommandDataSetType to data set present (0x0000)" do
      cmd = NEventReport.build_command_set("1.2.3", "1.2.3.4", 1, 1)
      assert cmd[{0x0000, 0x0800}] == 0x0000
    end

    test "sets MessageID" do
      cmd = NEventReport.build_command_set("1.2.3", "1.2.3.4", 77, 1)
      assert cmd[{0x0000, 0x0110}] == 77
    end
  end
end
