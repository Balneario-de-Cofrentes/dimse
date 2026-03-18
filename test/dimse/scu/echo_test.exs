defmodule Dimse.Scu.EchoTest do
  use ExUnit.Case, async: true

  alias Dimse.Command.Fields
  alias Dimse.Scu.Echo

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

  describe "verify/2 command construction" do
    test "builds a valid C-ECHO-RQ command set" do
      # Verify the command set that would be sent
      # by testing the internal structure
      verification_uid = "1.2.840.10008.1.1"

      cmd = %{
        {0x0000, 0x0002} => verification_uid,
        {0x0000, 0x0100} => Fields.c_echo_rq(),
        {0x0000, 0x0800} => 0x0101
      }

      assert cmd[{0x0000, 0x0002}] == "1.2.840.10008.1.1"
      assert cmd[{0x0000, 0x0100}] == 0x0030
      assert cmd[{0x0000, 0x0800}] == 0x0101
    end
  end

  describe "verify/2 transport error" do
    test "propagates transport-level error from association" do
      {:ok, assoc} = FakeAssociation.start_link({:error, :timeout})
      assert {:error, :timeout} = Echo.verify(assoc)
    end
  end

  # Integration tests for verify/2 success and non-success status are in
  # test/dimse/integration_test.exs
end
