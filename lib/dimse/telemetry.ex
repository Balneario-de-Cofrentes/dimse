defmodule Dimse.Telemetry do
  @moduledoc """
  Telemetry event definitions and span helpers for the DIMSE library.

  All events are prefixed with `[:dimse, ...]` and follow the `:telemetry`
  span convention (`:start`, `:stop`, `:exception` suffixes) where applicable.

  ## Events

  ### Association Lifecycle

  - `[:dimse, :association, :start]` -- association process started
    - Measurements: `%{system_time: integer()}`
    - Metadata: `%{association_id: String.t(), mode: :scp | :scu}`

  - `[:dimse, :association, :stop]` -- association process ended normally
    - Measurements: `%{duration: integer(), bytes_received: integer(), bytes_sent: integer()}`
    - Metadata: `%{association_id: String.t(), reason: atom()}`

  - `[:dimse, :association, :exception]` -- association process crashed
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{association_id: String.t(), kind: atom(), reason: term()}`

  ### Negotiation

  - `[:dimse, :negotiation, :start]` -- A-ASSOCIATE-RQ received (SCP) or sent (SCU)
    - Measurements: `%{system_time: integer()}`
    - Metadata: `%{association_id: String.t(), mode: :scp | :scu, calling_ae: String.t(),
      called_ae: String.t(), proposed_contexts_count: non_neg_integer()}`

  - `[:dimse, :negotiation, :stop]` -- negotiation completed
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{association_id: String.t(), mode: :scp | :scu,
      accepted_contexts_count: non_neg_integer(), rejected_contexts_count: non_neg_integer(),
      result: :accepted | :rejected}`

  ### TLS

  - `[:dimse, :tls, :handshake]` -- successful TLS handshake completed
    - Measurements: `%{}`
    - Metadata: `%{association_id: String.t(), protocol_version: atom() | nil,
      cipher_suite: tuple() | nil}`

  ### PDU

  - `[:dimse, :pdu, :received]` -- PDU decoded from socket
    - Measurements: `%{byte_size: integer()}`
    - Metadata: `%{association_id: String.t(), pdu_type: atom()}`

  - `[:dimse, :pdu, :sent]` -- PDU encoded and sent to socket
    - Measurements: `%{byte_size: integer()}`
    - Metadata: `%{association_id: String.t(), pdu_type: atom()}`

  ### DIMSE Commands

  - `[:dimse, :command, :start]` -- DIMSE command processing started
    - Measurements: `%{system_time: integer()}`
    - Metadata: `%{association_id: String.t(), command_field: integer(), message_id: integer()}`

  - `[:dimse, :command, :stop]` -- DIMSE command processing completed
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{association_id: String.t(), command_field: integer(), status: integer()}`

  - `[:dimse, :command, :exception]` -- DIMSE command processing failed
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{association_id: String.t(), command_field: integer(), kind: atom(), reason: term()}`

  ### Handler Callbacks

  - `[:dimse, :handler, :start]` -- before SCP handler callback invoked
    - Measurements: `%{system_time: integer()}`
    - Metadata: `%{association_id: String.t(), callback: atom(), command_field: integer()}`

  - `[:dimse, :handler, :stop]` -- after SCP handler callback returns
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{association_id: String.t(), callback: atom(), status: integer()}`

  - `[:dimse, :handler, :exception]` -- SCP handler callback raised
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{association_id: String.t(), callback: atom(), kind: atom(), reason: term()}`

  ### Sub-Operations (C-GET / C-MOVE)

  - `[:dimse, :sub_operation, :start]` -- sub-operation processing begins
    - Measurements: `%{system_time: integer()}`
    - Metadata: `%{association_id: String.t(), type: :c_get | :c_move, total_instances: non_neg_integer()}`

  - `[:dimse, :sub_operation, :progress]` -- per sub-operation instance
    - Measurements: `%{}`
    - Metadata: `%{association_id: String.t(), type: :c_get | :c_move,
      completed: non_neg_integer(), failed: non_neg_integer(), remaining: non_neg_integer()}`

  - `[:dimse, :sub_operation, :stop]` -- all sub-operations complete
    - Measurements: `%{}`
    - Metadata: `%{association_id: String.t(), type: :c_get | :c_move,
      completed: non_neg_integer(), failed: non_neg_integer(), warning: non_neg_integer()}`

  ## Span Helper

      Dimse.Telemetry.span(:association, %{association_id: id}, fn ->
        {result, %{bytes_received: n}}
      end)
  """

  @doc """
  Executes a function within a telemetry span.

  Emits `[:dimse, event, :start]` before and `[:dimse, event, :stop]` or
  `[:dimse, event, :exception]` after execution.
  """
  @spec span(atom(), map(), (-> {term(), map()})) :: term()
  def span(event, metadata, fun)
      when is_atom(event) and is_map(metadata) and is_function(fun, 0) do
    :telemetry.span([:dimse, event], metadata, fun)
  end

  @doc """
  Emits a telemetry event with a flat event name atom.

  The atom is prefixed with `[:dimse, event]`.
  """
  @spec emit(atom(), map(), map()) :: :ok
  def emit(event, measurements \\ %{}, metadata \\ %{}) when is_atom(event) do
    :telemetry.execute([:dimse, event], measurements, metadata)
  end

  @doc """
  Emits a telemetry event with a list event name.

  The list is prefixed with `[:dimse | event_name]`.
  """
  @spec emit_event([atom()], map(), map()) :: :ok
  def emit_event(event_name, measurements \\ %{}, metadata \\ %{})
      when is_list(event_name) do
    :telemetry.execute([:dimse | event_name], measurements, metadata)
  end
end
