defmodule Dimse.Association do
  @moduledoc """
  GenServer managing a single DICOM association lifecycle.

  Implements the DICOM Upper Layer state machine defined in PS3.8 Section 9.2.
  Each TCP connection spawns one Association process that owns the socket and
  manages the full lifecycle: negotiation, message exchange, and release/abort.

  ## State Machine

      Idle → (A-ASSOCIATE-RQ received) → Negotiating
      Negotiating → (accepted) → Established
      Established → (A-RELEASE-RQ) → Releasing
      Releasing → (A-RELEASE-RP) → Closed
      Any state → (A-ABORT or TCP close) → Closed

  ## Responsibilities

  - Parse incoming PDU stream from the TCP socket
  - Validate PDUs against current state (reject unexpected PDU types)
  - Negotiate presentation contexts and transfer syntaxes
  - Reassemble DIMSE messages from P-DATA-TF fragments
  - Dispatch complete DIMSE commands to the `Dimse.Handler` callback module
  - Encode and send response PDUs
  - Enforce ARTIM timer (Association Request/Reject/Release Timer)
  - Emit telemetry events for observability

  ## Supervision

  Association processes are started under a DynamicSupervisor with `max_children`
  for backpressure. When the limit is reached, new connections receive an
  A-ASSOCIATE-RJ with reason "local-limit-exceeded".

  See `Dimse.ConnectionHandler` for the Ranch integration that spawns these.
  """
  use GenServer

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end
end
