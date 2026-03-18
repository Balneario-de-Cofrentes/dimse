defmodule Dimse.Scu.MoveTest do
  use ExUnit.Case, async: true

  alias Dimse.Scu.Move
  alias Dimse.Command.Fields

  defmodule FakeAssociation do
    use GenServer

    def start_link(response), do: GenServer.start_link(__MODULE__, response)

    @impl true
    def init(response), do: {:ok, response}

    @impl true
    def handle_call({:dimse_find_request, _command_set, _data}, _from, response) do
      {:reply, response, response}
    end
  end

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

  describe "retrieve/5 response handling" do
    test "returns {:ok, counts} for success status 0x0000" do
      response = %{
        {0x0000, 0x0900} => 0x0000,
        {0x0000, 0x1021} => 2,
        {0x0000, 0x1022} => 1,
        {0x0000, 0x1023} => 0
      }

      {:ok, assoc} = FakeAssociation.start_link({:ok, response, []})

      assert {:ok, %{completed: 2, failed: 1, warning: 0}} =
               Move.retrieve(assoc, "1.2.3", <<>>, "DEST")
    end

    test "returns {:ok, counts} when status is 0xFE00 (cancelled with partial results)" do
      response = %{{0x0000, 0x0900} => 0xFE00, {0x0000, 0x1021} => 1, {0x0000, 0x1022} => 0}
      {:ok, assoc} = FakeAssociation.start_link({:ok, response, []})
      assert {:ok, %{completed: 1}} = Move.retrieve(assoc, "1.2.3", <<>>, "DEST")
    end

    test "returns {:error, {:status, code}} for non-success status" do
      {:ok, assoc} = FakeAssociation.start_link({:ok, %{{0x0000, 0x0900} => 0xA701}, []})
      assert {:error, {:status, 0xA701}} = Move.retrieve(assoc, "1.2.3", <<>>, "DEST")
    end

    test "propagates transport-level error from association" do
      {:ok, assoc} = FakeAssociation.start_link({:error, :timeout})
      assert {:error, :timeout} = Move.retrieve(assoc, "1.2.3", <<>>, "DEST")
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
