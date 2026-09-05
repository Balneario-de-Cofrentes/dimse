defmodule Dimse.Handler do
  @moduledoc """
  Behaviour for DIMSE SCP service class handlers.

  Implement this behaviour to handle incoming DIMSE requests on your SCP.
  Each callback receives the decoded command set, optional data set, and
  the current association state.

  ## Example

      defmodule MyApp.DicomHandler do
        @behaviour Dimse.Handler

        @impl true
        def supported_abstract_syntaxes do
          [
            "1.2.840.10008.1.1",
            "1.2.840.10008.5.1.4.1.1.2",
            "1.2.840.10008.5.1.4.1.2.2.1",
            "1.2.840.10008.5.1.4.1.2.2.2",
            "1.2.840.10008.5.1.4.1.2.2.3"
          ]
        end

        @impl true
        def handle_echo(_command, _state) do
          {:ok, 0x0000}
        end

        @impl true
        def handle_store(command, data_set, state) do
          sop_instance_uid = command[{0x0000, 0x1000}]
          # ... persist the instance ...
          {:ok, 0x0000}
        end

        @impl true
        def handle_find(_command, _query, _state) do
          # Return a list of matching data sets
          {:ok, []}
        end

        @impl true
        def handle_move(_command, _query, _state) do
          # One element per C-STORE sub-operation. The third element is the
          # encoded data set, or a zero-arity function that loads it on demand
          # right before that sub-operation is sent.
          {:ok,
           [
             {"1.2.840.10008.5.1.4.1.1.2", "1.2.3.4",
              fn -> MyApp.Archive.read_data_set("1.2.3.4") end}
           ]}
        end

        @impl true
        def handle_get(_command, _query, _state) do
          {:ok, []}
        end
      end

  ## Callback Return Values

  - `handle_echo/2` and `handle_store/3` return `{:ok, status_code}` or
    `{:error, status_code, message}`.
  - `handle_find/3` returns `{:ok, [identifier_binary()]}` or
    `{:error, status_code, message}`.
  - `handle_move/3` and `handle_get/3` return `{:ok, [t:instance/0]}` or
    `{:error, status_code, message}`. See the next section.

  The status code is a DIMSE status (see `Dimse.Command.Status`).

  ## C-MOVE and C-GET sub-operations

  `handle_move/3` and `handle_get/3` return one `t:instance/0` per C-STORE
  sub-operation: `{sop_class_uid, sop_instance_uid, data}`. `data` is either
  the encoded data set as a binary (no Part 10 preamble or file meta group,
  the same bytes `handle_store/3` receives) or a `t:fetcher/0`, a zero-arity
  function that loads that data set on demand.

  The list length is the number of sub-operations, so Number of Remaining
  Sub-operations is exact from the first pending response and the
  `[:dimse, :sub_operation, :start]` event reports `total_instances` as the
  list length. Only the object bytes are lazy:

    * A binary element is sent as is.
    * A fetcher element is called on the association process right before its
      C-STORE, once the previous sub-operation has finished (C-GET: its
      C-STORE-RSP was received; C-MOVE: the C-STORE on the sub-association
      returned). The association keeps no reference to the returned bytes once
      the C-STORE has been sent, so they are reclaimable at the next garbage
      collection. A retrieve of thousands of objects references one data set
      at a time instead of the whole list.
    * The fetcher blocks the association process while it runs, like any other
      handler callback: PDUs for that association (A-ABORT, C-CANCEL) are not
      processed until it returns.
    * A fetcher returning `{:error, reason}` counts as one failed
      sub-operation: Number of Failed Sub-operations increments, the SOP
      Instance UID is added to the Failed SOP Instance UID List (0008,0058) of
      the final response, and the retrieve continues with the next element.
    * A fetcher that raises, throws, exits or returns any other term is also
      counted as failed and the retrieve continues. That is a bug in the
      handler, so the association first emits `[:dimse, :handler, :exception]`
      with `callback: :fetcher` and the exception in `reason`.
    * For C-GET the presentation context is resolved before the fetcher runs.
      An element whose SOP Class has no accepted presentation context is
      counted as failed without invoking its fetcher.
    * Binaries and fetchers can be mixed freely in one list.

  The final C-MOVE-RSP or C-GET-RSP has status `0xB000` when any
  sub-operation failed and then carries an Identifier with the Failed SOP
  Instance UID List (0008,0058) in sub-operation order (PS3.4 C.4.2.1.4.2 for
  C-MOVE, C.4.3.1.3.2 for C-GET), encoded in the transfer syntax negotiated for
  the request's presentation context. Under Explicit VR Little Endian the
  element length is a 16-bit field, so the list is cut to the leading UIDs that
  fit in 65,534 bytes; the counts in the command set stay exact.
  """

  @typedoc """
  Zero-arity function that loads one object's encoded data set on demand.

  Called by the association right before that object's C-STORE sub-operation.
  Returns `{:ok, data_set}` with the encoded data set (no Part 10 header) or
  `{:error, reason}`.
  """
  @type fetcher :: (-> {:ok, binary()} | {:error, term()})

  @typedoc """
  One C-STORE sub-operation of a C-MOVE or C-GET: SOP Class UID, SOP Instance
  UID and the object, either as the encoded data set or as a `t:fetcher/0`.
  """
  @type instance ::
          {sop_class_uid :: String.t(), sop_instance_uid :: String.t(), binary() | fetcher()}

  @doc "Called when a C-ECHO-RQ is received."
  @callback handle_echo(command :: map(), state :: Dimse.Association.State.t()) ::
              {:ok, integer()} | {:error, integer(), String.t()}

  @doc "Called when a C-STORE-RQ is received with a data set."
  @callback handle_store(
              command :: map(),
              data_set :: binary(),
              state :: Dimse.Association.State.t()
            ) ::
              {:ok, integer()} | {:error, integer(), String.t()}

  @doc "Called when a C-FIND-RQ is received. Return matching data sets."
  @callback handle_find(
              command :: map(),
              query :: binary(),
              state :: Dimse.Association.State.t()
            ) ::
              {:ok, [binary()]} | {:error, integer(), String.t()}

  @doc """
  Called when a C-MOVE-RQ is received.

  Return one `t:instance/0` per object to transfer to the move destination via
  C-STORE sub-operations. Each element carries the encoded data set or a
  `t:fetcher/0` that loads it right before its C-STORE. See "C-MOVE and C-GET
  sub-operations" in the module documentation for the full contract.
  """
  @callback handle_move(
              command :: map(),
              query :: binary(),
              state :: Dimse.Association.State.t()
            ) ::
              {:ok, [instance()]} | {:error, integer(), String.t()}

  @doc """
  Called when a C-GET-RQ is received.

  Return one `t:instance/0` per object to send back on the same association via
  C-STORE sub-operations. Each element carries the encoded data set or a
  `t:fetcher/0` that loads it right before its C-STORE. See "C-MOVE and C-GET
  sub-operations" in the module documentation for the full contract.
  """
  @callback handle_get(
              command :: map(),
              query :: binary(),
              state :: Dimse.Association.State.t()
            ) ::
              {:ok, [instance()]} | {:error, integer(), String.t()}

  # --- DIMSE-N callbacks (PS3.7 Chapter 10) ---

  @doc "Called when an N-GET-RQ is received. Return attribute data."
  @callback handle_n_get(command :: map(), state :: Dimse.Association.State.t()) ::
              {:ok, integer(), binary() | nil} | {:error, integer(), String.t()}

  @doc "Called when an N-SET-RQ is received with modification data."
  @callback handle_n_set(
              command :: map(),
              data_set :: binary(),
              state :: Dimse.Association.State.t()
            ) ::
              {:ok, integer(), binary() | nil} | {:error, integer(), String.t()}

  @doc "Called when an N-ACTION-RQ is received with action info."
  @callback handle_n_action(
              command :: map(),
              data_set :: binary(),
              state :: Dimse.Association.State.t()
            ) ::
              {:ok, integer(), binary() | nil} | {:error, integer(), String.t()}

  @doc """
  Called when an N-CREATE-RQ is received with attributes.

  Implementations may return `{:ok, status, data}` when the request already
  supplies the SOP Instance UID, or `{:ok, status, created_sop_instance_uid, data}`
  when the SCP generates the UID and needs it echoed in the N-CREATE-RSP command.
  """
  @callback handle_n_create(
              command :: map(),
              data_set :: binary(),
              state :: Dimse.Association.State.t()
            ) ::
              {:ok, integer(), binary() | nil}
              | {:ok, integer(), String.t(), binary() | nil}
              | {:error, integer(), String.t()}

  @doc "Called when an N-DELETE-RQ is received."
  @callback handle_n_delete(command :: map(), state :: Dimse.Association.State.t()) ::
              {:ok, integer()} | {:error, integer(), String.t()}

  @doc "Called when an N-EVENT-REPORT-RQ is received with event info."
  @callback handle_n_event_report(
              command :: map(),
              data_set :: binary(),
              state :: Dimse.Association.State.t()
            ) ::
              {:ok, integer(), binary() | nil} | {:error, integer(), String.t()}

  @doc """
  Returns the set of abstract syntaxes (SOP Class UIDs) this handler supports.

  Override this to declare which SOP Classes your SCP accepts during
  presentation context negotiation. Defaults to Verification only.
  """
  @callback supported_abstract_syntaxes() :: [String.t()]

  @doc """
  Resolves a C-MOVE destination AE title to a `{host, port}` tuple.

  Called by the SCP when processing a C-MOVE-RQ to determine where to
  open the outbound sub-association for C-STORE sub-operations.
  """
  @callback resolve_ae(ae_title :: String.t()) ::
              {:ok, {String.t(), pos_integer()}} | {:error, term()}

  @doc """
  Validates an incoming A-ASSOCIATE-RQ before presentation of application data.

  This callback can inspect calling/called AE titles and other association
  negotiation details to accept or reject the association.

  ## Return Values

    * `{:ok, nil}` — accept the association
    * `{:error, reason}` — reject the association; sends A-ASSOCIATE-RJ with
      result=1, source=1, reason=1

  When not implemented, the SCP accepts all associations at this stage.
  """
  @callback validate_association(
              request :: Dimse.Pdu.AssociateRq.t(),
              state :: Dimse.Association.State.t()
            ) :: {:ok, nil} | {:error, term()}

  @doc """
  Authenticates the requesting SCU during A-ASSOCIATE-RQ processing.

  Called when the incoming A-ASSOCIATE-RQ contains a `UserIdentity` sub-item
  (0x58). The SCP handler can inspect the identity and decide whether to accept
  or reject the association.

  ## Return Values

    * `{:ok, nil}` — accept the association; no server response included in AC
    * `{:ok, server_response}` — accept; include `server_response` binary in AC
      as `UserIdentityAc` (only sent when the SCU set
      `positive_response_requested = true`)
    * `{:error, reason}` — reject the association; sends A-ASSOCIATE-RJ with
      result=1, source=1, reason=1

  When not implemented, the SCP accepts all associations regardless of identity.
  """
  @callback handle_authenticate(
              user_identity :: Dimse.Pdu.UserIdentity.t(),
              state :: Dimse.Association.State.t()
            ) :: {:ok, nil | binary()} | {:error, term()}

  @optional_callbacks [
    supported_abstract_syntaxes: 0,
    resolve_ae: 1,
    validate_association: 2,
    handle_authenticate: 2,
    handle_n_get: 2,
    handle_n_set: 3,
    handle_n_action: 3,
    handle_n_create: 3,
    handle_n_delete: 2,
    handle_n_event_report: 3
  ]

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Dimse.Handler
    end
  end
end
