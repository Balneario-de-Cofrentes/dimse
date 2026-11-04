defmodule Dimse.TlsTest do
  use ExUnit.Case

  @moduletag :tls

  alias Dimse.Test.TlsHelpers

  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"
  @printer_sop_class "1.2.840.10008.5.1.1.17"

  setup do
    certs = TlsHelpers.generate_tls_certs()
    on_exit(fn -> File.rm_rf!(certs.dir) end)
    %{certs: certs}
  end

  defp wait_for_established(assoc, timeout \\ 2_000) do
    contexts = Dimse.Association.negotiated_contexts(assoc)

    assert map_size(contexts) > 0,
           "Association was not established immediately after connect/3 within #{timeout}ms"

    :ok
  end

  defp server_tls_opts(certs) do
    [
      certfile: certs.server_certfile,
      keyfile: certs.server_keyfile
    ]
  end

  defp client_tls_opts(certs) do
    [
      cacertfile: certs.cacertfile,
      verify: :verify_peer
    ]
  end

  defp mtls_server_opts(certs) do
    server_tls_opts(certs) ++
      [cacertfile: certs.cacertfile, verify: :verify_peer, fail_if_no_peer_cert: true]
  end

  defp mtls_client_opts(certs) do
    client_tls_opts(certs) ++ [certfile: certs.client_certfile, keyfile: certs.client_keyfile]
  end

  defp der(certfile) do
    [{:Certificate, der, :not_encrypted}] = :public_key.pem_decode(File.read!(certfile))
    der
  end

  defp start_probe_listener(opts) do
    {:ok, ref} = Dimse.start_listener([port: 0, handler: PeerCertProbeHandler] ++ opts)
    on_exit(fn -> Dimse.stop_listener(ref) end)
    :ranch.get_port(ref)
  end

  # Echoes over a fresh association and returns the SCU's own `peer_cert`.
  defp echo_and_release(port, connect_opts) do
    opts =
      Keyword.merge(
        [calling_ae: "PEER_SCU", called_ae: "PEER_SCP", abstract_syntaxes: ["1.2.840.10008.1.1"]],
        connect_opts
      )

    {:ok, assoc} = Dimse.connect("127.0.0.1", port, opts)
    assert :ok = Dimse.echo(assoc, timeout: 5_000)
    scu_peer_cert = :sys.get_state(assoc).peer_cert
    assert :ok = Dimse.release(assoc, 5_000)
    scu_peer_cert
  end

  describe "C-ECHO over TLS" do
    test "SCU can echo SCP over TLS", %{certs: certs} do
      {:ok, ref} =
        Dimse.start_listener(
          port: 0,
          handler: Dimse.Scp.Echo,
          tls: server_tls_opts(certs)
        )

      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TLS_SCU",
          called_ae: "TLS_SCP",
          abstract_syntaxes: ["1.2.840.10008.1.1"],
          tls: client_tls_opts(certs)
        )

      wait_for_established(assoc)

      assert :ok = Dimse.echo(assoc, timeout: 5_000)
      assert :ok = Dimse.release(assoc, 5_000)

      Dimse.stop_listener(ref)
    end
  end

  describe "C-STORE over TLS" do
    test "full data transfer over encrypted connection", %{certs: certs} do
      {:ok, ref} =
        Dimse.start_listener(
          port: 0,
          handler: TestStoreHandler,
          tls: server_tls_opts(certs)
        )

      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TLS_SCU",
          called_ae: "TLS_SCP",
          abstract_syntaxes: [@ct_image_storage],
          tls: client_tls_opts(certs)
        )

      wait_for_established(assoc)

      data = :crypto.strong_rand_bytes(4096)
      sop_instance = "1.2.3.4.5.6.7.8.9"
      assert :ok = Dimse.store(assoc, @ct_image_storage, sop_instance, data, timeout: 5_000)

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end
  end

  describe "mutual TLS" do
    test "SCP verifies client certificate", %{certs: certs} do
      {:ok, ref} =
        Dimse.start_listener(
          port: 0,
          handler: Dimse.Scp.Echo,
          tls: mtls_server_opts(certs)
        )

      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "MTLS_SCU",
          called_ae: "MTLS_SCP",
          abstract_syntaxes: ["1.2.840.10008.1.1"],
          tls: mtls_client_opts(certs)
        )

      wait_for_established(assoc)

      assert :ok = Dimse.echo(assoc, timeout: 5_000)
      assert :ok = Dimse.release(assoc, 5_000)

      Dimse.stop_listener(ref)
    end
  end

  describe "peer certificate in association state" do
    setup do
      Process.register(self(), PeerCertProbe)
      :ok
    end

    test "SCP handlers receive the client certificate on mutual TLS", %{certs: certs} do
      port = start_probe_listener(tls: mtls_server_opts(certs))
      echo_and_release(port, tls: mtls_client_opts(certs))

      client_der = der(certs.client_certfile)
      assert_receive {:validate_association, ^client_der}
      assert_receive {:handle_echo, ^client_der}
    end

    test "SCU state holds the server certificate", %{certs: certs} do
      port = start_probe_listener(tls: mtls_server_opts(certs))
      assert echo_and_release(port, tls: mtls_client_opts(certs)) == der(certs.server_certfile)
    end

    test "is nil on TLS when the client presents no certificate", %{certs: certs} do
      port = start_probe_listener(tls: server_tls_opts(certs))
      echo_and_release(port, tls: client_tls_opts(certs))

      assert_receive {:validate_association, nil}
      assert_receive {:handle_echo, nil}
    end

    test "is nil on plain TCP" do
      port = start_probe_listener([])
      assert echo_and_release(port, []) == nil

      assert_receive {:validate_association, nil}
      assert_receive {:handle_echo, nil}
    end
  end

  describe "DIMSE-N over TLS" do
    test "N-GET round trip over TLS", %{certs: certs} do
      {:ok, ref} =
        Dimse.start_listener(
          port: 0,
          handler: TestNGetHandler,
          tls: server_tls_opts(certs)
        )

      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TLS_SCU",
          called_ae: "TLS_SCP",
          abstract_syntaxes: [@printer_sop_class],
          tls: client_tls_opts(certs)
        )

      wait_for_established(assoc)

      assert {:ok, 0x0000, _data} =
               Dimse.n_get(assoc, @printer_sop_class, "1.2.3.4.5", timeout: 5_000)

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end
  end

  describe "mixed TCP and TLS listeners" do
    test "TCP listener and TLS listener both operational", %{certs: certs} do
      # Start a plain TCP listener
      {:ok, tcp_ref} =
        Dimse.start_listener(
          port: 0,
          handler: Dimse.Scp.Echo
        )

      tcp_port = :ranch.get_port(tcp_ref)

      # Start a TLS listener
      {:ok, tls_ref} =
        Dimse.start_listener(
          port: 0,
          handler: Dimse.Scp.Echo,
          tls: server_tls_opts(certs)
        )

      tls_port = :ranch.get_port(tls_ref)

      # Connect via TCP
      {:ok, tcp_assoc} =
        Dimse.connect("127.0.0.1", tcp_port,
          calling_ae: "TCP_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1"]
        )

      wait_for_established(tcp_assoc)
      assert :ok = Dimse.echo(tcp_assoc, timeout: 5_000)

      # Connect via TLS
      {:ok, tls_assoc} =
        Dimse.connect("127.0.0.1", tls_port,
          calling_ae: "TLS_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1"],
          tls: client_tls_opts(certs)
        )

      wait_for_established(tls_assoc)
      assert :ok = Dimse.echo(tls_assoc, timeout: 5_000)

      # Clean up
      :ok = Dimse.release(tcp_assoc, 5_000)
      :ok = Dimse.release(tls_assoc, 5_000)
      Dimse.stop_listener(tcp_ref)
      Dimse.stop_listener(tls_ref)
    end
  end

  describe "TLS hostname verification" do
    test "SCU with server_name_indication validates hostname", %{certs: certs} do
      {:ok, ref} =
        Dimse.start_listener(
          port: 0,
          handler: Dimse.Scp.Echo,
          tls: server_tls_opts(certs)
        )

      port = :ranch.get_port(ref)

      # Connect with explicit SNI that matches the SAN in the cert (127.0.0.1)
      client_tls =
        client_tls_opts(certs) ++
          [
            server_name_indication: ~c"localhost",
            customize_hostname_check: [
              match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
            ]
          ]

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "SNI_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1"],
          tls: client_tls
        )

      wait_for_established(assoc)
      assert :ok = Dimse.echo(assoc, timeout: 5_000)
      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
    end
  end

  describe "TLS handshake timeout" do
    test "SCU times out when SCP does not complete TLS handshake" do
      # Start a raw TCP listener that accepts but never does TLS handshake
      {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_sock)

      # Accept in background but don't do anything with it
      spawn(fn ->
        {:ok, _sock} = :gen_tcp.accept(listen_sock, 5_000)
        # Intentionally don't do TLS handshake — just hold the socket
        Process.sleep(10_000)
      end)

      # SCU should timeout trying to establish TLS
      result =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TIMEOUT_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1"],
          timeout: 2_000,
          tls: [verify: :verify_none]
        )

      assert {:error, _reason} = result
      :gen_tcp.close(listen_sock)
    end
  end

  describe "TLS error surfacing" do
    test "handshake failure returns descriptive error", %{certs: certs} do
      server_tls =
        server_tls_opts(certs) ++
          [
            cacertfile: certs.cacertfile,
            verify: :verify_peer,
            fail_if_no_peer_cert: true
          ]

      {:ok, ref} =
        Dimse.start_listener(
          port: 0,
          handler: Dimse.Scp.Echo,
          tls: server_tls
        )

      port = :ranch.get_port(ref)

      # Connect without client cert — should get a TLS error, not a generic timeout
      result =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "NO_CERT",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1"],
          tls: client_tls_opts(certs),
          timeout: 5_000
        )

      assert {:error, reason} = result
      # The error should be TLS-related, not a generic timeout
      assert reason != :timeout
      Dimse.stop_listener(ref)
    end

    test "wrong protocol version detected as TLS error" do
      # Start a TLS listener but try connecting with plain TCP
      certs = Dimse.Test.TlsHelpers.generate_tls_certs()
      on_exit(fn -> File.rm_rf!(certs.dir) end)

      {:ok, ref} =
        Dimse.start_listener(
          port: 0,
          handler: Dimse.Scp.Echo,
          tls: server_tls_opts(certs)
        )

      port = :ranch.get_port(ref)

      # Plain TCP to a TLS listener — should fail
      result =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "PLAIN_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1"],
          timeout: 5_000
        )

      # Should get an error (TCP closed or timeout because TLS handshake never happens)
      assert {:error, _} = result
      Dimse.stop_listener(ref)
    end
  end

  describe "TLS security" do
    test "SCU rejects SCP with unknown CA", %{certs: certs} do
      # Start SCP with server cert
      {:ok, ref} =
        Dimse.start_listener(
          port: 0,
          handler: Dimse.Scp.Echo,
          tls: server_tls_opts(certs)
        )

      port = :ranch.get_port(ref)

      # Generate a separate CA that the client will trust (not the one that signed the server cert)
      other_certs = TlsHelpers.generate_tls_certs()
      on_exit(fn -> File.rm_rf!(other_certs.dir) end)

      # SCU connects trusting the wrong CA — should fail
      result =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "BAD_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1"],
          tls: [cacertfile: other_certs.cacertfile, verify: :verify_peer]
        )

      assert {:error, _reason} = result

      Dimse.stop_listener(ref)
    end

    test "SCP rejects client without required cert", %{certs: certs} do
      {:ok, ref} =
        Dimse.start_listener(
          port: 0,
          handler: Dimse.Scp.Echo,
          tls: mtls_server_opts(certs)
        )

      port = :ranch.get_port(ref)

      # SCU connects without a client certificate
      result =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "NO_CERT_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: ["1.2.840.10008.1.1"],
          tls: client_tls_opts(certs)
        )

      assert {:error, _reason} = result

      Dimse.stop_listener(ref)
    end
  end
