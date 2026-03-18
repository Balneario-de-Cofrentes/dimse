defmodule Dimse.IntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"
  @study_root_find "1.2.840.10008.5.1.4.1.2.2.1"
  @study_root_get "1.2.840.10008.5.1.4.1.2.2.3"
  @study_root_move "1.2.840.10008.5.1.4.1.2.2.2"

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

  describe "C-FIND end-to-end" do
    test "SCU receives matching results from SCP" do
      test_pid = self()
      result1 = :crypto.strong_rand_bytes(64)
      result2 = :crypto.strong_rand_bytes(96)
      handler = find_handler(test_pid, [result1, result2])

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "FIND_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_find]
        )

      wait_for_established(assoc)

      query_data = :crypto.strong_rand_bytes(32)
      assert {:ok, results} = Dimse.find(assoc, @study_root_find, query_data, timeout: 5_000)

      assert length(results) == 2
      assert Enum.at(results, 0) == result1
      assert Enum.at(results, 1) == result2

      assert_receive {:find_query, ^query_data}, 2_000

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "empty results return empty list" do
      test_pid = self()
      handler = find_handler(test_pid, [])

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "FIND_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_find]
        )

      wait_for_established(assoc)

      assert {:ok, []} = Dimse.find(assoc, @study_root_find, <<>>, timeout: 5_000)

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "many results (10)" do
      test_pid = self()
      results = for _ <- 1..10, do: :crypto.strong_rand_bytes(48)
      handler = find_handler(test_pid, results)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "FIND_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_find]
        )

      wait_for_established(assoc)

      assert {:ok, received} = Dimse.find(assoc, @study_root_find, <<>>, timeout: 5_000)
      assert length(received) == 10
      assert received == results

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "handler error returns failure" do
      test_pid = self()
      handler = find_error_handler(test_pid)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "FIND_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_find]
        )

      wait_for_established(assoc)

      assert {:error, {:status, status}} =
               Dimse.find(assoc, @study_root_find, <<>>, timeout: 5_000)

      assert status == 0xA700

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "find with echo on same association" do
      test_pid = self()
      result1 = :crypto.strong_rand_bytes(64)
      handler = find_echo_handler(test_pid, [result1])

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "FIND_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1", @study_root_find]
        )

      wait_for_established(assoc)

      assert :ok = Dimse.echo(assoc, timeout: 5_000)
      assert {:ok, [^result1]} = Dimse.find(assoc, @study_root_find, <<>>, timeout: 5_000)
      assert :ok = Dimse.echo(assoc, timeout: 5_000)

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "multiple find requests on same association" do
      test_pid = self()
      results1 = [:crypto.strong_rand_bytes(32)]
      results2 = [:crypto.strong_rand_bytes(48), :crypto.strong_rand_bytes(48)]
      handler = find_handler(test_pid, results1, results2)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "FIND_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_find]
        )

      wait_for_established(assoc)

      assert {:ok, received1} = Dimse.find(assoc, @study_root_find, <<>>, timeout: 5_000)
      assert received1 == results1

      assert {:ok, received2} = Dimse.find(assoc, @study_root_find, <<>>, timeout: 5_000)
      assert received2 == results2

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "find with query level convenience atom" do
      test_pid = self()
      result1 = :crypto.strong_rand_bytes(64)
      handler = find_handler(test_pid, [result1])

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "FIND_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_find]
        )

      wait_for_established(assoc)

      assert {:ok, [^result1]} = Dimse.find(assoc, :study, <<>>, timeout: 5_000)

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "C-CANCEL is sent and SCP handles it gracefully" do
      test_pid = self()
      handler = find_slow_handler(test_pid)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "FIND_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_find]
        )

      wait_for_established(assoc)

      # Start find in a task, then cancel it
      find_task =
        Task.async(fn ->
          Dimse.find(assoc, @study_root_find, <<>>, timeout: 10_000)
        end)

      # Wait for the handler to start processing
      assert_receive {:find_started, message_id}, 2_000

      # Send C-CANCEL — with synchronous handlers, the find will complete
      # but the cancel should not crash the association
      :ok = Dimse.cancel(assoc, message_id)

      # The find completes with all results (handler is synchronous)
      assert {:ok, results} = Task.await(find_task, 10_000)
      assert is_list(results)

      # Association should still be usable after cancel
      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end
  end

  describe "C-GET end-to-end" do
    test "SCU receives instances via C-GET on same association" do
      test_pid = self()
      instance1 = :crypto.strong_rand_bytes(128)
      instance2 = :crypto.strong_rand_bytes(256)

      instances = [
        {"1.2.840.10008.5.1.4.1.1.2", "1.2.3.4.1", instance1},
        {"1.2.840.10008.5.1.4.1.1.2", "1.2.3.4.2", instance2}
      ]

      handler = get_handler(test_pid, instances)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "GET_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_get, @ct_image_storage]
        )

      wait_for_established(assoc)

      query_data = :crypto.strong_rand_bytes(32)
      assert {:ok, results} = Dimse.get(assoc, :study, query_data, timeout: 10_000)

      assert length(results) == 2
      assert Enum.at(results, 0) == instance1
      assert Enum.at(results, 1) == instance2

      assert_receive {:get_query, ^query_data}, 2_000

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "empty C-GET results return empty list" do
      test_pid = self()
      handler = get_handler(test_pid, [])

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "GET_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_get, @ct_image_storage]
        )

      wait_for_established(assoc)

      assert {:ok, []} = Dimse.get(assoc, :study, <<>>, timeout: 5_000)

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "C-GET handler error returns failure" do
      test_pid = self()
      handler = get_error_handler(test_pid)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "GET_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_get, @ct_image_storage]
        )

      wait_for_established(assoc)

      assert {:error, {:status, 0xA700}} = Dimse.get(assoc, :study, <<>>, timeout: 5_000)

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "C-GET with echo on same association" do
      test_pid = self()
      instance1 = :crypto.strong_rand_bytes(64)

      instances = [{"1.2.840.10008.5.1.4.1.1.2", "1.2.3.4.1", instance1}]
      handler = get_echo_handler(test_pid, instances)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "GET_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1", @study_root_get, @ct_image_storage]
        )

      wait_for_established(assoc)

      assert :ok = Dimse.echo(assoc, timeout: 5_000)
      assert {:ok, [^instance1]} = Dimse.get(assoc, :study, <<>>, timeout: 10_000)
      assert :ok = Dimse.echo(assoc, timeout: 5_000)

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end
  end

  describe "C-MOVE end-to-end" do
    test "SCU sends C-MOVE-RQ and destination SCP receives C-STORE" do
      test_pid = self()

      # Start destination SCP first
      dest_handler = store_dest_handler(test_pid)
      {:ok, dest_ref} = Dimse.start_listener(port: 0, handler: dest_handler)
      dest_port = :ranch.get_port(dest_ref)

      instance1 = :crypto.strong_rand_bytes(128)
      instance2 = :crypto.strong_rand_bytes(256)

      instances = [
        {"1.2.840.10008.5.1.4.1.1.2", "1.2.3.4.1", instance1},
        {"1.2.840.10008.5.1.4.1.1.2", "1.2.3.4.2", instance2}
      ]

      handler = move_handler(test_pid, instances, dest_port)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "MOVE_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_move]
        )

      wait_for_established(assoc)

      query_data = :crypto.strong_rand_bytes(32)

      assert {:ok, result} =
               Dimse.move(assoc, :study, query_data, dest_ae: "DEST_SCP", timeout: 10_000)

      assert result.completed == 2
      assert result.failed == 0

      # Verify destination received the instances
      assert_receive {:dest_stored, ^instance1}, 5_000
      assert_receive {:dest_stored, ^instance2}, 5_000
      assert_receive {:move_query, ^query_data}, 2_000

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
      Dimse.stop_listener(dest_ref)
    end

    test "empty C-MOVE results return success with zero counts" do
      test_pid = self()

      dest_handler = store_dest_handler(test_pid)
      {:ok, dest_ref} = Dimse.start_listener(port: 0, handler: dest_handler)
      dest_port = :ranch.get_port(dest_ref)

      handler = move_handler(test_pid, [], dest_port)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "MOVE_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_move]
        )

      wait_for_established(assoc)

      assert {:ok, result} =
               Dimse.move(assoc, :study, <<>>, dest_ae: "DEST_SCP", timeout: 5_000)

      assert result.completed == 0
      assert result.failed == 0

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
      Dimse.stop_listener(dest_ref)
    end

    test "C-MOVE handler error returns failure" do
      test_pid = self()
      handler = move_error_handler(test_pid)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "MOVE_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_move]
        )

      wait_for_established(assoc)

      assert {:error, {:status, 0xA700}} =
               Dimse.move(assoc, :study, <<>>, dest_ae: "DEST_SCP", timeout: 5_000)

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "C-MOVE resolve_ae failure returns error" do
      test_pid = self()

      instance1 = :crypto.strong_rand_bytes(64)
      instances = [{"1.2.840.10008.5.1.4.1.1.2", "1.2.3.4.1", instance1}]

      # Use port 0 — resolve_ae will return unknown_ae error
      handler = move_unknown_dest_handler(test_pid, instances)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "MOVE_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_move]
        )

      wait_for_established(assoc)

      assert {:error, {:status, status}} =
               Dimse.move(assoc, :study, <<>>, dest_ae: "UNKNOWN_AE", timeout: 5_000)

      # 0xA801 = Move Destination unknown (PS3.4 Table C.4-2)
      assert status == 0xA801

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "C-MOVE with echo on same association" do
      test_pid = self()

      dest_handler = store_dest_handler(test_pid)
      {:ok, dest_ref} = Dimse.start_listener(port: 0, handler: dest_handler)
      dest_port = :ranch.get_port(dest_ref)

      instance1 = :crypto.strong_rand_bytes(64)
      instances = [{"1.2.840.10008.5.1.4.1.1.2", "1.2.3.4.1", instance1}]
      handler = move_echo_handler(test_pid, instances, dest_port)

      {:ok, ref} = Dimse.start_listener(port: 0, handler: handler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "MOVE_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1", @study_root_move]
        )

      wait_for_established(assoc)

      assert :ok = Dimse.echo(assoc, timeout: 5_000)

      assert {:ok, result} =
               Dimse.move(assoc, :study, <<>>, dest_ae: "DEST_SCP", timeout: 10_000)

      assert result.completed == 1

      assert :ok = Dimse.echo(assoc, timeout: 5_000)
      assert :ok = Dimse.release(assoc, 5_000)

      Dimse.stop_listener(ref)
      Dimse.stop_listener(dest_ref)
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

  defp find_handler(test_pid, results, results2 \\ nil) do
    mod = :"Dimse.Test.FindHandler.#{System.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          ["1.2.840.10008.5.1.4.1.2.2.1"]
        end

        @impl true
        def handle_echo(_command, _state), do: {:ok, 0x0000}

        @impl true
        def handle_store(_command, _data, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_find(_command, query, _state) do
          send(unquote(test_pid), {:find_query, query})

          # Support alternating results for sequential find tests
          case Process.get(:find_call_count, 0) do
            0 ->
              Process.put(:find_call_count, 1)
              {:ok, unquote(Macro.escape(results))}

            _ ->
              results2 = unquote(Macro.escape(results2))
              if results2, do: {:ok, results2}, else: {:ok, unquote(Macro.escape(results))}
          end
        end

        @impl true
        def handle_move(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_get(_command, _query, _state), do: {:error, 0xC000, "not supported"}
      end,
      Macro.Env.location(__ENV__)
    )

    mod
  end

  defp find_error_handler(test_pid) do
    mod = :"Dimse.Test.FindErrorHandler.#{System.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          ["1.2.840.10008.5.1.4.1.2.2.1"]
        end

        @impl true
        def handle_echo(_command, _state), do: {:ok, 0x0000}

        @impl true
        def handle_store(_command, _data, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_find(_command, _query, _state) do
          send(unquote(test_pid), :find_error_called)
          {:error, 0xA700, "out of resources"}
        end

        @impl true
        def handle_move(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_get(_command, _query, _state), do: {:error, 0xC000, "not supported"}
      end,
      Macro.Env.location(__ENV__)
    )

    mod
  end

  defp find_echo_handler(test_pid, results) do
    mod = :"Dimse.Test.FindEchoHandler.#{System.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          ["1.2.840.10008.1.1", "1.2.840.10008.5.1.4.1.2.2.1"]
        end

        @impl true
        def handle_echo(_command, _state), do: {:ok, 0x0000}

        @impl true
        def handle_store(_command, _data, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_find(_command, _query, _state) do
          send(unquote(test_pid), :find_called)
          {:ok, unquote(Macro.escape(results))}
        end

        @impl true
        def handle_move(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_get(_command, _query, _state), do: {:error, 0xC000, "not supported"}
      end,
      Macro.Env.location(__ENV__)
    )

    mod
  end

  # --- C-GET handler factories ---

  defp get_handler(test_pid, instances) do
    mod = :"Dimse.Test.GetHandler.#{System.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          ["1.2.840.10008.5.1.4.1.2.2.3", "1.2.840.10008.5.1.4.1.1.2"]
        end

        @impl true
        def handle_echo(_command, _state), do: {:ok, 0x0000}

        @impl true
        def handle_store(_command, _data, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_find(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_move(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_get(_command, query, _state) do
          send(unquote(test_pid), {:get_query, query})
          {:ok, unquote(Macro.escape(instances))}
        end
      end,
      Macro.Env.location(__ENV__)
    )

    mod
  end

  defp get_error_handler(test_pid) do
    mod = :"Dimse.Test.GetErrorHandler.#{System.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          ["1.2.840.10008.5.1.4.1.2.2.3", "1.2.840.10008.5.1.4.1.1.2"]
        end

        @impl true
        def handle_echo(_command, _state), do: {:ok, 0x0000}

        @impl true
        def handle_store(_command, _data, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_find(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_move(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_get(_command, _query, _state) do
          send(unquote(test_pid), :get_error_called)
          {:error, 0xA700, "out of resources"}
        end
      end,
      Macro.Env.location(__ENV__)
    )

    mod
  end

  defp get_echo_handler(test_pid, instances) do
    mod = :"Dimse.Test.GetEchoHandler.#{System.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          ["1.2.840.10008.1.1", "1.2.840.10008.5.1.4.1.2.2.3", "1.2.840.10008.5.1.4.1.1.2"]
        end

        @impl true
        def handle_echo(_command, _state), do: {:ok, 0x0000}

        @impl true
        def handle_store(_command, _data, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_find(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_move(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_get(_command, _query, _state) do
          send(unquote(test_pid), :get_called)
          {:ok, unquote(Macro.escape(instances))}
        end
      end,
      Macro.Env.location(__ENV__)
    )

    mod
  end

  # --- C-MOVE handler factories ---

  defp move_handler(test_pid, instances, dest_port) do
    mod = :"Dimse.Test.MoveHandler.#{System.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          ["1.2.840.10008.5.1.4.1.2.2.2"]
        end

        @impl true
        def handle_echo(_command, _state), do: {:ok, 0x0000}

        @impl true
        def handle_store(_command, _data, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_find(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_move(_command, query, _state) do
          send(unquote(test_pid), {:move_query, query})
          {:ok, unquote(Macro.escape(instances))}
        end

        @impl true
        def handle_get(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        def resolve_ae("DEST_SCP"), do: {:ok, {"127.0.0.1", unquote(dest_port)}}
        def resolve_ae(_), do: {:error, :unknown_ae}
      end,
      Macro.Env.location(__ENV__)
    )

    mod
  end

  defp move_echo_handler(test_pid, instances, dest_port) do
    mod = :"Dimse.Test.MoveEchoHandler.#{System.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          ["1.2.840.10008.1.1", "1.2.840.10008.5.1.4.1.2.2.2"]
        end

        @impl true
        def handle_echo(_command, _state), do: {:ok, 0x0000}

        @impl true
        def handle_store(_command, _data, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_find(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_move(_command, _query, _state) do
          send(unquote(test_pid), :move_called)
          {:ok, unquote(Macro.escape(instances))}
        end

        @impl true
        def handle_get(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        def resolve_ae("DEST_SCP"), do: {:ok, {"127.0.0.1", unquote(dest_port)}}
        def resolve_ae(_), do: {:error, :unknown_ae}
      end,
      Macro.Env.location(__ENV__)
    )

    mod
  end

  defp move_error_handler(test_pid) do
    mod = :"Dimse.Test.MoveErrorHandler.#{System.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          ["1.2.840.10008.5.1.4.1.2.2.2"]
        end

        @impl true
        def handle_echo(_command, _state), do: {:ok, 0x0000}

        @impl true
        def handle_store(_command, _data, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_find(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_move(_command, _query, _state) do
          send(unquote(test_pid), :move_error_called)
          {:error, 0xA700, "out of resources"}
        end

        @impl true
        def handle_get(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        def resolve_ae(_), do: {:error, :unknown_ae}
      end,
      Macro.Env.location(__ENV__)
    )

    mod
  end

  defp move_unknown_dest_handler(test_pid, instances) do
    mod = :"Dimse.Test.MoveUnknownDestHandler.#{System.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          ["1.2.840.10008.5.1.4.1.2.2.2"]
        end

        @impl true
        def handle_echo(_command, _state), do: {:ok, 0x0000}

        @impl true
        def handle_store(_command, _data, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_find(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_move(_command, _query, _state) do
          send(unquote(test_pid), :move_called)
          {:ok, unquote(Macro.escape(instances))}
        end

        @impl true
        def handle_get(_command, _query, _state), do: {:error, 0xC000, "not supported"}

        def resolve_ae(_), do: {:error, :unknown_ae}
      end,
      Macro.Env.location(__ENV__)
    )

    mod
  end

  defp store_dest_handler(test_pid) do
    mod = :"Dimse.Test.StoreDestHandler.#{System.unique_integer([:positive])}"

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
          send(unquote(test_pid), {:dest_stored, data})
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

  defp find_slow_handler(test_pid) do
    mod = :"Dimse.Test.FindSlowHandler.#{System.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          ["1.2.840.10008.5.1.4.1.2.2.1"]
        end

        @impl true
        def handle_echo(_command, _state), do: {:ok, 0x0000}

        @impl true
        def handle_store(_command, _data, _state), do: {:error, 0xC000, "not supported"}

        @impl true
        def handle_find(command, _query, _state) do
          message_id = command[{0x0000, 0x0110}] || 0
          send(unquote(test_pid), {:find_started, message_id})

          # Generate many results slowly so cancel has time to arrive
          results =
            for i <- 1..100 do
              Process.sleep(10)
              :crypto.strong_rand_bytes(32)
            end

          {:ok, results}
        end

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
