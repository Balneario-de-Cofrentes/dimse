defmodule Dimse.IntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"

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

  describe "C-STORE end-to-end" do
    test "SCU can store an instance on SCP" do
      test_pid = self()
      handler = store_handler(test_pid)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      sop_instance_uid = "1.2.3.4.5.6.7.8.9"
      data_set = :crypto.strong_rand_bytes(256)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "STORE_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@ct_image_storage]
        )

      wait_for_established(assoc)

      assert :ok =
               Dimse.store(assoc, @ct_image_storage, sop_instance_uid, data_set, timeout: 5_000)

      assert_receive {:stored, ^data_set}, 2_000

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "multiple store requests on same association" do
      test_pid = self()
      handler = store_handler(test_pid)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "STORE_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@ct_image_storage]
        )

      wait_for_established(assoc)

      for i <- 1..3 do
        uid = "1.2.3.#{i}"
        data = :crypto.strong_rand_bytes(128)
        assert :ok = Dimse.store(assoc, @ct_image_storage, uid, data, timeout: 5_000)
        assert_receive {:stored, ^data}, 2_000
      end

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "large data set store" do
      test_pid = self()
      handler = store_handler(test_pid)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      # 64KB — exceeds default max PDU (16KB), tests fragmentation
      data_set = :crypto.strong_rand_bytes(65_536)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "STORE_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@ct_image_storage]
        )

      wait_for_established(assoc)

      assert :ok =
               Dimse.store(assoc, @ct_image_storage, "1.2.3.99", data_set, timeout: 10_000)

      assert_receive {:stored, ^data_set}, 5_000

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "store with echo on same association" do
      test_pid = self()
      handler = store_echo_handler(test_pid)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "STORE_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1", @ct_image_storage]
        )

      wait_for_established(assoc)

      assert :ok = Dimse.echo(assoc, timeout: 5_000)

      data_set = :crypto.strong_rand_bytes(128)

      assert :ok =
               Dimse.store(assoc, @ct_image_storage, "1.2.3.42", data_set, timeout: 5_000)

      assert_receive {:stored, ^data_set}, 2_000

      assert :ok = Dimse.echo(assoc, timeout: 5_000)
      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end
  end

  # --- Test handler factories ---

  defp store_handler(test_pid) do
    # Create a module at runtime that sends stored data back to the test process
    mod = :"Dimse.Test.StoreHandler.#{System.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          ["1.2.840.10008.5.1.4.1.1.2"]
        end

        @impl true
        def handle_echo(_command, _state), do: {:ok, 0x0000}

        @impl true
        def handle_store(_command, data, _state) do
          send(unquote(test_pid), {:stored, data})
          {:ok, 0x0000}
        end

        @impl true
        def handle_find(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_move(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_get(_command, _query, _state), do: {:error, 0xC000, "not supported"}
      end,
      Macro.Env.location(__ENV__)
    )

    mod
  end

  defp store_echo_handler(test_pid) do
    mod = :"Dimse.Test.StoreEchoHandler.#{System.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          ["1.2.840.10008.1.1", "1.2.840.10008.5.1.4.1.1.2"]
        end

        @impl true
        def handle_echo(_command, _state), do: {:ok, 0x0000}

        @impl true
        def handle_store(_command, data, _state) do
          send(unquote(test_pid), {:stored, data})
          {:ok, 0x0000}
        end

        @impl true
        def handle_find(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_move(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_get(_command, _query, _state), do: {:error, 0xC000, "not supported"}
      end,
      Macro.Env.location(__ENV__)
    )

    mod
  end
end
