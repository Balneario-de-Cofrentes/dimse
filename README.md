# Dimse

[![Hex.pm](https://img.shields.io/hexpm/v/dimse.svg)](https://hex.pm/packages/dimse)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/dimse)
[![CI](https://github.com/Balneario-de-Cofrentes/dimse/actions/workflows/ci.yml/badge.svg)](https://github.com/Balneario-de-Cofrentes/dimse/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

```
██████╗ ██╗███╗   ███╗███████╗███████╗
██╔══██╗██║████╗ ████║██╔════╝██╔════╝
██║  ██║██║██╔████╔██║███████╗█████╗
██║  ██║██║██║╚██╔╝██║╚════██║██╔══╝
██████╔╝██║██║ ╚═╝ ██║███████║███████╗
╚═════╝ ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝

  DICOM networking for Elixir · PS3.7 + PS3.8
```

Pure Elixir DICOM DIMSE networking library for the BEAM.

Implements the DICOM Upper Layer Protocol ([PS3.8](https://dicom.nema.org/medical/dicom/current/output/html/part08.html)),
DIMSE-C ([PS3.7 Ch.9](https://dicom.nema.org/medical/dicom/current/output/html/part07.html#chapter_9)),
and DIMSE-N ([PS3.7 Ch.10](https://dicom.nema.org/medical/dicom/current/output/html/part07.html#chapter_10))
for building SCP (server) and SCU (client) applications. One GenServer per association
for fault isolation and natural backpressure.

## Features

- **Upper Layer Protocol** -- full PDU encode/decode for all 7 PDU types (PS3.8 §9.3)
- **Association state machine** -- GenServer-per-association with ARTIM timer (PS3.8 §9.2)
- **DIMSE-C services** -- C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET
- **DIMSE-N services** -- N-EVENT-REPORT, N-GET, N-SET, N-ACTION, N-CREATE, N-DELETE
- **SCP behaviour** -- `Dimse.Handler` callbacks for all 11 services
- **SCU client API** -- connect, echo, store, find, move, get, cancel, n_get, n_set, n_action, n_create, n_delete, n_event_report, release, abort
- **Presentation context negotiation** -- abstract syntax + transfer syntax matching
- **TLS / DICOM Secure Transport** -- PS3.15 Annex B, mutual TLS via OTP `:ssl` + Ranch SSL
- **Extended Negotiation (PS3.7 Annex D)** -- Role Selection, SOP Class Extended/Common Extended, User Identity authentication
- **Automatic lifecycle** -- `Dimse.with_connection/4` for connect/execute/release in one call
- **Error taxonomy** -- `Dimse.Error` with typed categories: transport, association, status, protocol
- **Telemetry** -- 17 events across 6 categories (association, PDU, command, negotiation, TLS, handler) via `:telemetry`
- **3 runtime deps** -- `dicom` + `ranch` + `telemetry`

## Installation

Add `dimse` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:dimse, "~> 0.8"}
  ]
end
```

## Quick Start

### C-ECHO SCP (Server)

```elixir
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
{:ok, assoc} = Dimse.connect("192.168.1.10", 11112,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP"
)

:ok = Dimse.echo(assoc)
:ok = Dimse.release(assoc)
```

### Automatic Lifecycle (`with_connection/4`)

```elixir
{:ok, results} = Dimse.with_connection("192.168.1.10", 11112,
  [calling_ae: "MY_SCU", called_ae: "REMOTE_SCP",
   abstract_syntaxes: ["1.2.840.10008.5.1.4.1.2.2.1"]],
  fn assoc ->
    {:ok, results} = Dimse.find(assoc, :study, query_data)
    results
  end
)
# Association is released automatically (or aborted on error)
```

### C-STORE SCU (Client)

```elixir
{:ok, assoc} = Dimse.connect("192.168.1.10", 11112,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP",
  abstract_syntaxes: ["1.2.840.10008.5.1.4.1.1.2"]
)

:ok = Dimse.store(assoc, sop_class_uid, sop_instance_uid, data_set)
:ok = Dimse.release(assoc)
```

### C-FIND SCU (Client)

```elixir
{:ok, assoc} = Dimse.connect("192.168.1.10", 11112,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP",
  abstract_syntaxes: ["1.2.840.10008.5.1.4.1.2.2.1"]
)

{:ok, results} = Dimse.find(assoc, :study, query_data)
:ok = Dimse.release(assoc)
```

### C-MOVE SCU (Client)

```elixir
{:ok, assoc} = Dimse.connect("192.168.1.10", 11112,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP",
  abstract_syntaxes: ["1.2.840.10008.5.1.4.1.2.2.2"]
)

# SCP pushes instances to DEST_SCP via C-STORE sub-ops
{:ok, result} = Dimse.move(assoc, :study, query_data, dest_ae: "DEST_SCP")
# result.completed, result.failed, result.warning

:ok = Dimse.release(assoc)
```

### C-GET SCU (Client)

```elixir
{:ok, assoc} = Dimse.connect("192.168.1.10", 11112,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP",
  abstract_syntaxes: [
    "1.2.840.10008.5.1.4.1.2.2.3",  # Study Root GET
    "1.2.840.10008.5.1.4.1.1.2"     # CT Image Storage (to receive)
  ]
)

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

{:ok, 0x0000, _reply} = Dimse.n_action(assoc, commitment_uid, instance_uid, 1, action_data)
{:ok, 0x0000, attrs}  = Dimse.n_get(assoc, sop_class_uid, sop_instance_uid)
{:ok, 0x0000, updated} = Dimse.n_set(assoc, sop_class_uid, sop_instance_uid, modifications)
{:ok, 0x0000, created_uid, created} = Dimse.n_create(assoc, sop_class_uid, attributes)
{:ok, 0x0000, nil}    = Dimse.n_delete(assoc, sop_class_uid, sop_instance_uid)
{:ok, 0x0000, _data}  = Dimse.n_event_report(assoc, sop_class_uid, sop_instance_uid, 1, event_data)

:ok = Dimse.release(assoc)
```

### TLS / DICOM Secure Transport (PS3.15 Annex B)

```elixir
# TLS SCP listener
{:ok, ref} = Dimse.start_listener(
  port: 2762,
  handler: MyApp.DicomHandler,
  tls: [
    certfile: "/path/to/server.pem",
    keyfile: "/path/to/server_key.pem"
  ]
)

# TLS SCU connection
{:ok, assoc} = Dimse.connect("192.168.1.10", 2762,
  calling_ae: "MY_SCU",
  called_ae: "REMOTE_SCP",
  abstract_syntaxes: ["1.2.840.10008.1.1"],
  tls: [
    cacertfile: "/path/to/ca.pem",
    verify: :verify_peer
  ]
)
```

Mutual TLS: add `cacertfile:`, `verify: :verify_peer`, and `fail_if_no_peer_cert: true` on
the SCP side, and `certfile:` + `keyfile:` on the SCU side. All standard OTP `:ssl` options
are passed through.

## DICOM Standard Coverage

All 11 DIMSE services, both SCP and SCU:

| Service | SCP | SCU | Description |
|---------|-----|-----|-------------|
| C-ECHO  | Yes | Yes | Verification |
| C-STORE | Yes | Yes | Store instances |
| C-FIND  | Yes | Yes | Query patient/study/series/instance |
| C-MOVE  | Yes | Yes | Retrieve via C-STORE sub-ops to destination AE |
| C-GET   | Yes | Yes | Retrieve via C-STORE sub-ops on same association |
| N-EVENT-REPORT | Yes | Yes | Event notification |
| N-GET   | Yes | Yes | Retrieve managed SOP Instance attributes |
| N-SET   | Yes | Yes | Modify managed SOP Instance attributes |
| N-ACTION | Yes | Yes | Request action on managed SOP Instance |
| N-CREATE | Yes | Yes | Create managed SOP Instance |
| N-DELETE | Yes | Yes | Delete managed SOP Instance |

The only unimplemented PS3.7 Annex D item is the Asynchronous Operations Window (0x53),
which requires concurrent in-flight request support — a future milestone.

## Testing

429 tests (419 unit/integration + 10 property-based), 96%+ line coverage.

```bash
mix test                          # Unit + integration tests
mix test --cover                  # With HTML coverage report
mix test --include interop        # Interop tests (requires Docker)
mix format --check-formatted      # Check formatting
```

### Interop Tests

Interop tests run against real DICOM implementations via Docker:

```bash
docker compose -f docker-compose.interop.yml up -d
mix test --include interop
docker compose -f docker-compose.interop.yml down
```

## Comparison

| | dimse | [DCMTK](https://github.com/DCMTK/dcmtk) | [dcm4che](https://github.com/dcm4che/dcm4che) | [pynetdicom](https://github.com/pydicom/pynetdicom) | [fo-dicom](https://github.com/fo-dicom/fo-dicom) | [wolfpacs](https://github.com/wolfpacs/wolfpacs) | [dicom-rs](https://github.com/Enet4/dicom-rs) |
|---|---|---|---|---|---|---|---|
| Language | Elixir | C++ | Java | Python | C#/.NET | Erlang | Rust |
| DIMSE-C | 5/5 | 5/5 | 5/5 | 5/5 | 5/5 | 2/5 | 2/5 |
| DIMSE-N | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 0/6 | 0/6 |
| SCP + SCU | Both | Both | Both | Both | Both | SCP only | SCU only |
| TLS | Yes | Yes | Yes | Yes | Yes | No | No |
| Extended negotiation | Yes | Yes | Yes | Yes | Yes | No | No |
| License | MIT | BSD-3 | MPL-1.1 | MIT | MS-PL | AGPL-3.0 | MIT/Apache |

`dimse` pairs with [`dicom`](https://hex.pm/packages/dicom) for a complete pure-Elixir DICOM toolkit:
`dicom` handles P10 files and data sets (PS3.5, PS3.6, PS3.10, PS3.18);
`dimse` handles DIMSE networking (PS3.7, PS3.8).

## Contributing

Contributions are welcome. Please read our [Contributing Guide](CONTRIBUTING.md)
and [Code of Conduct](CODE_OF_CONDUCT.md) before opening a PR.

## License

MIT -- see [LICENSE](LICENSE) for details.
