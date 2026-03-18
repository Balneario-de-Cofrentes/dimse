defmodule Dimse.ListenerTest do
  use ExUnit.Case, async: true

  alias Dimse.Listener

  describe "child_spec/1" do
    test "returns a Ranch child spec map" do
      spec = Listener.child_spec(port: 11112, handler: Dimse.Scp.Echo)

      # Ranch child_spec returns a map with :id, :start, :restart, :type fields
      assert is_map(spec)
      assert Map.has_key?(spec, :id) or Map.has_key?(spec, :start)
    end

    test "accepts custom ref option" do
      ref = make_ref()
      spec1 = Listener.child_spec(port: 11112, handler: Dimse.Scp.Echo, ref: ref)
      spec2 = Listener.child_spec(port: 11112, handler: Dimse.Scp.Echo, ref: ref)
      assert spec1 == spec2
    end
  end
end
