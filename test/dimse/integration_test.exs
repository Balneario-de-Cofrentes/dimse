defmodule Dimse.IntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  defp wait_for_established(assoc, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(assoc, deadline)
  end

  defp do_wait(assoc, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      flunk("Association did not reach :established within timeout")
    end

    contexts = Dimse.Association.negotiated_contexts(assoc)

    if map_size(contexts) > 0 do
      :ok
    else
      Process.sleep(10)
      do_wait(assoc, deadline)
    end
  end

  describe "C-ECHO end-to-end" do
    test "SCU can echo SCP over TCP" do
      {:ok, ref} =
        Dimse.start_listener(
          port: 0,
          handler: Dimse.Scp.Echo
        )

      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TEST_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1"]
        )

      wait_for_established(assoc)

      assert :ok = Dimse.echo(assoc, timeout: 5_000)
      assert :ok = Dimse.release(assoc, 5_000)

      Dimse.stop_listener(ref)
    end

    test "multiple echo requests on same association" do
      {:ok, ref} = Dimse.start_listener(port: 0, handler: Dimse.Scp.Echo)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TEST_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1"]
        )

      wait_for_established(assoc)

      assert :ok = Dimse.echo(assoc, timeout: 5_000)
      assert :ok = Dimse.echo(assoc, timeout: 5_000)
      assert :ok = Dimse.echo(assoc, timeout: 5_000)

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "abort terminates association" do
      {:ok, ref} = Dimse.start_listener(port: 0, handler: Dimse.Scp.Echo)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TEST_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1"]
        )

      wait_for_established(assoc)

      ref_monitor = Process.monitor(assoc)
      Dimse.abort(assoc)

      assert_receive {:DOWN, ^ref_monitor, :process, ^assoc, _reason}, 2_000
      Dimse.stop_listener(ref)
    end

    test "connection refused when no listener" do
      result =
        Dimse.connect("127.0.0.1", 59999,
          calling_ae: "TEST_SCU",
          called_ae: "NOWHERE"
        )

      assert {:error, :econnrefused} = result
    end
  end
end
