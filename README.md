# Dimse

[![Hex.pm](https://img.shields.io/hexpm/v/dimse.svg)](https://hex.pm/packages/dimse)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/dimse)
[![CI](https://github.com/Balneario-de-Cofrentes/dimse/actions/workflows/ci.yml/badge.svg)](https://github.com/Balneario-de-Cofrentes/dimse/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Pure Elixir DICOM DIMSE networking library for the BEAM.

Implements the DICOM Upper Layer Protocol ([PS3.8](https://dicom.nema.org/medical/dicom/current/output/html/part08.html)),
DIMSE-C message services ([PS3.7 Ch.9](https://dicom.nema.org/medical/dicom/current/output/html/part07.html#chapter_9)),
and DIMSE-N notification/management services ([PS3.7 Ch.10](https://dicom.nema.org/medical/dicom/current/output/html/part07.html#chapter_10))
for building SCP (server) and SCU (client) applications.

Built on Elixir's binary pattern matching for fast, correct PDU parsing, with
one GenServer per association for fault isolation and natural backpressure.

## Features

- **Upper Layer Protocol** -- full PDU encode/decode for all 7 PDU types (PS3.8 Section 9.3)
- **Association state machine** -- GenServer-per-association with ARTIM timer (PS3.8 Section 9.2)
- **DIMSE-C services** -- C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET
- **DIMSE-N services** -- N-EVENT-REPORT, N-GET, N-SET, N-ACTION, N-CREATE, N-DELETE
- **SCP behaviour** -- `Dimse.Handler` callbacks for implementing DICOM servers (all 11 services)
- **SCU client API** -- connect, echo, store, find, move, get, cancel, n_get, n_set, n_action, n_create, n_delete, n_event_report, release, abort
- **Presentation context negotiation** -- abstract syntax + transfer syntax matching
- **Max PDU length negotiation** -- with automatic message fragmentation
- **Telemetry** -- `:telemetry`-based events for association lifecycle, PDU, and command metrics
- **Built-in C-ECHO** -- SCP and SCU implementations for verification (DICOM "ping")
- **TLS / DICOM Secure Transport** -- PS3.15 Annex B via OTP `:ssl` + Ranch SSL, mutual TLS support
- **3 runtime deps** -- `dicom` + `ranch` + `telemetry` (`:ssl`/`:public_key` are OTP stdlib)

## Installation

Add `dimse` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:dimse, "~> 0.6.0"}
  ]
end
```

## Quick Start

### C-ECHO SCP (Server)

```elixir
defmodule MyApp.DicomHandler do
  @behaviour Dimse.Handler

  @impl true
  def handle_echo(_command, _state), do: {:ok, 0x0000}

  @impl true
  def handle_store(_command, data_set, _state) do
    # Persist the DICOM instance...
    {:ok, 0x0000}
  end

  @impl true
  def handle_find(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_move(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_get(_command, _query, _state), do: {:ok, []}

  # Optional: resolve C-MOVE destination AE titles
  def resolve_ae("DEST_SCP"), do: {:ok, {"192.168.1.20", 11112}}
  def resolve_ae(_), do: {:error, :unknown_ae}
end

# Start the listener
{:ok, _ref} = Dimse.start_listener(
  port: 11112,
  handler: MyApp.DicomHandler,
  ae_title: "MY_SCP",
  max_associations: 200
)
```

### C-ECHO SCU (Client)

```elixir
# Open an association
{:ok, assoc} = Dimse.connect("192.168.1.10", 11112,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP"
)

# Verify connectivity (DICOM "ping")
:ok = Dimse.echo(assoc)

# Release the association
:ok = Dimse.release(assoc)
```

### C-STORE SCU (Client)

```elixir
# Open an association proposing CT Image Storage
{:ok, assoc} = Dimse.connect("192.168.1.10", 11112,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP",
  abstract_syntaxes: ["1.2.840.10008.5.1.4.1.1.2"]
)

# Store a DICOM instance
:ok = Dimse.store(assoc, sop_class_uid, sop_instance_uid, data_set)

# Release the association
:ok = Dimse.release(assoc)
```

### C-FIND SCU (Client)

```elixir
# Open an association proposing Study Root Query/Retrieve
{:ok, assoc} = Dimse.connect("192.168.1.10", 11112,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP",
  abstract_syntaxes: ["1.2.840.10008.5.1.4.1.2.2.1"]
)

# Query for matching studies (query_data is an encoded DICOM identifier)
{:ok, results} = Dimse.find(assoc, :study, query_data)

# Or use the SOP Class UID directly
{:ok, results} = Dimse.find(assoc, "1.2.840.10008.5.1.4.1.2.2.1", query_data)

# Release the association
:ok = Dimse.release(assoc)
```

### C-MOVE SCU (Client)

```elixir
# Open an association proposing Study Root Query/Retrieve MOVE
{:ok, assoc} = Dimse.connect("192.168.1.10", 11112,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP",
  abstract_syntaxes: ["1.2.840.10008.5.1.4.1.2.2.2"]
)

# Retrieve matching studies — SCP pushes to DEST_SCP via C-STORE sub-ops
{:ok, result} = Dimse.move(assoc, :study, query_data, dest_ae: "DEST_SCP")
# result.completed, result.failed, result.warning

:ok = Dimse.release(assoc)
```

### C-GET SCU (Client)

```elixir
# Open an association proposing Study Root GET + storage SOP classes to receive
{:ok, assoc} = Dimse.connect("192.168.1.10", 11112,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP",
  abstract_syntaxes: [
    "1.2.840.10008.5.1.4.1.2.2.3",  # Study Root GET
    "1.2.840.10008.5.1.4.1.1.2"     # CT Image Storage (to receive)
  ]
)

# Retrieve matching instances on the same association
{:ok, data_sets} = Dimse.get(assoc, :study, query_data)

:ok = Dimse.release(assoc)
```

### DIMSE-N SCU (Client)

```elixir
# Storage Commitment example (PS3.4 Annex J)
commitment_uid = "1.2.840.10008.1.20.1"

{:ok, assoc} = Dimse.connect("192.168.1.10", 11112,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP",
  abstract_syntaxes: [commitment_uid]
)

# Request storage commitment (N-ACTION)
{:ok, 0x0000, _reply} = Dimse.n_action(assoc, commitment_uid, instance_uid, 1, action_data)

# Retrieve attributes (N-GET)
{:ok, 0x0000, attrs} = Dimse.n_get(assoc, sop_class_uid, sop_instance_uid)

# Modify attributes (N-SET)
{:ok, 0x0000, updated} = Dimse.n_set(assoc, sop_class_uid, sop_instance_uid, modifications)

# Create a managed instance (N-CREATE)
{:ok, 0x0000, created_sop_instance_uid, created} =
  Dimse.n_create(assoc, sop_class_uid, attributes)

# Delete a managed instance (N-DELETE)
{:ok, 0x0000, nil} = Dimse.n_delete(assoc, sop_class_uid, sop_instance_uid)

# Send an event notification (N-EVENT-REPORT)
{:ok, 0x0000, _data} = Dimse.n_event_report(assoc, sop_class_uid, sop_instance_uid, 1, event_data)

:ok = Dimse.release(assoc)
```

### TLS / DICOM Secure Transport (PS3.15 Annex B)

```elixir
# Start a TLS-enabled SCP listener
{:ok, ref} = Dimse.start_listener(
  port: 2762,
  handler: MyApp.DicomHandler,
  tls: [
    certfile: "/path/to/server.pem",
    keyfile: "/path/to/server_key.pem"
  ]
)

# Connect an SCU over TLS
{:ok, assoc} = Dimse.connect("192.168.1.10", 2762,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP",
  abstract_syntaxes: ["1.2.840.10008.1.1"],
  tls: [
    cacertfile: "/path/to/ca.pem",
    verify: :verify_peer
  ]
)

:ok = Dimse.echo(assoc)
:ok = Dimse.release(assoc)
```

Mutual TLS (client certificate verification):

```elixir
# SCP requires client certificate
{:ok, ref} = Dimse.start_listener(
  port: 2762,
  handler: MyApp.DicomHandler,
  tls: [
    certfile: "/path/to/server.pem",
    keyfile: "/path/to/server_key.pem",
    cacertfile: "/path/to/ca.pem",
    verify: :verify_peer,
    fail_if_no_peer_cert: true
  ]
)

# SCU provides client certificate
{:ok, assoc} = Dimse.connect("192.168.1.10", 2762,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP",
  tls: [
    cacertfile: "/path/to/ca.pem",
    certfile: "/path/to/client.pem",
    keyfile: "/path/to/client_key.pem",
    verify: :verify_peer
  ]
)
```

All standard OTP `:ssl` options are passed through — no opinionated wrappers.

## Architecture

```
lib/dimse/
  dimse.ex              -- Public API facade
  pdu.ex                -- 7 PDU type structs + sub-items
  pdu/
    decoder.ex          -- Binary → struct (PS3.8 §9.3)
    encoder.ex          -- Struct → iodata
  association.ex        -- GenServer: Upper Layer state machine
  association/
    state.ex            -- Association state struct
    negotiation.ex      -- Presentation context matching
    config.ex           -- Timeouts, AE titles, max PDU
  command.ex            -- Command set encode/decode (group 0000)
  command/
    fields.ex           -- Command field constants (PS3.7 §E)
    status.ex           -- DIMSE status codes (PS3.7 §C)
  message.ex            -- DIMSE message assembly from P-DATA fragments
  listener.ex           -- Ranch listener lifecycle
  connection_handler.ex -- Ranch protocol → Association
  handler.ex            -- SCP behaviour
  scp/echo.ex           -- Built-in C-ECHO SCP
  scu.ex                -- SCU client API
  scu/echo.ex           -- C-ECHO SCU
  scu/store.ex          -- C-STORE SCU
  scu/find.ex           -- C-FIND SCU
  scu/move.ex           -- C-MOVE SCU
  scu/get.ex            -- C-GET SCU
  scu/n_get.ex          -- N-GET SCU
  scu/n_set.ex          -- N-SET SCU
  scu/n_action.ex       -- N-ACTION SCU
  scu/n_create.ex       -- N-CREATE SCU
  scu/n_delete.ex       -- N-DELETE SCU
  scu/n_event_report.ex -- N-EVENT-REPORT SCU
  telemetry.ex          -- Event definitions
```

## DICOM Standard Coverage

### Services -- 11/11

All DIMSE-C (PS3.7 Ch.9) and DIMSE-N (PS3.7 Ch.10) services, both SCP and SCU:

| Service | SCP | SCU | Description |
|---------|-----|-----|-------------|
| C-ECHO  | Yes | Yes | Verification (connectivity test) |
| C-STORE | Yes | Yes | Store DICOM instances |
| C-FIND  | Yes | Yes | Query patient/study/series/instance |
| C-MOVE  | Yes | Yes | Retrieve via C-STORE sub-ops to destination AE |
| C-GET   | Yes | Yes | Retrieve via C-STORE sub-ops on same association |
| N-EVENT-REPORT | Yes | Yes | Event notification |
| N-GET   | Yes | Yes | Retrieve managed SOP Instance attributes |
| N-SET   | Yes | Yes | Modify managed SOP Instance attributes |
| N-ACTION | Yes | Yes | Request action on managed SOP Instance |
| N-CREATE | Yes | Yes | Create managed SOP Instance |
| N-DELETE | Yes | Yes | Delete managed SOP Instance |

### Upper Layer Protocol (PS3.8)

| Component | Status |
|-----------|--------|
| All 7 PDU types | Complete |
| Association state machine (5-phase + ARTIM) | Complete |
| Presentation context negotiation | Complete |
| Max PDU length negotiation + fragmentation | Complete |
| Implementation Class UID / Version Name | Complete |
| Command set encoding (Implicit VR LE, PS3.7 6.3.1) | Complete |
| Status code handling (success/warning/failure/cancel/pending) | Complete |
| Sub-operation tracking (C-MOVE/C-GET remaining/completed/failed/warning) | Complete |
| C-CANCEL support | Complete |

### Not Yet Implemented

| Feature | Priority | Notes |
|---------|----------|-------|
| SOP Class Extended Negotiation (0x56) | Medium | Role selection for SOP classes |
| SOP Class Common Extended Negotiation (0x57) | Medium | Service class-wide negotiation |
| User Identity Negotiation (0x58/0x59) | Medium | Username/password/Kerberos |
| Asynchronous Operations Window (0x53) | Low | Multi-message pipelining |

## Testing

206 tests + 10 property-based tests, 0 failures.

```bash
mix test              # Run all tests
mix test --cover      # Run with coverage report
mix format --check-formatted
```

Property-based tests using [StreamData](https://hex.pm/packages/stream_data)
verify PDU encode/decode roundtrips. Integration tests verify all 11 DIMSE
services end-to-end over TCP and TLS.

## Competitive Analysis

`dimse` is one of only 5 libraries in any language that implements all 11 DIMSE
services with both SCP and SCU roles. The others are DCMTK (C++), dcm4che (Java),
pynetdicom (Python), and fo-dicom (C#/.NET).

### Cross-Language Comparison

| Feature | dimse | [DCMTK](https://github.com/DCMTK/dcmtk) | [dcm4che](https://github.com/dcm4che/dcm4che) | [pynetdicom](https://github.com/pydicom/pynetdicom) | [fo-dicom](https://github.com/fo-dicom/fo-dicom) | [dicom-rs](https://github.com/Enet4/dicom-rs) |
|---------|-------|-------|---------|------------|----------|----------|
| Language | Elixir | C++ | Java | Python | C#/.NET | Rust |
| License | MIT | BSD-3 | MPL-1.1 | MIT | MS-PL | MIT/Apache |
| DIMSE-C services | 5/5 | 5/5 | 5/5 | 5/5 | 5/5 | 2/5 |
| DIMSE-N services | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 0/6 |
| SCP + SCU | Both | Both | Both | Both | Both | SCU only |
| TLS | Yes | Yes | Yes | Yes | Yes | No |
| Extended negotiation | No | Yes | Yes | Yes | Yes | No |
| Async ops window | No | Yes | Partial | Negotiation only | Yes | No |
| Telemetry | `:telemetry` | Logging | Logging | Events | Events | -- |
| Concurrency model | GenServer/OTP | Threads | Threads | Threads | async/await | -- |
| Runtime deps | 3 | Many | JDK | pydicom | .NET | Minimal |

### BEAM Ecosystem

| Feature | dimse | [wolfpacs](https://github.com/wolfpacs/wolfpacs) | [dicom.ex](https://github.com/jjedele/dicom.ex) |
|---------|-------|----------|----------|
| Language | Elixir | Erlang | Elixir |
| License | MIT | AGPL-3.0 | Apache-2.0 |
| DIMSE-C services | 5/5 (SCP+SCU) | 2/5 (C-ECHO, C-STORE) | 2.5/5 (SCP only) |
| DIMSE-N services | 6/6 (SCP+SCU) | 0/6 | 0/6 |
| All 7 PDU types | Yes | 6/7 | 6/7 |
| ARTIM timer | Yes | No | No |
| SCU client API | Full | Partial | None |
| Tests | 216 (206 + 10 prop) | ~81 | ~25 |
| Status | Active | Sporadic | Inactive |

### Ecosystem Positioning

`dimse` is the networking counterpart to [`dicom`](https://hex.pm/packages/dicom),
which handles DICOM P10 file parsing and writing. Together they provide a complete
pure-Elixir DICOM toolkit:

| Library | Scope | DICOM Parts |
|---------|-------|-------------|
| [`dicom`](https://hex.pm/packages/dicom) | P10 files, data sets, DICOM JSON | PS3.5, PS3.6, PS3.10, PS3.18 |
| `dimse` | DIMSE networking, SCP/SCU | PS3.7, PS3.8 |

## AI-Assisted Development

This project welcomes AI-assisted contributions. See [AGENTS.md](AGENTS.md)
for instructions that AI coding assistants can use to work with this codebase,
and [CONTRIBUTING.md](CONTRIBUTING.md) for our AI contribution policy.

## Contributing

Contributions are welcome. Please read our [Contributing Guide](CONTRIBUTING.md)
and [Code of Conduct](CODE_OF_CONDUCT.md) before opening a PR.

## License

MIT -- see [LICENSE](LICENSE) for details.
