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
          # Return list of SOP Instance UIDs to send
          {:ok, []}
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
  - `handle_move/3` and `handle_get/3` return service-specific result lists or
    `{:error, status_code, message}`.

  The status code is a DIMSE status (see `Dimse.Command.Status`).
  """

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

  Return a list of `{sop_class_uid, sop_instance_uid, data}` tuples to transfer
  to the move destination via C-STORE sub-operations.
  """
  @callback handle_move(
              command :: map(),
              query :: binary(),
              state :: Dimse.Association.State.t()
            ) ::
              {:ok, [{String.t(), String.t(), binary()}]} | {:error, integer(), String.t()}

  @doc """
  Called when a C-GET-RQ is received.

  Return a list of `{sop_class_uid, sop_instance_uid, data}` tuples to send
  back on the same association via C-STORE sub-operations.
  """
  @callback handle_get(
              command :: map(),
              query :: binary(),
              state :: Dimse.Association.State.t()
            ) ::
              {:ok, [{String.t(), String.t(), binary()}]} | {:error, integer(), String.t()}

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