end

# --- Test handler modules ---

defmodule TestStoreHandler do
  @behaviour Dimse.Handler

  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"

  @impl true
  def supported_abstract_syntaxes, do: [@ct_image_storage]

  @impl true
  def handle_echo(_command, _state), do: {:ok, 0x0000}

  @impl true
  def handle_store(_command, _data, _state), do: {:ok, 0x0000}

  @impl true
  def handle_find(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_move(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_get(_command, _query, _state), do: {:ok, []}
end

defmodule TestNGetHandler do
  @behaviour Dimse.Handler

  @printer_sop_class "1.2.840.10008.5.1.1.17"

  @impl true
  def supported_abstract_syntaxes, do: [@printer_sop_class]

  @impl true
  def handle_echo(_command, _state), do: {:ok, 0x0000}

  @impl true
  def handle_store(_command, _data, _state), do: {:ok, 0x0000}

  @impl true
  def handle_find(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_move(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_get(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_n_get(_command, _state), do: {:ok, 0x0000, <<0x00, 0x01, 0x02>>}
end

# Reports `state.peer_cert` to the test process registered as `PeerCertProbe`.
defmodule PeerCertProbeHandler do
  @behaviour Dimse.Handler

  @impl true
  def validate_association(_request, state) do
    send(PeerCertProbe, {:validate_association, state.peer_cert})
    {:ok, nil}
  end

  @impl true
  def handle_echo(_command, state) do
    send(PeerCertProbe, {:handle_echo, state.peer_cert})
    {:ok, 0x0000}
  end

  @impl true
  def handle_store(_command, _data, _state), do: {:ok, 0x0000}

  @impl true
  def handle_find(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_move(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_get(_command, _query, _state), do: {:ok, []}
end
