defmodule Dimse.Scp.EchoTest do
  use ExUnit.Case, async: true

  alias Dimse.Scp.Echo

  describe "supported_abstract_syntaxes/0" do
    test "returns Verification SOP class" do
      assert ["1.2.840.10008.1.1"] = Echo.supported_abstract_syntaxes()
    end
  end

  describe "unsupported service callbacks" do
    test "handle_store returns not-supported error" do
      assert {:error, 0xC000, "not supported"} = Echo.handle_store(%{}, <<>>, nil)
    end

    test "handle_find returns not-supported error" do
      assert {:error, 0xC000, "not supported"} = Echo.handle_find(%{}, <<>>, nil)
    end

    test "handle_move returns not-supported error" do
      assert {:error, 0xA801, "not supported"} = Echo.handle_move(%{}, <<>>, nil)
    end

    test "handle_get returns not-supported error" do
      assert {:error, 0xA900, "not supported"} = Echo.handle_get(%{}, <<>>, nil)
    end
  end
end
