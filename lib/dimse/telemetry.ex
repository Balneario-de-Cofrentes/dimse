defmodule Dimse.Telemetry do
  @moduledoc """
  Telemetry event definitions and span helpers for the DIMSE library.

  All events are prefixed with `[:dimse, ...]` and follow the `:telemetry`
  span convention (`:start`, `:stop`, `:exception` suffixes).

  ## Events

  ### Association Lifecycle

  - `[:dimse, :association, :start]` — association process started
    - Measurements: `%{system_time: integer()}`
    - Metadata: `%{association_id: String.t(), remote_ae: String.t(), local_ae: String.t()}`

  - `[:dimse, :association, :stop]` — association process ended normally
    - Measurements: `%{duration: integer(), bytes_received: integer(), bytes_sent: integer()}`
    - Metadata: `%{association_id: String.t(), reason: atom()}`

  - `[:dimse, :association, :exception]` — association process crashed
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{association_id: String.t(), kind: atom(), reason: term()}`

  ### PDU

  - `[:dimse, :pdu, :received]` — PDU decoded from socket
    - Measurements: `%{byte_size: integer()}`
    - Metadata: `%{association_id: String.t(), pdu_type: atom()}`

  - `[:dimse, :pdu, :sent]` — PDU encoded and sent to socket
    - Measurements: `%{byte_size: integer()}`
    - Metadata: `%{association_id: String.t(), pdu_type: atom()}`

  ### DIMSE Commands

  - `[:dimse, :command, :start]` — DIMSE command processing started
    - Measurements: `%{system_time: integer()}`
    - Metadata: `%{association_id: String.t(), command_field: integer(), message_id: integer()}`

  - `[:dimse, :command, :stop]` — DIMSE command processing completed
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{association_id: String.t(), command_field: integer(), status: integer()}`

  - `[:dimse, :command, :exception]` — DIMSE command processing failed
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{association_id: String.t(), command_field: integer(), kind: atom(), reason: term()}`

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
  Emits a telemetry event.
  """
  @spec emit(atom(), map(), map()) :: :ok
  def emit(event, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute([:dimse, event], measurements, metadata)
  end
end
