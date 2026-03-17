# Product Requirements Document: Dimse

**Pure Elixir DICOM DIMSE Networking Library**

| Field | Value |
|-------|-------|
| Version | 0.1.0 (draft) |
| Date | 2026-03-17 |
| Status | Scaffold complete, implementation pending |
| Repository | https://github.com/Balneario-de-Cofrentes/dimse |
| License | MIT |

---

## 1. Vision

**Dimse** will be the first production-grade, pure-Elixir DIMSE networking
library for the BEAM. It provides the DICOM Upper Layer Protocol (PS3.8) and
DIMSE-C message services (PS3.7) as a standalone, reusable library that any
Elixir application can consume to build DICOM SCP (server) and SCU (client)
applications.

The library leverages the BEAM's process model — one GenServer per association —
to deliver fault isolation, natural backpressure, and horizontal scalability
that is difficult to achieve in thread-based DIMSE implementations.

## 2. Problem Statement

No BEAM-native DIMSE networking library exists that is:

1. **Complete** — covers all DIMSE-C services (C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET)
2. **Correct** — implements the full Upper Layer state machine (PS3.8 Section 9.2)
3. **Production-grade** — handles 200+ concurrent associations with fault isolation
4. **Maintained** — actively developed and tested

Existing projects:

| Project | Status | Limitations |
|---------|--------|-------------|
| [wolfpacs](https://github.com/wolfpacs/wolfpacs) | Abandoned (~2020) | Partial PDU support, no SCP behaviour, no telemetry, monolithic |
| [dicom.ex](https://github.com/jjedele/dicom.ex) | Abandoned (~2021) | C-ECHO only, no state machine, no fragmentation |

Teams building DICOM applications on Elixir (PACS, RIS, AI inference gateways)
must currently implement DIMSE from scratch or shell out to DCMTK/dcm4che.

## 3. Target Users

1. **Phaos project** — the primary consumer. Phaos (`phaos_dimse` app) will wrap
   `dimse` with application-specific handlers for its PACS archive.

2. **Elixir PACS/RIS developers** — teams building medical imaging or radiology
   information systems on the BEAM.

3. **AI inference pipelines** — applications that receive DICOM instances via
   C-STORE and run AI models (classification, segmentation, report generation).

4. **Research teams** — medical imaging researchers who want a scriptable,
   testable DIMSE client for querying and retrieving studies from clinical PACS.

5. **DICOM gateway builders** — teams bridging legacy DIMSE systems with modern
   web APIs (DICOMweb, FHIR ImagingStudy).

## 4. Scope

### In Scope (v0.1.0 – v0.4.0)

- DICOM Upper Layer Protocol (PS3.8)
  - All 7 PDU types: A-ASSOCIATE-RQ/AC/RJ, P-DATA-TF, A-RELEASE-RQ/RP, A-ABORT
  - Sub-items: Presentation Context, Abstract/Transfer Syntax, User Information
  - Association state machine with ARTIM timer
  - Presentation context negotiation
  - Max PDU length negotiation and message fragmentation

- DIMSE-C Services (PS3.7)
  - C-ECHO (verification)
  - C-STORE (instance storage)
  - C-FIND (query)
  - C-MOVE (retrieve via push)
  - C-GET (retrieve via pull)

- SCP and SCU roles for all above services
- SCP behaviour (`Dimse.Handler`) with callbacks
- Telemetry events for observability
- Ranch-based TCP acceptor pool

### Out of Scope

- DIMSE-N services (N-CREATE, N-SET, N-GET, N-ACTION, N-EVENT-REPORT, N-DELETE) — future v0.5.0
- TLS/DICOM Secure Transport (PS3.15 Annex B) — future enhancement
- Extended negotiation items (SOP Class Extended Negotiation, User Identity) — future
- DICOM P10 file parsing/writing — provided by the `dicom` library
- DICOMweb (STOW-RS, WADO-RS, QIDO-RS) — separate concern
- OTP application callback — consumers manage their own supervision tree

## 5. Functional Requirements

### FR-1: PDU Encode/Decode

**All 7 PDU types must be correctly encoded and decoded per PS3.8 Section 9.3.**

| PDU Type | Hex | Struct | Encode | Decode |
|----------|-----|--------|--------|--------|
| A-ASSOCIATE-RQ | 0x01 | `Dimse.Pdu.AssociateRq` | Yes | Yes |
| A-ASSOCIATE-AC | 0x02 | `Dimse.Pdu.AssociateAc` | Yes | Yes |
| A-ASSOCIATE-RJ | 0x03 | `Dimse.Pdu.AssociateRj` | Yes | Yes |
| P-DATA-TF | 0x04 | `Dimse.Pdu.PDataTf` | Yes | Yes |
| A-RELEASE-RQ | 0x05 | `Dimse.Pdu.ReleaseRq` | Yes | Yes |
| A-RELEASE-RP | 0x06 | `Dimse.Pdu.ReleaseRp` | Yes | Yes |
| A-ABORT | 0x07 | `Dimse.Pdu.Abort` | Yes | Yes |

Sub-items within A-ASSOCIATE-RQ/AC:
- Application Context Item (type 0x10)
- Presentation Context Item (type 0x20 in RQ, 0x21 in AC)
- Abstract Syntax Sub-Item (type 0x30)
- Transfer Syntax Sub-Item (type 0x40)
- User Information Item (type 0x50)
- Maximum Length Sub-Item (type 0x51)
- Implementation Class UID Sub-Item (type 0x52)
- Implementation Version Name Sub-Item (type 0x55)

**Wire format**: All PDUs share the header `<<type::8, 0x00::8, length::32-big>>`.
The length field does not include the 6-byte header.

**Decoder contract**:
```elixir
@spec decode(binary()) :: {:ok, struct(), binary()} | {:incomplete, binary()} | {:error, term()}
```

**Encoder contract**:
```elixir
@spec encode(struct()) :: iodata()
```

The encoder MUST return iodata (not flat binaries) to avoid unnecessary copying
when sending to the TCP socket.

### FR-2: Association Lifecycle (State Machine)

**Implement the DICOM Upper Layer state machine per PS3.8 Section 9.2.**

States: `:idle`, `:negotiating`, `:established`, `:releasing`, `:closed`

Transitions:

```
Idle ──(A-ASSOCIATE-RQ received)──> Negotiating
Idle ──(connect + send A-ASSOCIATE-RQ)──> Negotiating (SCU mode)
Negotiating ──(A-ASSOCIATE-AC sent/received)──> Established
Negotiating ──(A-ASSOCIATE-RJ sent/received)──> Closed
Established ──(A-RELEASE-RQ received/sent)──> Releasing
Releasing ──(A-RELEASE-RP received/sent)──> Closed
Any ──(A-ABORT received/sent)──> Closed
Any ──(TCP close)──> Closed
Any ──(ARTIM timeout)──> Closed (send A-ABORT if possible)
```

Each association is a GenServer process that:
- Owns its TCP socket
- Maintains its state struct (`Dimse.Association.State`)
- Parses incoming PDUs from the socket buffer
- Validates PDU types against the current state
- Dispatches complete DIMSE messages to the handler
- Encodes and sends response PDUs
- Enforces the ARTIM timer (configurable, default 30s)
- Emits telemetry events

**ARTIM Timer** (PS3.8 Section 9.1.4):
- Started when TCP connection is accepted (waiting for A-ASSOCIATE-RQ)
- Restarted when A-RELEASE-RQ is sent/received (waiting for A-RELEASE-RP)
- Fires → send A-ABORT and close

### FR-3: DIMSE-C Services

| Service | Command Fields | Data Set | Description |
|---------|---------------|----------|-------------|
| C-ECHO | RQ: 0x0030, RSP: 0x8030 | No | Verification |
| C-STORE | RQ: 0x0001, RSP: 0x8001 | Yes (instance) | Store instance |
| C-FIND | RQ: 0x0020, RSP: 0x8020 | Yes (query/match) | Query |
| C-MOVE | RQ: 0x0021, RSP: 0x8021 | Yes (query) | Retrieve via push |
| C-GET | RQ: 0x0010, RSP: 0x8010 | Yes (query) | Retrieve via pull |

For each service, both SCP (receive request, send response) and SCU
(send request, receive response) must be implemented.

**C-FIND and C-MOVE/C-GET** involve multiple response messages:
- C-FIND: one RSP per match with status Pending (0xFF00), final RSP with Success
- C-MOVE/C-GET: RSP messages with sub-operation counts, plus sub-operation
  C-STORE requests (C-MOVE pushes to a third party; C-GET sends back on the
  same association)

### FR-4: Command Set Encoding

**Command sets are always encoded in Implicit VR Little Endian, regardless of
the negotiated transfer syntax (PS3.7 Section 6.3.1).**

Uses the `dicom` library for Implicit VR Little Endian encoding/decoding of
group 0000 elements:

| Tag | Name | VR | Description |
|-----|------|----|-------------|
| (0000,0000) | CommandGroupLength | UL | Remaining byte count |
| (0000,0002) | AffectedSOPClassUID | UI | SOP Class UID |
| (0000,0100) | CommandField | US | DIMSE operation type |
| (0000,0110) | MessageID | US | Request identifier |
| (0000,0120) | MessageIDBeingRespondedTo | US | Matching request ID |
| (0000,0700) | Priority | US | Request priority (0=MEDIUM, 1=HIGH, 2=LOW) |
| (0000,0800) | CommandDataSetType | US | 0x0101 = no data set |
| (0000,0900) | Status | US | Operation result |
| (0000,1020) | NumberOfRemainingSubOperations | US | C-MOVE/C-GET |
| (0000,1021) | NumberOfCompletedSubOperations | US | C-MOVE/C-GET |
| (0000,1022) | NumberOfFailedSubOperations | US | C-MOVE/C-GET |
| (0000,1023) | NumberOfWarningSubOperations | US | C-MOVE/C-GET |
| (0000,0600) | MoveDestination | AE | C-MOVE destination |

### FR-5: Presentation Context Negotiation

**The SCP must evaluate each proposed presentation context and accept, reject,
or accept with an alternative transfer syntax.**

Algorithm for each proposed context:

1. Is the abstract syntax (SOP Class UID) supported by the handler?
   - No → reject with reason 3 (abstract syntax not supported)
2. Is any proposed transfer syntax supported locally?
   - Yes → accept with the first matching transfer syntax
   - No → reject with reason 4 (transfer syntaxes not supported)

The negotiation module must be configurable:
- List of supported abstract syntaxes (from handler)
- List of supported transfer syntaxes (defaults to all known by `dicom`)

### FR-6: Transfer Syntax Negotiation

**Uses `Dicom.TransferSyntax` from the `dicom` library for the transfer syntax
registry.** The library's `all/0` function returns all 49 known transfer syntaxes.

Default supported transfer syntaxes for negotiation:
- Implicit VR Little Endian (`1.2.840.10008.1.2`)
- Explicit VR Little Endian (`1.2.840.10008.1.2.1`)

Applications may configure additional transfer syntaxes (e.g., compressed)
depending on their codec capabilities.

### FR-7: Max PDU Length Negotiation and Fragmentation

**Both sides advertise their max PDU length in the User Information item.
The effective max PDU length is the minimum of both sides' values.**

When encoding a DIMSE message for transmission:
1. Encode the command set (always fits in one PDV, typically < 200 bytes)
2. If a data set follows, split it into fragments of `(max_pdu_length - 12)` bytes
   (6 bytes PDU header + 4 bytes PDV header + 2 bytes flags)
3. Send each fragment as a P-DATA-TF PDU
4. Set `is_last: true` on the final fragment

The default max PDU length is 16,384 bytes (16 KB), the DICOM minimum. This can
be increased to 65,536 or higher for local-network deployments.

### FR-8: SCP Behaviour with Callbacks

**`Dimse.Handler` defines callbacks for each DIMSE-C service.**

```elixir
@callback handle_echo(command, state) :: {:ok, status} | {:error, status, message}
@callback handle_store(command, data_set, state) :: {:ok, status} | {:error, status, message}
@callback handle_find(command, query, state) :: {:ok, [data_set]} | {:error, status, message}
@callback handle_move(command, query, state) :: {:ok, [sop_instance_uid]} | {:error, status, message}
@callback handle_get(command, query, state) :: {:ok, [data_set]} | {:error, status, message}
```

A built-in `Dimse.Scp.Echo` module provides the default C-ECHO handler (always
returns Success).

### FR-9: SCU Client API

**Public API via the `Dimse` module:**

```elixir
# Connection
{:ok, assoc} = Dimse.connect(host, port, opts)

# Operations
:ok = Dimse.echo(assoc)
:ok = Dimse.store(assoc, data_set)
{:ok, results} = Dimse.find(assoc, :study, query)
:ok = Dimse.move(assoc, :study, query, dest_ae: "DEST")
{:ok, data_sets} = Dimse.get(assoc, :study, query)

# Teardown
:ok = Dimse.release(assoc)
:ok = Dimse.abort(assoc)
```

The SCU:
1. Opens a TCP connection
2. Sends A-ASSOCIATE-RQ with proposed presentation contexts
3. Waits for A-ASSOCIATE-AC (or RJ/timeout)
4. Returns the association pid for subsequent operations
5. Each operation is a GenServer call to the association process
6. `release/1` sends A-RELEASE-RQ and waits for RP
7. `abort/1` sends A-ABORT and closes immediately

### FR-10: PDU Fragment Reassembly

**P-DATA-TF PDUs may arrive in fragments due to TCP segmentation and PDU splitting.**

Two levels of reassembly:

1. **TCP level**: PDU bytes may arrive across multiple TCP reads. The association
   buffers incoming bytes and feeds them to the PDU decoder until a complete PDU
   is decoded (decoder returns `{:ok, pdu, rest}` vs `{:incomplete, buffer}`).

2. **DIMSE level**: A single DIMSE message may span multiple P-DATA-TF PDUs.
   The message assembler accumulates PDV data until `is_last: true` is received
   for both the command set and (if present) the data set.

## 6. Non-Functional Requirements

### NFR-1: Minimal Dependencies

3 runtime dependencies only:
- `dicom` — command set encoding, UID gen, TS registry, SOP classes
- `ranch` — TCP acceptor pool
- `telemetry` — observability

### NFR-2: Concurrent Associations

Support 200+ concurrent associations with:
- Fault isolation: one association crash must not affect others
- DynamicSupervisor `max_children` for backpressure
- Memory budget: ~2-4 KB per idle association (BEAM process overhead)

### NFR-3: Telemetry

All operations emit `:telemetry` events:
- Association lifecycle: start, stop, exception
- PDU: received, sent (with byte counts)
- DIMSE commands: start, stop, exception (with duration)

### NFR-4: Configurable Timeouts

| Timeout | Default | Purpose |
|---------|---------|---------|
| ARTIM | 30s | Association idle/release timer (PS3.8 §9.1.4) |
| DIMSE | 30s | Per-operation timeout |
| Association | 10 min | Max association lifetime |
| TCP connect | 30s | SCU connection timeout |

### NFR-5: Graceful Shutdown

When the listener is stopped:
1. Stop accepting new connections
2. Send A-RELEASE-RQ to all established associations
3. Wait for A-RELEASE-RP (with timeout)
4. A-ABORT any remaining associations
5. Close all TCP sockets

### NFR-6: Fault Isolation

Each association is an independent OTP process. Crash recovery:
- Association process crashes → DynamicSupervisor restarts it (configurable)
- TCP socket owned by the association → socket closes on crash
- Other associations are unaffected

### NFR-7: No OTP Application Callback

The library does NOT define an OTP application (`mod:` in `mix.exs`). Consumers
call `Dimse.start_listener/1` or supervise `Dimse.Listener` in their own
supervision tree. This gives consumers full control over the lifecycle.

## 7. Architecture

### Supervision Tree (SCP)

```
Consumer's Supervisor
  └── Dimse.Listener (wraps Ranch)
        ├── Ranch acceptor pool (N acceptors)
        │     └── on accept → Dimse.ConnectionHandler.start_link/3
        └── DynamicSupervisor (max_children: 200)
              ├── Dimse.Association (GenServer) -- assoc 1
              ├── Dimse.Association (GenServer) -- assoc 2
              └── ...
```

### Data Flow (SCP: Incoming C-STORE)

```
TCP Socket
  │
  ▼
Dimse.Association (GenServer)
  │ 1. Buffer incoming bytes
  │ 2. Feed to Dimse.Pdu.Decoder
  │ 3. A-ASSOCIATE-RQ → negotiate → send A-ASSOCIATE-AC
  │ 4. P-DATA-TF → accumulate fragments (Dimse.Message)
  │ 5. Complete message → decode command set (Dimse.Command)
  │ 6. Dispatch to handler (Dimse.Handler.handle_store/3)
  │ 7. Encode response command set
  │ 8. Fragment into P-DATA-TF PDUs (Dimse.Pdu.Encoder)
  │ 9. Send response PDUs
  ▼
TCP Socket (response)
```

### Data Flow (SCU: Outgoing C-STORE)

```
User code
  │ Dimse.store(assoc, data_set)
  ▼
Dimse.Association (GenServer call)
  │ 1. Encode command set (C-STORE-RQ, Implicit VR LE)
  │ 2. Encode data set per negotiated transfer syntax
  │ 3. Fragment into P-DATA-TF PDUs
  │ 4. Send PDUs
  │ 5. Wait for P-DATA-TF response
  │ 6. Reassemble → decode command set (C-STORE-RSP)
  │ 7. Check status
  ▼
{:ok, status} or {:error, status, message}
```

### PDU Wire Format Reference

#### Common Header (6 bytes)

```
Byte 0:    PDU Type (0x01-0x07)
Byte 1:    Reserved (0x00)
Bytes 2-5: PDU Length (uint32 big-endian, excludes header)
```

#### A-ASSOCIATE-RQ (type 0x01)

```
Bytes 0-1:   Protocol Version (uint16, always 1)
Bytes 2-3:   Reserved
Bytes 4-19:  Called AE Title (16 bytes, space-padded)
Bytes 20-35: Calling AE Title (16 bytes, space-padded)
Bytes 36-67: Reserved (32 bytes, all zeros)
Bytes 68+:   Variable items:
             - Application Context Item (type 0x10)
             - Presentation Context Items (type 0x20, one per context)
             - User Information Item (type 0x50)
```

#### P-DATA-TF (type 0x04)

```
Payload contains one or more Presentation Data Value (PDV) items:

PDV Item:
  Bytes 0-3: PDV Length (uint32 big-endian, includes context ID + flags)
  Byte 4:    Presentation Context ID (odd number, 1-255)
  Byte 5:    Message Control Header:
             Bit 0: 1 = command, 0 = data
             Bit 1: 1 = last fragment, 0 = more fragments
  Bytes 6+:  PDV data (command set or data set fragment)
```

## 8. API Design

### Public Module: `Dimse`

```elixir
# Listener management
@spec start_listener(keyword()) :: {:ok, term()} | {:error, term()}
@spec stop_listener(term()) :: :ok | {:error, term()}

# SCU connection
@spec connect(String.t(), pos_integer(), keyword()) :: {:ok, pid()} | {:error, term()}

# DIMSE-C operations (on an established association)
@spec echo(pid()) :: :ok | {:error, term()}
@spec store(pid(), term()) :: :ok | {:error, term()}
@spec find(pid(), atom(), term()) :: {:ok, [term()]} | {:error, term()}
@spec move(pid(), atom(), term(), keyword()) :: :ok | {:error, term()}
@spec get(pid(), atom(), term()) :: {:ok, [term()]} | {:error, term()}

# Teardown
@spec release(pid()) :: :ok | {:error, term()}
@spec abort(pid()) :: :ok | {:error, term()}
```

### Handler Behaviour: `Dimse.Handler`

```elixir
@callback handle_echo(map(), State.t()) :: {:ok, integer()} | {:error, integer(), String.t()}
@callback handle_store(map(), binary(), State.t()) :: {:ok, integer()} | {:error, integer(), String.t()}
@callback handle_find(map(), binary(), State.t()) :: {:ok, [binary()]} | {:error, integer(), String.t()}
@callback handle_move(map(), binary(), State.t()) :: {:ok, [String.t()]} | {:error, integer(), String.t()}
@callback handle_get(map(), binary(), State.t()) :: {:ok, [binary()]} | {:error, integer(), String.t()}
```

### Configuration: `Dimse.Association.Config`

```elixir
%Dimse.Association.Config{
  ae_title: "DIMSE",
  max_pdu_length: 16_384,
  max_associations: 200,
  association_timeout: 600_000,
  dimse_timeout: 30_000,
  artim_timeout: 30_000,
  num_acceptors: 10
}
```

## 9. Testing Strategy

### Unit Tests

| Area | Technique | Count (est.) |
|------|-----------|------|
| PDU decode | Binary fixtures → struct assertion | ~30 |
| PDU encode | Struct → binary → decode roundtrip | ~30 |
| PDU roundtrip | Property-based with StreamData | ~10 |
| Command fields | Constant value verification | ~25 |
| Status codes | Category classification | ~10 |
| Negotiation | Context matching scenarios | ~15 |
| State struct | Default values, field types | ~10 |

### Property-Based Tests

Using StreamData:
- PDU encode/decode roundtrip: generate random valid PDU structs, encode, decode,
  assert equality
- Command set roundtrip: generate random group 0000 element maps, encode, decode
- Fragmentation: generate random data sizes, fragment at random max PDU lengths,
  reassemble, assert equality

### Integration Tests

| Test | Description |
|------|-------------|
| C-ECHO round trip | Start SCP, connect SCU, verify echo, release |
| C-STORE round trip | Start SCP, connect SCU, store instance, verify handler called |
| C-FIND round trip | Start SCP, connect SCU, query, verify results |
| Association reject | Start SCP, connect with wrong AE title, verify rejection |
| Max associations | Start SCP, open max+1 associations, verify rejection |
| ARTIM timeout | Start SCP, connect without sending A-ASSOCIATE-RQ, verify timeout |
| Graceful shutdown | Start SCP, establish associations, stop listener, verify release |

### Interoperability Tests (Future)

| Tool | Test |
|------|------|
| DCMTK echoscu | SCU echo against dimse SCP |
| DCMTK storescu | SCU store against dimse SCP |
| DCMTK storescp | dimse SCU store against DCMTK SCP |
| DCMTK findscu | SCU find against dimse SCP |
| dcm4che | Full C-STORE/C-FIND/C-MOVE interop |

### Coverage Target

95%+ line coverage. All public API functions and all PDU decode/encode paths
must be covered.

## 10. Milestones

### v0.1.0: PDU Layer + C-ECHO

**Goal**: Minimal viable DIMSE — two nodes can associate and echo.

- [ ] PDU encode/decode for all 7 types + sub-items
- [ ] Association GenServer with full state machine
- [ ] ARTIM timer
- [ ] Presentation context negotiation
- [ ] Max PDU length negotiation
- [ ] C-ECHO SCP (via Handler behaviour)
- [ ] C-ECHO SCU (via Dimse.Scu.Echo)
- [ ] Listener with Ranch integration
- [ ] ConnectionHandler (Ranch protocol callback)
- [ ] Telemetry events (association + PDU)
- [ ] Property-based PDU roundtrip tests
- [ ] Integration test: C-ECHO round trip
- [ ] Interop test: DCMTK echoscu/echoscp

**Definition of done**: `Dimse.Scu.Echo.verify/1` succeeds against a `Dimse.start_listener/1`
SCP, and DCMTK `echoscu` succeeds against the same SCP.

### v0.2.0: C-STORE SCP/SCU

**Goal**: Store DICOM instances via DIMSE.

- [ ] DIMSE message assembly from P-DATA fragments (FR-10)
- [ ] Command set encode/decode via `dicom` library (FR-4)
- [ ] P-DATA fragmentation for large data sets (FR-7)
- [ ] C-STORE SCP handler callback
- [ ] C-STORE SCU function
- [ ] Command-level telemetry events
- [ ] Integration test: C-STORE round trip
- [ ] Interop: DCMTK storescu → dimse SCP

**Definition of done**: An Elixir application can receive DICOM instances from
DCMTK `storescu` and store them via the handler callback.

### v0.3.0: C-FIND SCP/SCU

**Goal**: Query DICOM data sets via DIMSE.

- [ ] C-FIND SCP with multi-response (Pending + Success)
- [ ] C-FIND SCU with result stream
- [ ] C-CANCEL support (cancel pending operations)
- [ ] Query levels: PATIENT, STUDY, SERIES, IMAGE
- [ ] Integration test: C-FIND round trip
- [ ] Interop: DCMTK findscu → dimse SCP

### v0.4.0: C-MOVE/C-GET

**Goal**: Retrieve studies via DIMSE.

- [ ] C-MOVE SCP (opens outbound sub-associations for C-STORE)
- [ ] C-MOVE SCU
- [ ] C-GET SCP (sends back on same association)
- [ ] C-GET SCU
- [ ] Sub-operation tracking (remaining, completed, failed, warning)
- [ ] Integration test: C-MOVE and C-GET round trips
- [ ] Interop: DCMTK movescu/getscu

### v0.5.0: DIMSE-N (Future)

- [ ] N-EVENT-REPORT
- [ ] N-GET
- [ ] N-SET
- [ ] N-ACTION
- [ ] N-CREATE
- [ ] N-DELETE
- [ ] Storage Commitment (PS3.4 Annex J)

## 11. Success Criteria

| Criterion | Target |
|-----------|--------|
| Interoperability | C-ECHO/C-STORE/C-FIND/C-MOVE pass with DCMTK and dcm4che |
| Concurrent associations | 200+ without degradation |
| Fault isolation | Single association crash does not affect others |
| Test coverage | 95%+ line coverage |
| Dependencies | 3 runtime deps (dicom, ranch, telemetry) |
| PDU correctness | All 7 PDU types encode/decode correctly per PS3.8 |
| State machine | Full PS3.8 Section 9.2 compliance |
| Zero panics | No unhandled exceptions in production paths |
| Documentation | @moduledoc on all modules, @doc on all public functions |
| Performance | C-ECHO round trip < 1ms on loopback |

## 12. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| PDU reassembly bugs | Data corruption, crashes | Property-based testing with randomized fragmentation |
| C-MOVE complexity | Sub-association management | Separate GenServer for sub-operation tracking |
| Memory exhaustion | OOM under burst load | Configurable max_pdu_length, TCP backpressure, max_children |
| Vendor interop | Some PACS send non-conformant PDUs | Lenient parsing mode, vendor-specific quirks module |
| State machine edge cases | Unexpected PDUs in wrong state | Exhaustive state × PDU type test matrix |
| `dicom` library coupling | API changes break command encoding | Pin `~> 0.4`, use stable public API only |

## 13. References

- [DICOM PS3.7](https://dicom.nema.org/medical/dicom/current/output/html/part07.html) — DIMSE Service and Protocol
- [DICOM PS3.8](https://dicom.nema.org/medical/dicom/current/output/html/part08.html) — Network Communication Support
- [DICOM PS3.8 Section 9.2](https://dicom.nema.org/medical/dicom/current/output/html/part08.html#sect_9.2) — State Machine
- [DICOM PS3.8 Section 9.3](https://dicom.nema.org/medical/dicom/current/output/html/part08.html#sect_9.3) — PDU Structure
- [DICOM PS3.7 Section 6.3](https://dicom.nema.org/medical/dicom/current/output/html/part07.html#sect_6.3) — Command Set Structure
- [Ranch Documentation](https://ninenines.eu/docs/en/ranch/2.1/guide/)
- [dicom library](https://hex.pm/packages/dicom) — DICOM P10 parser
- [DCMTK](https://dcmtk.org/) — Reference DIMSE implementation (C++)
- [dcm4che](https://www.dcm4che.org/) — Reference DIMSE implementation (Java)
- [wolfpacs](https://github.com/wolfpacs/wolfpacs) — Existing Elixir DIMSE (abandoned)
