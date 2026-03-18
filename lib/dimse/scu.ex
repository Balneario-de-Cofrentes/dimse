defmodule Dimse.Scu do
  @moduledoc """
  SCU (Service Class User) client API.

  Provides functions to establish outbound DICOM associations and execute
  DIMSE-C operations against remote SCPs. This is the client-side counterpart
  to the SCP behaviour defined in `Dimse.Handler`.

  ## Usage

      # Open an association
      {:ok, assoc} = Dimse.Scu.open("192.168.1.10", 11112,
        calling_ae: "MY_SCU",
        called_ae: "REMOTE_SCP",
        abstract_syntaxes: ["1.2.840.10008.1.1"]  # Verification
      )

      # Execute operations
      :ok = Dimse.Scu.Echo.verify(assoc)

      # Release the association
      :ok = Dimse.Scu.release(assoc)

  ## Association Management

  The SCU opens a TCP connection, sends an A-ASSOCIATE-RQ, waits for the
  A-ASSOCIATE-AC, and returns a `Dimse.Association` pid. All DIMSE operations
  are then sent as GenServer calls to this pid.

  ## Error Handling

  - Connection refused → `{:error, :econnrefused}`
  - Association rejected → `{:error, {:rejected, result, source, reason}}`
  - Association establishment timeout → `{:error, :timeout}`
  - Unexpected abort → `{:error, {:aborted, source, reason}}`
  """

  @verification_uid "1.2.840.10008.1.1"

  @doc """
  Opens a DICOM association to a remote AE.

  Returns `{:ok, association_pid}` or `{:error, reason}`.

  ## Options

    * `:calling_ae` — local AE title (default: `"DIMSE"`)
    * `:called_ae` — remote AE title (default: `"ANY-SCP"`)
    * `:abstract_syntaxes` — list of SOP Class UIDs (default: Verification)
    * `:transfer_syntaxes` — list of Transfer Syntax UIDs
    * `:max_pdu_length` — max PDU length (default: `16_384`)
    * `:timeout` — total association establishment timeout in ms (default: `30_000`)
    * `:tls` — TLS options (keyword list). When present, the SCU connects
      via TLS instead of plain TCP. Accepts standard `:ssl` options:
      - `:cacertfile` — path to CA certificate for server verification
      - `:verify` — `:verify_peer` to verify the server certificate
      - `:certfile` — client certificate for mutual TLS
      - `:keyfile` — client private key for mutual TLS
    * `:role_selections` — list of `Dimse.Pdu.RoleSelection` structs proposing
      SCU/SCP roles for specific SOP classes (PS3.7 Annex D.3.3.4)
    * `:user_identity` — `Dimse.Pdu.UserIdentity` struct for SCU authentication
      (PS3.7 Annex D.3.3.7). The SCP handler's `handle_authenticate/2` callback
      is called to accept or reject.
  """
  @spec open(String.t(), pos_integer(), keyword()) :: {:ok, pid()} | {:error, term()}
  def open(host, port, opts \\ []) do
    abstract_syntaxes = Keyword.get(opts, :abstract_syntaxes, [@verification_uid])
    timeout = Keyword.get(opts, :timeout, 30_000)
    started_at = System.monotonic_time(:millisecond)

    config = %Dimse.Association.Config{
      ae_title: Keyword.get(opts, :calling_ae, "DIMSE"),
      max_pdu_length: Keyword.get(opts, :max_pdu_length, 16_384),
      dimse_timeout: timeout
    }

    assoc_opts =
      [
        mode: :scu,
        host: host,
        port: port,
        calling_ae: Keyword.get(opts, :calling_ae, "DIMSE"),
        called_ae: Keyword.get(opts, :called_ae, "ANY-SCP"),
        abstract_syntaxes: abstract_syntaxes,
        config: config,
        timeout: timeout
      ]
      |> maybe_add(:transfer_syntaxes, Keyword.get(opts, :transfer_syntaxes))
      |> maybe_add(:tls, Keyword.get(opts, :tls))
      |> maybe_add(:role_selections, Keyword.get(opts, :role_selections))
      |> maybe_add(:user_identity, Keyword.get(opts, :user_identity))

    # Use start (not start_link) so connection failures don't crash the caller
    case Dimse.Association.start(assoc_opts) do
      {:ok, pid} ->
        case remaining_timeout(started_at, timeout) do
          remaining when remaining > 0 ->
            case await_established(pid, remaining) do
              :ok -> {:ok, pid}
              {:error, _} = err -> err
            end

          _ ->
            Dimse.Association.abort(pid)
            {:error, :timeout}
        end

      {:error, _} = err ->
        err
    end
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  @doc """
  Sends an A-RELEASE-RQ and waits for A-RELEASE-RP.
  """
  @spec release(pid(), timeout()) :: :ok | {:error, term()}
  def release(assoc, timeout \\ 30_000) do
    Dimse.Association.release(assoc, timeout)
  end

  @doc """
  Sends an A-ABORT to forcefully terminate the association.
  """
  @spec abort(pid()) :: :ok
  def abort(assoc) do
    Dimse.Association.abort(assoc)
  end

  @doc false
  @spec normalize_n_response(map(), binary() | nil) ::
          {:ok, integer(), binary() | nil} | {:error, {:status, integer(), binary() | nil}}
  def normalize_n_response(response, data) do
    status = Dimse.Command.status(response)

    case Dimse.Command.Status.category(status) do
      category when category in [:success, :warning] ->
        {:ok, status, data}

      _ ->
        {:error, {:status, status, data}}
    end
  end

  defp await_established(pid, timeout) do
    ref = Process.monitor(pid)
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_established(pid, ref, deadline)
  end

  defp remaining_timeout(started_at, timeout) do
    elapsed = System.monotonic_time(:millisecond) - started_at
    max(timeout - elapsed, 0)
  end

  defp do_await_established(pid, ref, deadline) do
    receive do
      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:error, normalize_connect_exit(reason)}
    after
      10 ->
        case Dimse.Association.negotiated_contexts(pid) do
          contexts when map_size(contexts) > 0 ->
            Process.demonitor(ref, [:flush])
            :ok

          _ ->
            if System.monotonic_time(:millisecond) >= deadline do
              Dimse.Association.abort(pid)
              Process.demonitor(ref, [:flush])
              {:error, :timeout}
            else
              do_await_established(pid, ref, deadline)
            end
        end
    end
  catch
    :exit, reason ->
      wait_for_down(pid, ref, normalize_connect_call_exit(reason))
  end

  defp wait_for_down(pid, ref, fallback) do
    receive do
      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:error, normalize_connect_exit(reason)}
    after
      0 ->
        {:error, fallback}
    end
  end

  defp normalize_connect_call_exit({:noproc, _}), do: :closed
  defp normalize_connect_call_exit({:normal, _}), do: :closed
  defp normalize_connect_call_exit({:shutdown, reason}), do: normalize_connect_exit(reason)
  defp normalize_connect_call_exit(reason), do: normalize_connect_exit(reason)

  defp normalize_connect_exit({:rejected, result, source, reason}),
    do: {:rejected, result, source, reason}

  defp normalize_connect_exit({:aborted, source, reason}),
    do: {:aborted, source, reason}

  defp normalize_connect_exit({:shutdown, reason}), do: normalize_connect_exit(reason)
  defp normalize_connect_exit(:normal), do: :closed
  defp normalize_connect_exit(reason), do: reason
end
