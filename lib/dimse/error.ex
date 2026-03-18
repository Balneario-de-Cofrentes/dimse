defmodule Dimse.Error do
  @moduledoc """
  Error taxonomy for the Dimse library.

  All public functions in `Dimse` return `{:ok, result}` or `{:error, reason}`.
  This module documents the error categories and provides types for downstream
  pattern matching and specs.

  ## Error Categories

  ### 1. Transport Errors

  Failures at the TCP/TLS layer before or during DICOM protocol exchange.

      {:error, :econnrefused}          # Remote host refused TCP connection
      {:error, :timeout}               # TCP connect or DIMSE operation timed out
      {:error, :closed}                # Connection closed unexpectedly
      {:error, {:tcp_error, reason}}   # TCP socket error (e.g., :etimedout, :ehostunreach)
      {:error, {:tls_error, reason}}   # TLS handshake or protocol error

  **Recovery**: retry with backoff, check network, verify host/port.

  ### 2. Association Lifecycle Errors

  Failures during A-ASSOCIATE negotiation or unexpected termination.

      {:error, {:rejected, result, source, reason}}  # A-ASSOCIATE-RJ received
      {:error, {:aborted, source, reason}}            # A-ABORT received
      {:error, :no_accepted_contexts}                 # No presentation contexts accepted
      {:error, :authentication_failed}                # User identity rejected by SCP

  **Recovery**: check AE titles, SOP classes, transfer syntaxes, credentials.

  The `result`, `source`, and `reason` fields in rejection/abort tuples follow
  PS3.8 Section 9.3.4 (A-ASSOCIATE-RJ) and Section 9.3.8 (A-ABORT):

  - `result`: 1 = rejected-permanent, 2 = rejected-transient
  - `source`: 1 = DICOM UL service-user, 2 = DICOM UL service-provider (ACSE), 3 = presentation
  - `reason`: varies by source (see PS3.8 Table 9-21)

  ### 3. DIMSE Status Errors

  The remote peer returned a non-success DIMSE status in its response.

      {:error, {:status, code}}              # DIMSE-C failure status
      {:error, {:status, code, data}}        # DIMSE-N failure status (may include data)
      {:error, {:cancelled, partial_results}} # C-FIND cancelled with partial results

  Use `Dimse.Command.Status.category/1` to classify status codes:
  `:success`, `:pending`, `:cancel`, `:warning`, `:failure`.

  **Recovery**: inspect the status code (PS3.7 Annex C) for operation-specific meaning.

  ### 4. Protocol Errors

  Violations of the DICOM protocol detected during message exchange.

      {:error, :no_accepted_context}         # No negotiated context for the SOP class
      {:error, :unexpected_pdu}              # PDU received in wrong state
      {:error, :unexpected_command}          # Unknown command field
      {:error, {:decode_error, reason}}      # PDU binary decoding failed
      {:error, {:message_assembly_error, reason}} # DIMSE message assembly failed
      {:error, :invalid_presentation_context}     # Request on non-negotiated context
      {:error, :artim_timeout}               # ARTIM timer expired (PS3.8 Section 9.1.4)

  **Recovery**: these indicate a protocol bug in the peer or the library.
  Log and investigate.

  ### 5. Process-Level Failures

  The association GenServer process exited. These are NOT returned as
  `{:error, reason}` — they surface as process exits or monitor messages.

  The `Dimse.Association` GenServer exits with the reason that caused
  termination (e.g., `:normal` after release, `{:aborted, source, reason}`
  after abort). Callers using `Dimse.connect/3` never see raw process exits;
  the SCU layer translates them to `{:error, reason}` tuples.

  If you hold a reference to an association pid directly (e.g., from
  `Dimse.Association.start/1`), use `Process.monitor/1` to detect
  unexpected termination.

  ## Error Contract by Operation

  | Operation        | Success                                    | Error                                    |
  |------------------|--------------------------------------------|------------------------------------------|
  | `connect/3`      | `{:ok, pid}`                               | `{:error, reason}` (transport/lifecycle) |
  | `echo/2`         | `:ok`                                      | `{:error, {:status, code} \\| reason}`    |
  | `store/5`        | `:ok`                                      | `{:error, {:status, code} \\| reason}`    |
  | `find/4`         | `{:ok, [binary()]}`                        | `{:error, {:cancelled, [binary()]} \\| {:status, code} \\| reason}` |
  | `move/4`         | `{:ok, %{completed: n, failed: n, ...}}`  | `{:error, {:status, code} \\| reason}`    |
  | `get/4`          | `{:ok, [binary()]}`                        | `{:error, {:status, code} \\| reason}`    |
  | `n_get/4`        | `{:ok, status, data}`                      | `{:error, {:status, status, data} \\| reason}` |
  | `n_set/5`        | `{:ok, status, data}`                      | `{:error, {:status, status, data} \\| reason}` |
  | `n_action/6`     | `{:ok, status, data}`                      | `{:error, {:status, status, data} \\| reason}` |
  | `n_create/4`     | `{:ok, status, uid, data}`                 | `{:error, {:status, status, data} \\| reason}` |
  | `n_delete/4`     | `{:ok, status, nil}`                       | `{:error, {:status, status, nil} \\| reason}` |
  | `n_event_report/6` | `{:ok, status, data}`                    | `{:error, {:status, status, data} \\| reason}` |
  | `release/2`      | `:ok`                                      | `{:error, reason}`                       |
  | `abort/1`        | `:ok`                                      | (never fails)                            |
  """

  @typedoc "Transport-layer error reasons."
  @type transport_error ::
          :econnrefused
          | :timeout
          | :closed
          | {:tcp_error, term()}
          | {:tls_error, term()}

  @typedoc "Association negotiation/lifecycle error reasons."
  @type association_error ::
          {:rejected, pos_integer(), pos_integer(), non_neg_integer()}
          | {:aborted, non_neg_integer(), non_neg_integer()}
          | :no_accepted_contexts
          | :authentication_failed

  @typedoc "DIMSE status error reasons."
  @type status_error ::
          {:status, integer()}
          | {:status, integer(), binary() | nil}
          | {:cancelled, [binary()]}

  @typedoc "Protocol-level error reasons."
  @type protocol_error ::
          :no_accepted_context
          | :unexpected_pdu
          | :unexpected_command
          | {:decode_error, term()}
          | {:message_assembly_error, term()}
          | :invalid_presentation_context
          | :artim_timeout

  @typedoc "Any error reason returned by Dimse public functions."
  @type reason :: transport_error() | association_error() | status_error() | protocol_error()
end
