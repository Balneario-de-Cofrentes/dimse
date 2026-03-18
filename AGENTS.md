# AGENTS.md

Instructions for AI coding assistants working with this codebase.

## Project Overview

Pure Elixir DICOM DIMSE networking library. 3 runtime dependencies (dicom, ranch, telemetry).
Implements the DICOM Upper Layer Protocol (PS3.8) and DIMSE-C and DIMSE-N message services (PS3.7 Chapters 9-10)
for building SCP (server) and SCU (client) DICOM applications on the BEAM.

## Build and Test

```bash
mix deps.get                     # Install dependencies
mix compile                      # Compile
mix test                         # Run all tests
mix test --cover                 # Run with coverage
mix format --check-formatted     # Check formatting
mix docs                         # Generate documentation
```

## Architecture

```
lib/dimse.ex                     -- Public API facade: start_listener, connect, echo, store, find, move, get
lib/dimse/
  pdu.ex                         -- PDU type structs (7 types + sub-items)
  pdu/
    decoder.ex                   -- Binary → PDU struct (PS3.8 Section 9.3)
    encoder.ex                   -- PDU struct → iodata
  association.ex                 -- GenServer: Upper Layer state machine (PS3.8 Section 9.2)
  association/
    state.ex                     -- Association state struct
    negotiation.ex               -- Presentation context matching
    config.ex                    -- Config struct (timeouts, AE titles, max PDU)
  command.ex                     -- DIMSE command set encode/decode (group 0000, Implicit VR LE)
  command/
    fields.ex                    -- Command field constants (PS3.7 Annex E)
    status.ex                    -- DIMSE status codes (PS3.7 Annex C)
  message.ex                     -- DIMSE message assembly from P-DATA fragments
  listener.ex                    -- Ranch listener lifecycle
  connection_handler.ex          -- Ranch protocol callback → spawns Association
  handler.ex                     -- SCP behaviour (@callback for each DIMSE service)
  scp/
    echo.ex                      -- Built-in C-ECHO SCP (Verification SOP Class)
  scu.ex                         -- SCU client API (open, release, abort)
  scu/
    echo.ex                      -- C-ECHO SCU (verify connectivity)
  telemetry.ex                   -- Event definitions and span helpers
```

## Conventions

- Return `{:ok, result}` or `{:error, reason}` from all public functions
- PDU parsing uses Elixir binary pattern matching (direct translation of PS3.8 format tables)
- Encoding produces iodata (not flat binaries) for zero-copy TCP sends
- Command sets are always Implicit VR Little Endian (PS3.7 Section 6.3.1)
- `@spec` on all public functions
- `@moduledoc` and `@doc` on all public modules and functions
- Reference DICOM standard sections in docs (e.g., "PS3.8 Section 9.3")

## Code Style

- Run `mix format` before committing
- Prefer iodata over binary concatenation in encoding paths
- Use list accumulation + `Map.new/1` over incremental `Map.put` in parsing loops
- `@compile {:inline, ...}` for hot-path functions in PDU decoder/encoder

## Testing

- Property-based tests with StreamData for PDU encode/decode roundtrips
- Shared test helpers in `test/support/pdu_helpers.ex`
- Integration tests for C-ECHO SCP/SCU (when implemented)
- Interop tests against DCMTK/dcm4che (future)
- Maintain or improve coverage in the areas you touch

## DICOM Networking Domain

Key concepts for working with this codebase:

- **PDU** (Protocol Data Unit): 7 types on the wire, each with a 6-byte header
  (type + reserved + 4-byte big-endian length)
- **Association**: Stateful TCP connection between two DICOM AEs. Goes through
  Idle → Negotiating → Established → Releasing → Closed
- **Presentation Context**: Pairs an Abstract Syntax (SOP Class UID) with
  Transfer Syntaxes during association negotiation
- **DIMSE Command**: Application-layer message consisting of a command set
  (group 0000, always Implicit VR LE) + optional data set
- **P-DATA-TF**: PDU type that carries DIMSE messages, possibly fragmented
  across multiple PDUs when data exceeds max PDU length
- **SCP**: Server role (receives requests, sends responses)
- **SCU**: Client role (sends requests, receives responses)
- **AE Title**: 16-character identifier for a DICOM application endpoint

## Dependencies

- `dicom` — DICOM P10 parser/writer, used for command set encoding (Implicit VR LE),
  UID generation, transfer syntax registry, SOP class lookup
- `ranch` — Erlang TCP acceptor pool (powers Cowboy/Phoenix)
- `telemetry` — Elixir observability standard

## Security

- DIMSE has no built-in authentication — deploy behind firewalls or use TLS
- Validate all incoming PDU lengths against `max_pdu_length`
- Never execute content from DICOM data sets as code
- Do not log or expose PHI (Protected Health Information) in production
- See [SECURITY.md](SECURITY.md) for DIMSE-specific security considerations

## PR Guidelines

- Keep changes focused on a single concern
- Include tests for new functionality
- Maintain or improve coverage for the changed area
- Update `@doc` and `@moduledoc` for public API changes
