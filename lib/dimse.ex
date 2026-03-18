defmodule Dimse do
  @moduledoc """
  Pure Elixir DICOM DIMSE networking library.

  Provides the DICOM Upper Layer Protocol (PS3.8), DIMSE-C message services
  (PS3.7 Chapter 9) and DIMSE-N notification/management services (PS3.7 Chapter 10)
  for building DICOM SCP (server) and SCU (client) applications on the BEAM.

  ## Public API

  ### Listener (SCP)

      Dimse.start_listener(port: 11112, handler: MyApp.DicomHandler)
      Dimse.stop_listener(ref)

  ### Client (SCU) — DIMSE-C

      {:ok, assoc} = Dimse.connect("192.168.1.10", 11112, calling_ae: "MY_SCU", called_ae: "REMOTE_SCP")
      :ok = Dimse.echo(assoc)
      :ok = Dimse.store(assoc, sop_class_uid, sop_instance_uid, data_set)
      {:ok, results} = Dimse.find(assoc, :study, query_data, timeout: 30_000)
      :ok = Dimse.cancel(assoc, message_id)
      {:ok, result} = Dimse.move(assoc, :study, query, dest_ae: "DEST_AE")
      {:ok, data_sets} = Dimse.get(assoc, :study, query)

  ### Client (SCU) — DIMSE-N

      {:ok, status, data} = Dimse.n_get(assoc, sop_class_uid, sop_instance_uid)
      {:ok, status, data} = Dimse.n_set(assoc, sop_class_uid, sop_instance_uid, modifications)
      {:ok, status, data} = Dimse.n_action(assoc, sop_class_uid, sop_instance_uid, action_type_id, action_info)
      {:ok, status, data} = Dimse.n_create(assoc, sop_class_uid, attributes)
      {:ok, status, nil}  = Dimse.n_delete(assoc, sop_class_uid, sop_instance_uid)
      {:ok, status, data} = Dimse.n_event_report(assoc, sop_class_uid, sop_instance_uid, event_type_id, event_info)

  ### Connection management

      :ok = Dimse.release(assoc)
      :ok = Dimse.abort(assoc)

  ## Architecture

  Each DICOM association is a dedicated GenServer process (`Dimse.Association`)
  supervised under a DynamicSupervisor. Ranch handles TCP acceptance. This gives
  fault isolation per-association and natural backpressure via `max_children`.

  ## Dependencies

  - `dicom` — command set encoding (Implicit VR Little Endian), UID generation,
    transfer syntax registry, SOP class lookup
  - `ranch` — TCP acceptor pool
  - `telemetry` — observability events
  """

  @doc """
  Starts a DIMSE listener on the given port.

  ## Options

    * `:port` — TCP port to listen on (default: `11112`)
    * `:handler` — module implementing `Dimse.Handler` behaviour (required)
    * `:ae_title` — local AE title (default: `"DIMSE"`)
    * `:max_associations` — max concurrent associations (default: `200`)
    * `:num_acceptors` — Ranch acceptor pool size (default: `10`)
    * `:max_pdu_length` — max PDU length in bytes (default: `16_384`)

  Returns `{:ok, listener_ref}` or `{:error, reason}`.
  """
  @spec start_listener(keyword()) :: {:ok, term()} | {:error, term()}
  def start_listener(opts \\ []) do
    Dimse.Listener.start(opts)
  end

  @doc """
  Stops a running DIMSE listener.
  """
  @spec stop_listener(term()) :: :ok | {:error, term()}
  def stop_listener(ref) do
    Dimse.Listener.stop(ref)
  end

  @doc """
  Opens an association to a remote DICOM AE (SCU client).

  ## Options

    * `:calling_ae` — local AE title (default: `"DIMSE"`)
    * `:called_ae` — remote AE title (default: `"ANY-SCP"`)
    * `:abstract_syntaxes` — list of SOP Class UIDs to propose
    * `:transfer_syntaxes` — list of Transfer Syntax UIDs to propose
    * `:max_pdu_length` — max PDU length (default: `16_384`)
    * `:timeout` — connection timeout in ms (default: `30_000`)

  Returns `{:ok, association_pid}` or `{:error, reason}`.
  """
  @spec connect(String.t(), pos_integer(), keyword()) :: {:ok, pid()} | {:error, term()}
  def connect(host, port, opts \\ []) do
    Dimse.Scu.open(host, port, opts)
  end

  @doc "Sends a C-ECHO request on an established association."
  @spec echo(pid(), keyword()) :: :ok | {:error, term()}
  def echo(assoc, opts \\ []), do: Dimse.Scu.Echo.verify(assoc, opts)

  @doc """
  Sends a C-STORE request with the given data set.

  ## Parameters

    * `assoc` — association pid from `Dimse.connect/3`
    * `sop_class_uid` — SOP Class UID of the instance
    * `sop_instance_uid` — SOP Instance UID of the instance
    * `data` — encoded data set binary

  ## Options

    * `:priority` — request priority (default: `0x0000` medium)
    * `:move_originator_ae` — AE title of the C-MOVE originator
    * `:move_originator_message_id` — message ID from the C-MOVE request
    * `:timeout` — response timeout in ms (default: `30_000`)
  """
  @spec store(pid(), String.t(), String.t(), binary(), keyword()) :: :ok | {:error, term()}
  def store(assoc, sop_class_uid, sop_instance_uid, data, opts \\ []) do
    Dimse.Scu.Store.send(assoc, sop_class_uid, sop_instance_uid, data, opts)
  end

  @doc """
  Sends a C-FIND request and returns matching data sets.

  ## Parameters

    * `assoc` — association pid from `Dimse.connect/3`
    * `sop_class_or_level` — SOP Class UID string, or query level atom
      (`:patient`, `:study`, `:worklist`)
    * `query_data` — encoded query identifier data set

  ## Options

    * `:priority` — request priority (default: `0x0000` medium)
    * `:timeout` — response timeout in ms (default: `30_000`)
  """
  @spec find(pid(), String.t() | atom(), binary(), keyword()) ::
          {:ok, [binary()]} | {:error, {:cancelled, [binary()]} | term()}
  def find(assoc, sop_class_or_level, query_data, opts \\ []) do
    sop_class_uid = resolve_find_sop_class(sop_class_or_level)

    if sop_class_uid do
      Dimse.Scu.Find.query(assoc, sop_class_uid, query_data, opts)
    else
      {:error, {:unknown_query_level, sop_class_or_level}}
    end
  end

  @doc """
  Sends a C-CANCEL-RQ to cancel a pending C-FIND operation.

  The `message_id` should be the MessageID of the original C-FIND-RQ.
  """
  @spec cancel(pid(), integer()) :: :ok
  def cancel(assoc, message_id) do
    Dimse.Association.cancel(assoc, message_id)
  end

  @doc """
  Sends a C-MOVE request to retrieve instances to a destination AE.

  The SCP pushes matching instances to the destination AE via C-STORE
  sub-operations and reports sub-operation counts in the response.

  ## Parameters

    * `assoc` — association pid from `Dimse.connect/3`
    * `sop_class_or_level` — SOP Class UID string, or query level atom
      (`:patient`, `:study`)
    * `query_data` — encoded query identifier data set

  ## Options

    * `:dest_ae` — destination AE title (required)
    * `:priority` — request priority (default: `0x0000` medium)
    * `:timeout` — response timeout in ms (default: `30_000`)

  Returns `{:ok, %{completed: n, failed: n, warning: n}}` on success.
  """
  @spec move(pid(), String.t() | atom(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def move(assoc, sop_class_or_level, query_data, opts \\ []) do
    sop_class_uid = resolve_move_sop_class(sop_class_or_level)
    dest_ae = Keyword.fetch!(opts, :dest_ae)

    if sop_class_uid do
      Dimse.Scu.Move.retrieve(assoc, sop_class_uid, query_data, dest_ae, opts)
    else
      {:error, {:unknown_query_level, sop_class_or_level}}
    end
  end

  @doc """
  Sends a C-GET request to retrieve instances on the same association.

  The SCP sends matching instances back as C-STORE sub-operations on the
  same association. The SCU auto-accepts and returns the data sets.

  ## Parameters

    * `assoc` — association pid from `Dimse.connect/3`
    * `sop_class_or_level` — SOP Class UID string, or query level atom
      (`:patient`, `:study`)
    * `query_data` — encoded query identifier data set

  ## Options

    * `:priority` — request priority (default: `0x0000` medium)
    * `:timeout` — response timeout in ms (default: `30_000`)

  Returns `{:ok, [binary()]}` with the received data sets.
  """
  @spec get(pid(), String.t() | atom(), binary(), keyword()) ::
          {:ok, [binary()]} | {:error, term()}
  def get(assoc, sop_class_or_level, query_data, opts \\ []) do
    sop_class_uid = resolve_get_sop_class(sop_class_or_level)

    if sop_class_uid do
      Dimse.Scu.Get.retrieve(assoc, sop_class_uid, query_data, opts)
    else
      {:error, {:unknown_query_level, sop_class_or_level}}
    end
  end

  defp resolve_find_sop_class(level) when is_atom(level),
    do: Dimse.Scu.Find.sop_class_uid(level)

  defp resolve_find_sop_class(uid) when is_binary(uid), do: uid

  defp resolve_move_sop_class(level) when is_atom(level),
    do: Dimse.Scu.Move.sop_class_uid(level)

  defp resolve_move_sop_class(uid) when is_binary(uid), do: uid

  defp resolve_get_sop_class(level) when is_atom(level),
    do: Dimse.Scu.Get.sop_class_uid(level)

  defp resolve_get_sop_class(uid) when is_binary(uid), do: uid

  # --- DIMSE-N Services ---

  @doc """
  Sends an N-GET-RQ to retrieve attributes from a managed SOP Instance.

  ## Options

    * `:attribute_identifier_list` — list of `{group, element}` tags to retrieve
    * `:timeout` — response timeout in ms (default: `30_000`)

  Returns `{:ok, status, data}` or `{:error, reason}`.
  """
  @spec n_get(pid(), String.t(), String.t(), keyword()) ::
          {:ok, integer(), binary() | nil} | {:error, term()}
  def n_get(assoc, sop_class_uid, sop_instance_uid, opts \\ []) do
    Dimse.Scu.NGet.query(assoc, sop_class_uid, sop_instance_uid, opts)
  end

  @doc """
  Sends an N-SET-RQ to modify attributes on a managed SOP Instance.

  Returns `{:ok, status, data}` or `{:error, reason}`.
  """
  @spec n_set(pid(), String.t(), String.t(), binary(), keyword()) ::
          {:ok, integer(), binary() | nil} | {:error, term()}
  def n_set(assoc, sop_class_uid, sop_instance_uid, data, opts \\ []) do
    Dimse.Scu.NSet.send(assoc, sop_class_uid, sop_instance_uid, data, opts)
  end

  @doc """
  Sends an N-ACTION-RQ to request an action on a managed SOP Instance.

  Returns `{:ok, status, data}` or `{:error, reason}`.
  """
  @spec n_action(pid(), String.t(), String.t(), integer(), binary() | nil, keyword()) ::
          {:ok, integer(), binary() | nil} | {:error, term()}
  def n_action(assoc, sop_class_uid, sop_instance_uid, action_type_id, data, opts \\ []) do
    Dimse.Scu.NAction.send(assoc, sop_class_uid, sop_instance_uid, action_type_id, data, opts)
  end

  @doc """
  Sends an N-CREATE-RQ to create a new managed SOP Instance.

  ## Options

    * `:sop_instance_uid` — optional proposed SOP Instance UID
    * `:timeout` — response timeout in ms (default: `30_000`)

  Returns `{:ok, status, data}` or `{:error, reason}`.
  """
  @spec n_create(pid(), String.t(), binary() | nil, keyword()) ::
          {:ok, integer(), binary() | nil} | {:error, term()}
  def n_create(assoc, sop_class_uid, data, opts \\ []) do
    Dimse.Scu.NCreate.send(assoc, sop_class_uid, data, opts)
  end

  @doc """
  Sends an N-DELETE-RQ to delete a managed SOP Instance.

  Returns `{:ok, status, nil}` or `{:error, reason}`.
  """
  @spec n_delete(pid(), String.t(), String.t(), keyword()) ::
          {:ok, integer(), nil} | {:error, term()}
  def n_delete(assoc, sop_class_uid, sop_instance_uid, opts \\ []) do
    Dimse.Scu.NDelete.send(assoc, sop_class_uid, sop_instance_uid, opts)
  end

  @doc """
  Sends an N-EVENT-REPORT-RQ to notify the SCP of an event.

  Returns `{:ok, status, data}` or `{:error, reason}`.
  """
  @spec n_event_report(pid(), String.t(), String.t(), integer(), binary() | nil, keyword()) ::
          {:ok, integer(), binary() | nil} | {:error, term()}
  def n_event_report(assoc, sop_class_uid, sop_instance_uid, event_type_id, data, opts \\ []) do
    Dimse.Scu.NEventReport.send(
      assoc,
      sop_class_uid,
      sop_instance_uid,
      event_type_id,
      data,
      opts
    )
  end

  @doc "Sends an A-RELEASE-RQ to gracefully close the association."
  @spec release(pid(), timeout()) :: :ok | {:error, term()}
  def release(assoc, timeout \\ 30_000), do: Dimse.Scu.release(assoc, timeout)

  @doc "Sends an A-ABORT to forcefully terminate the association."
  @spec abort(pid()) :: :ok
  def abort(assoc), do: Dimse.Scu.abort(assoc)
end
