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
  - Timeout → `{:error, :timeout}`
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
    * `:timeout` — connection timeout in ms (default: `30_000`)
  """
  @spec open(String.t(), pos_integer(), keyword()) :: {:ok, pid()} | {:error, term()}
  def open(host, port, opts \\ []) do
    abstract_syntaxes = Keyword.get(opts, :abstract_syntaxes, [@verification_uid])

    config = %Dimse.Association.Config{
      ae_title: Keyword.get(opts, :calling_ae, "DIMSE"),
      max_pdu_length: Keyword.get(opts, :max_pdu_length, 16_384),
      dimse_timeout: Keyword.get(opts, :timeout, 30_000)
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
        timeout: Keyword.get(opts, :timeout, 30_000)
      ]
      |> maybe_add(:transfer_syntaxes, Keyword.get(opts, :transfer_syntaxes))

    # Use start (not start_link) so connection failures don't crash the caller
    Dimse.Association.start(assoc_opts)
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
end
