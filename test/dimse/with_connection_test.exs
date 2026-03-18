defmodule Dimse.WithConnectionTest do
  use ExUnit.Case

  describe "with_connection/4" do
    test "connects, executes function, and releases" do
      {:ok, ref} = Dimse.start_listener(port: 0, handler: Dimse.Scp.Echo)
      port = :ranch.get_port(ref)

      assert {:ok, :echo_ok} =
               Dimse.with_connection(
                 "127.0.0.1",
                 port,
                 [calling_ae: "SCU", called_ae: "DIMSE"],
                 fn assoc ->
                   :ok = Dimse.echo(assoc, timeout: 5_000)
                   :echo_ok
                 end
               )

      Dimse.stop_listener(ref)
    end

    test "returns function result on success" do
      {:ok, ref} = Dimse.start_listener(port: 0, handler: Dimse.Scp.Echo)
      port = :ranch.get_port(ref)

      assert {:ok, 42} =
               Dimse.with_connection("127.0.0.1", port, [calling_ae: "SCU"], fn _assoc ->
                 42
               end)

      Dimse.stop_listener(ref)
    end

    test "returns error when connection fails" do
      assert {:error, :econnrefused} =
               Dimse.with_connection("127.0.0.1", 59999, [calling_ae: "SCU"], fn _assoc ->
                 flunk("should not be called")
               end)
    end

    test "aborts connection on exception and reraises" do
      {:ok, ref} = Dimse.start_listener(port: 0, handler: Dimse.Scp.Echo)
      port = :ranch.get_port(ref)

      assert_raise RuntimeError, "boom", fn ->
        Dimse.with_connection("127.0.0.1", port, [calling_ae: "SCU"], fn _assoc ->
          raise "boom"
        end)
      end

      Dimse.stop_listener(ref)
    end

    test "aborts connection on throw and rethrows" do
      {:ok, ref} = Dimse.start_listener(port: 0, handler: Dimse.Scp.Echo)
      port = :ranch.get_port(ref)

      assert catch_throw(
               Dimse.with_connection("127.0.0.1", port, [calling_ae: "SCU"], fn _assoc ->
                 throw(:bail)
               end)
             ) == :bail

      Dimse.stop_listener(ref)
    end
  end
end
