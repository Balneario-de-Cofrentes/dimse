defmodule Dimse.Listener do
  @moduledoc """
  Ranch listener lifecycle management.

  Wraps `:ranch.child_spec/5` to start a TCP listener that accepts DICOM
  associations. Each accepted connection is handed off to
  `Dimse.ConnectionHandler`, which spawns a `Dimse.Association` GenServer.

  ## Usage

  Add to your supervision tree:

      children = [
        {Dimse.Listener, port: 11112, handler: MyApp.DicomHandler}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  Or start dynamically:

      {:ok, ref} = Dimse.start_listener(port: 11112, handler: MyApp.DicomHandler)

  ## Options

  See `Dimse.start_listener/1` for available options.
  """

  alias Dimse.Association.Config

  @doc """
  Returns a child spec for the Ranch listener.

  Used when adding the listener to a supervision tree.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    ref = listener_ref(opts)
    {transport_mod, transport_opts, protocol_opts} = build_opts(opts)

    :ranch.child_spec(
      ref,
      transport_mod,
      transport_opts,
      Dimse.ConnectionHandler,
      protocol_opts
    )
  end

  @doc """
  Starts a DIMSE listener.

  Returns `{:ok, listener_ref}` on success.

  ## Options

    * `:port` — TCP port (default: `11112`)
    * `:handler` — module implementing `Dimse.Handler` (required)
    * `:ae_title` — local AE title (default: `"DIMSE"`)
    * `:max_associations` — max concurrent associations (default: `200`)
    * `:num_acceptors` — Ranch acceptor pool size (default: `10`)
    * `:max_pdu_length` — max PDU length in bytes (default: `16_384`)
    * `:ref` — custom listener reference (default: auto-generated)
    * `:tls` — TLS options (keyword list). When present, the listener uses
      TLS (`ranch_ssl`) instead of plain TCP. Accepts standard `:ssl` options:
      - `:certfile` — path to the server certificate PEM file (required)
      - `:keyfile` — path to the server private key PEM file (required)
      - `:cacertfile` — path to CA certificate for client verification
      - `:verify` — `:verify_peer` to require client certificates
      - `:fail_if_no_peer_cert` — `true` to reject clients without certs
      PS3.15 Annex B recommends port 2762 for DICOM-TLS.
  """
  @spec start(keyword()) :: {:ok, term()} | {:error, term()}
  def start(opts) do
    ref = listener_ref(opts)
    {transport_mod, transport_opts, protocol_opts} = build_opts(opts)

    :ranch.start_listener(
      ref,
      transport_mod,
      transport_opts,
      Dimse.ConnectionHandler,
      protocol_opts
    )
    |> case do
      {:ok, _pid} -> {:ok, ref}
      {:error, _} = err -> err
    end
  end

  @doc """
  Stops a running listener.
  """
  @spec stop(term()) :: :ok
  def stop(ref) do
    :ranch.stop_listener(ref)
  end

  defp build_opts(opts) do
    port = Keyword.get(opts, :port, 11112)
    num_acceptors = Keyword.get(opts, :num_acceptors, 10)
    max_associations = Keyword.get(opts, :max_associations, 200)
    tls_opts = Keyword.get(opts, :tls)

    config = %Config{
      ae_title: Keyword.get(opts, :ae_title, "DIMSE"),
      max_pdu_length: Keyword.get(opts, :max_pdu_length, 16_384),
      max_associations: max_associations,
      num_acceptors: num_acceptors
    }

    base_socket_opts = [port: port]

    {transport_mod, socket_opts} =
      case tls_opts do
        nil ->
          {:ranch_tcp, base_socket_opts}

        tls when is_list(tls) ->
          # Convert string paths to charlists for :ssl
          ssl_opts = Enum.map(tls, &normalize_tls_opt/1)
          {:ranch_ssl, base_socket_opts ++ ssl_opts}
      end

    transport_opts = %{
      socket_opts: socket_opts,
      num_acceptors: num_acceptors,
      max_connections: max_associations
    }

    protocol_opts = [
      handler: Keyword.fetch!(opts, :handler),
      config: config
    ]

    {transport_mod, transport_opts, protocol_opts}
  end

  # :ssl expects file paths as charlists
  defp normalize_tls_opt({key, value})
       when key in [:certfile, :keyfile, :cacertfile] and is_binary(value) do
    {key, to_charlist(value)}
  end

  defp normalize_tls_opt(opt), do: opt

  defp listener_ref(opts) do
    Keyword.get(opts, :ref, {__MODULE__, make_ref()})
  end
end
