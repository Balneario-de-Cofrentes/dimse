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
        def handle_echo(_command, _state) do
          {:ok, 0x0000}
        end

        @impl true
        def handle_store(command, data_set, state) do
          sop_instance_uid = command[{0x0008, 0x0018}]
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

  All callbacks return `{:ok, status_code}` or `{:error, status_code, message}`.
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

  @doc "Called when a C-MOVE-RQ is received. Return SOP Instance UIDs to transfer."
  @callback handle_move(
              command :: map(),
              query :: binary(),
              state :: Dimse.Association.State.t()
            ) ::
              {:ok, [String.t()]} | {:error, integer(), String.t()}

  @doc "Called when a C-GET-RQ is received. Return data sets to send back."
  @callback handle_get(
              command :: map(),
              query :: binary(),
              state :: Dimse.Association.State.t()
            ) ::
              {:ok, [binary()]} | {:error, integer(), String.t()}

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Dimse.Handler
    end
  end
end
