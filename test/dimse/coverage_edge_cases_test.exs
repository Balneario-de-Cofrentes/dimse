defmodule Dimse.CoverageEdgeCasesTest do
  @moduledoc """
  Tests targeting specific uncovered code paths to maintain coverage.
  Exercises handler error returns, ARTIM timeout, and protocol edge cases.
  """
  use ExUnit.Case

  alias Dimse.Association

  @verification_uid "1.2.840.10008.1.1"
  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"

  @study_root_find "1.2.840.10008.5.1.4.1.2.2.1"

  # Handler that returns {:error, status, msg} from callbacks
  defmodule ErrorReturningHandler do
    @behaviour Dimse.Handler

    @impl true
    def supported_abstract_syntaxes,
      do: [
        "1.2.840.10008.1.1",
        "1.2.840.10008.5.1.4.1.1.2",
        "1.2.840.10008.5.1.4.1.2.2.1"
      ]

    @impl true
    def handle_echo(_command, _state), do: {:error, 0xC000, "echo failed"}

    @impl true
    def handle_store(_command, _data, _state), do: {:error, 0xC000, "store failed"}

    @impl true
    def handle_find(_command, _query, _state), do: {:error, 0xA700, "find failed"}

    @impl true
    def handle_move(_command, _query, _state), do: {:error, 0xA801, "move failed"}

    @impl true
    def handle_get(_command, _query, _state), do: {:error, 0xA702, "get failed"}
  end

  # Handler that throws instead of raising — exercises catch clause in invoke_handler
  defmodule ThrowingHandler do
    @behaviour Dimse.Handler

    @impl true
    def supported_abstract_syntaxes, do: ["1.2.840.10008.1.1"]

    @impl true
    def handle_echo(_command, _state), do: throw(:handler_threw)

    @impl true
    def handle_store(_cmd, _data, _state), do: {:ok, 0x0000}

    @impl true
    def handle_find(_cmd, _query, _state), do: {:ok, []}

    @impl true
    def handle_move(_cmd, _query, _state), do: {:ok, []}

    @impl true
    def handle_get(_cmd, _query, _state), do: {:ok, []}
  end

  describe "handler error return paths" do
    test "C-ECHO handler returning {:error, status, msg} produces failure status" do
      {:ok, ref} = Dimse.start_listener(port: 0, handler: ErrorReturningHandler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TEST_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@verification_uid]
        )

      assert {:error, {:status, 0xC000}} = Dimse.echo(assoc, timeout: 5_000)
      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "C-STORE handler returning {:error, status, msg} produces failure status" do
      {:ok, ref} = Dimse.start_listener(port: 0, handler: ErrorReturningHandler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TEST_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@ct_image_storage]
        )

      data = :crypto.strong_rand_bytes(64)

      assert {:error, {:status, 0xC000}} =
               Dimse.store(assoc, @ct_image_storage, "1.2.3.4", data, timeout: 5_000)

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end

    test "C-FIND handler returning {:error, status, msg} produces failure status" do
      {:ok, ref} = Dimse.start_listener(port: 0, handler: ErrorReturningHandler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TEST_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_find]
        )

      assert {:error, {:status, 0xA700}} =
               Dimse.find(assoc, @study_root_find, <<>>, timeout: 5_000)

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end
  end

  describe "handler exception paths" do
    test "handler that throws causes association to crash with error" do
      {:ok, ref} = Dimse.start_listener(port: 0, handler: ThrowingHandler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TEST_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@verification_uid]
        )

      # The throw in handle_echo will crash the SCP-side association process,
      # which closes the socket, causing the SCU to get an error
      assert {:error, _reason} = Dimse.echo(assoc, timeout: 5_000)
      Dimse.stop_listener(ref)
    end
  end

  describe "ARTIM timeout" do
    test "SCP aborts when SCU connects but never sends A-ASSOCIATE-RQ" do
      {:ok, ref} =
        Dimse.start_listener(
          port: 0,
          handler: Dimse.Scp.Echo,
          artim_timeout: 200
        )

      port = :ranch.get_port(ref)

      # Connect via raw TCP but never send A-ASSOCIATE-RQ
      {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
      # Wait for ARTIM to fire — SCP sends A-ABORT then closes
      case :gen_tcp.recv(sock, 0, 2_000) do
        {:ok, <<0x07, 0x00, _::binary>>} ->
          # Got A-ABORT PDU as expected, connection will close next
          assert {:error, :closed} = :gen_tcp.recv(sock, 0, 1_000)

        {:error, :closed} ->
          # Connection closed directly — also acceptable
          :ok
      end

      :gen_tcp.close(sock)
      Dimse.stop_listener(ref)
    end
  end

  describe "abort during pending release" do
    test "abort received while release is pending replies error to release caller" do
      {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_sock)

      test_pid = self()

      # A server that accepts, sends AC, then aborts when it sees A-RELEASE-RQ
      Task.start(fn ->
        {:ok, conn} = :gen_tcp.accept(listen_sock, 5_000)
        {:ok, _rq_data} = :gen_tcp.recv(conn, 0, 1_000)
        ac_pdu = build_associate_ac()
        :gen_tcp.send(conn, ac_pdu)
        {:ok, _release_rq} = :gen_tcp.recv(conn, 0, 5_000)
        send(test_pid, :release_rq_received)
        # Send A-ABORT instead of A-RELEASE-RP
        a_abort_pdu = <<0x07, 0x00, 0, 0, 0, 4, 0, 0, 2, 0>>
        :gen_tcp.send(conn, a_abort_pdu)
        :timer.sleep(200)
        :gen_tcp.close(conn)
      end)

      {:ok, assoc} =
        Dimse.Scu.open("127.0.0.1", port,
          timeout: 5_000,
          abstract_syntaxes: [@verification_uid]
        )

      task = Task.async(fn -> Association.release(assoc, 10_000) end)
      assert_receive :release_rq_received, 3_000
      assert {:error, _reason} = Task.await(task, 3_000)
      :gen_tcp.close(listen_sock)
    end
  end

  describe "SCU connect error normalization" do
    test "returns {:error, :econnrefused} for refused connection" do
      assert {:error, :econnrefused} =
               Dimse.Scu.open("127.0.0.1", 59998,
                 timeout: 1_000,
                 abstract_syntaxes: [@verification_uid]
               )
    end

    test "returns {:error, :closed} when SCP closes immediately after TCP connect" do
      {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_sock)

      Task.start(fn ->
        {:ok, conn} = :gen_tcp.accept(listen_sock, 5_000)
        :gen_tcp.close(conn)
      end)

      result =
        Dimse.Scu.open("127.0.0.1", port,
          timeout: 2_000,
          abstract_syntaxes: [@verification_uid]
        )

      assert {:error, reason} = result
      assert reason in [:closed, :tcp_closed]
      :gen_tcp.close(listen_sock)
    end
  end

  describe "close_socket with nil socket" do
    test "association process terminates cleanly when socket is already nil" do
      # Start an association in idle state (no socket), then abort
      {:ok, pid} = Association.start([])
      ref = Process.monitor(pid)
      Association.abort(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
    end
  end

  # Builds a minimal valid A-ASSOCIATE-AC PDU
  defp build_associate_ac do
    transfer_syntax = "1.2.840.10008.1.2"
    impl_uid = "1.2.826.0.1.3680043.8.498.1"
    app_context_name = "1.2.840.10008.3.1.1.1"

    app_ctx = encode_sub_item(0x10, app_context_name)
    ts_item = encode_sub_item(0x40, transfer_syntax)
    pc_item = encode_sub_item(0x21, <<1, 0, 0, 0>> <> ts_item)
    max_len_item = <<0x51, 0x00, 0, 4, 0, 0, 0x40, 0x00>>
    impl_uid_item = encode_sub_item(0x52, impl_uid)
    user_info = encode_sub_item(0x50, max_len_item <> impl_uid_item)

    called = String.pad_trailing("DIMSE", 16)
    calling = String.pad_trailing("DIMSE", 16)
    reserved32 = :binary.copy(<<0>>, 32)

    payload =
      <<0x00, 0x01, 0x00, 0x00>> <>
        called <>
        calling <>
        reserved32 <>
        app_ctx <>
        pc_item <>
        user_info

    <<0x02, 0x00, byte_size(payload)::32>> <> payload
  end

  defp encode_sub_item(type, data) when is_binary(data) do
    <<type, 0x00, byte_size(data)::16>> <> data
  end
end
