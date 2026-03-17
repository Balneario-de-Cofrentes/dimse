defmodule Dimse.Scu.EchoTest do
  use ExUnit.Case, async: true

  alias Dimse.Scu.Echo

  describe "verify/2" do
    test "returns {:error, :not_implemented} for now" do
      assert {:error, :not_implemented} = Echo.verify(self())
    end
  end

  # TODO: Integration tests with a real SCP
  #
  # describe "verify/2 integration" do
  #   test "verifies connectivity with a C-ECHO SCP" do
  #     {:ok, _ref} = Dimse.start_listener(
  #       port: 0,
  #       handler: Dimse.Scp.Echo
  #     )
  #
  #     {:ok, assoc} = Dimse.Scu.open("127.0.0.1", port,
  #       calling_ae: "TEST_SCU",
  #       called_ae: "DIMSE",
  #       abstract_syntaxes: ["1.2.840.10008.1.1"]
  #     )
  #
  #     assert :ok = Echo.verify(assoc)
  #     :ok = Dimse.Scu.release(assoc)
  #   end
  # end
end
