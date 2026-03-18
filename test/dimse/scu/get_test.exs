defmodule Dimse.Scu.GetTest do
  use ExUnit.Case, async: true

  alias Dimse.Scu.Get
  alias Dimse.Command.Fields

  defmodule FakeAssociation do
    use GenServer

    def start_link(response), do: GenServer.start_link(__MODULE__, response)

    @impl true
    def init(response), do: {:ok, response}

    @impl true
    def handle_call({:dimse_get_request, _command_set, _data}, _from, response) do
      {:reply, response, response}
    end
  end

  describe "retrieve/4 response handling" do
    test "returns {:ok, results} for success status 0x0000" do
      {:ok, assoc} = FakeAssociation.start_link({:ok, %{{0x0000, 0x0900} => 0x0000}, [<<1>>]})
      assert {:ok, [<<1>>]} = Get.retrieve(assoc, "1.2.3", <<>>)
    end

    test "returns {:ok, results} when status is 0xFE00 (cancelled with partial results)" do
      {:ok, assoc} = FakeAssociation.start_link({:ok, %{{0x0000, 0x0900} => 0xFE00}, [<<2>>]})
      assert {:ok, [<<2>>]} = Get.retrieve(assoc, "1.2.3", <<>>)
    end

    test "returns {:error, {:status, code}} for non-success status" do
      {:ok, assoc} = FakeAssociation.start_link({:ok, %{{0x0000, 0x0900} => 0xA701}, []})
      assert {:error, {:status, 0xA701}} = Get.retrieve(assoc, "1.2.3", <<>>)
    end

    test "propagates transport-level error from association" do
      {:ok, assoc} = FakeAssociation.start_link({:error, :timeout})
      assert {:error, :timeout} = Get.retrieve(assoc, "1.2.3", <<>>)
    end
  end

  describe "sop_class_uid/1" do
    test "returns Patient Root C-GET UID for :patient" do
      assert Get.sop_class_uid(:patient) == "1.2.840.10008.5.1.4.1.2.1.3"
    end

    test "returns Study Root C-GET UID for :study" do
      assert Get.sop_class_uid(:study) == "1.2.840.10008.5.1.4.1.2.2.3"
    end

    test "returns nil for unknown level" do
      assert Get.sop_class_uid(:unknown) == nil
    end
  end

  describe "build_command_set/3" do
    test "builds a valid C-GET-RQ command set" do
      sop_class = "1.2.840.10008.5.1.4.1.2.2.3"
      cmd = Get.build_command_set(sop_class, 99)

      assert cmd[{0x0000, 0x0002}] == sop_class
      assert cmd[{0x0000, 0x0100}] == Fields.c_get_rq()
      assert cmd[{0x0000, 0x0110}] == 99
      assert cmd[{0x0000, 0x0700}] == 0x0000
      assert cmd[{0x0000, 0x0800}] == 0x0000
    end

    test "accepts custom priority" do
      cmd = Get.build_command_set("1.2.3", 1, priority: 0x0001)
      assert cmd[{0x0000, 0x0700}] == 0x0001
    end
  end
end
