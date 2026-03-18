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
- **3 runtime deps** -- `dicom` + `ranch` + `telemetry`

## Installation

Add `dimse` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:dimse, "~> 0.5.0"}
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
{:ok, 0x0000, created} = Dimse.n_create(assoc, sop_class_uid, attributes)

# Delete a managed instance (N-DELETE)
{:ok, 0x0000, nil} = Dimse.n_delete(assoc, sop_class_uid, sop_instance_uid)

# Send an event notification (N-EVENT-REPORT)
{:ok, 0x0000, _data} = Dimse.n_event_report(assoc, sop_class_uid, sop_instance_uid, 1, event_data)

:ok = Dimse.release(assoc)
```

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

| Part | Title | Coverage |
|------|-------|----------|
| PS3.7 | DIMSE Service and Protocol | DIMSE-C (Ch.9) + DIMSE-N (Ch.10), command set encoding, command fields, status codes |
| PS3.8 | Network Communication Support | Upper Layer PDUs (all 7 types), association state machine, presentation context negotiation |

### DIMSE Services

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

## Testing

```bash
mix test              # Run all tests
mix test --cover      # Run with coverage report
mix format --check-formatted
```

Property-based tests using [StreamData](https://hex.pm/packages/stream_data)
verify PDU encode/decode roundtrips. Integration tests verify all 11 DIMSE
services (C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET, N-GET, N-SET, N-ACTION,
N-CREATE, N-DELETE, N-EVENT-REPORT) SCP/SCU interoperability over TCP.

## Project Positioning

`dimse` is the networking counterpart to [`dicom`](https://hex.pm/packages/dicom),
which handles DICOM P10 file parsing and writing. Together they provide a complete
pure-Elixir DICOM toolkit:

| Library | Scope | DICOM Parts |
|---------|-------|-------------|
| [`dicom`](https://hex.pm/packages/dicom) | P10 files, data sets, DICOM JSON | PS3.5, PS3.6, PS3.10, PS3.18 |
| `dimse` | DIMSE networking, SCP/SCU | PS3.7, PS3.8 |

### Comparison with Existing Libraries

| Feature | dimse | [wolfpacs](https://github.com/wolfpacs/wolfpacs) | [dicom.ex](https://github.com/jjedele/dicom.ex) |
|---------|-------|----------|----------|
| Language | Elixir | Erlang | Elixir |
| PDU decode/encode | All 7 types | 6/7 (no A-ASSOCIATE-RJ) | 6/7 (no A-ABORT) |
| Association state machine | 5-phase + ARTIM timer | gen_statem (2 states) | GenServer (4 states) |
| DIMSE-C services | C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET | C-ECHO, C-STORE | C-ECHO, C-STORE, partial C-FIND |
| DIMSE-N services | All 6 (N-GET, N-SET, N-ACTION, N-CREATE, N-DELETE, N-EVENT-REPORT) | None | None |
| SCP behaviour | `@behaviour` with 11 callbacks (5 DIMSE-C + 6 DIMSE-N) | Hardcoded routing | Event handler callbacks |
| SCU client | Full API (open/release/abort/echo) | gen_statem sender | No SCU |
| Max PDU fragmentation | Yes (encode + reassembly) | Yes (sender chunking) | Parsed, not enforced |
| ARTIM timer | PS3.8 compliant (30s default) | No | No |
| Telemetry | 6 event types | Logger only | Logger only |
| Transfer syntaxes | IVR LE, EVR LE | 3 uncompressed | 13 registered (3 decoded) |
| Property tests | StreamData (10 properties) | proper (extensive) | No |
| Tests | 202 (192 tests + 10 properties) | ~81 eunit + proper | ~25 |
| Runtime deps | 3 (dicom, ranch, telemetry) | 2 (ranch, recon) | 0 (stdlib only) |
| Source LOC | ~2,700 | ~14,500 | ~2,600 (+ 26K tag dict) |
| Maintained | Active | Active | Active |
| License | MIT | AGPL-3.0 | Apache-2.0 |

## AI-Assisted Development

This project welcomes AI-assisted contributions. See [AGENTS.md](AGENTS.md)
for instructions that AI coding assistants can use to work with this codebase,
and [CONTRIBUTING.md](CONTRIBUTING.md) for our AI contribution policy.

## Contributing

Contributions are welcome. Please read our [Contributing Guide](CONTRIBUTING.md)
and [Code of Conduct](CODE_OF_CONDUCT.md) before opening a PR.

## License

MIT -- see [LICENSE](LICENSE) for details.
