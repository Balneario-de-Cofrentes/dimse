# Dimse -- AI Development Guide

## Overview

Pure Elixir DICOM DIMSE networking library. 3 runtime deps (dicom, ranch, telemetry).
MIT licensed. See [AGENTS.md](AGENTS.md) for agent-specific instructions.

## Build Commands

```bash
mix deps.get                     # Install deps
mix compile                      # Compile
mix test                         # Run tests
mix test --cover                 # Run with HTML coverage report
mix format                       # Format code
mix format --check-formatted     # Check formatting (CI uses this)
mix docs                         # Generate documentation
```

## Architecture

```
lib/dimse/
  dimse.ex                -- Public API (start_listener, connect, echo, store, find, move, get)
  pdu.ex                  -- PDU type structs (7 PDU types + sub-items)
  pdu/
    decoder.ex            -- Binary → struct (PS3.8 Section 9.3)
    encoder.ex            -- Struct → iodata
  association.ex          -- GenServer: Upper Layer state machine
  association/
    state.ex              -- State struct (phase, socket, contexts, buffer)
    negotiation.ex        -- Presentation context matching
    config.ex             -- Config (timeouts, AE titles, max PDU)
  command.ex              -- Command set encode/decode (group 0000, Implicit VR LE)
  command/
    fields.ex             -- Command field constants (0x0001 = C-STORE-RQ, etc.)
    status.ex             -- DIMSE status codes (success, pending, failure)
  message.ex              -- DIMSE message assembly from P-DATA fragments
  listener.ex             -- Ranch listener lifecycle
  connection_handler.ex   -- Ranch protocol callback
  handler.ex              -- SCP behaviour with callbacks
  scp/echo.ex             -- Built-in C-ECHO SCP
  scu.ex                  -- SCU client API
  scu/echo.ex             -- C-ECHO SCU
  telemetry.ex            -- Event definitions + span helpers
```

## Conventions

- All public functions return `{:ok, result}` or `{:error, reason}`
- PDU parsing uses Elixir binary pattern matching
- Encoding produces iodata, not flat binaries
- Command sets are always Implicit VR Little Endian (PS3.7 Section 6.3.1)
- `@spec` on all public functions
- `@compile {:inline, ...}` on hot-path functions
- Property-based tests with StreamData for PDU encode/decode roundtrips

## Key DICOM Networking Concepts

- **PDU**: 7 types, common header = type(1) + reserved(1) + length(4, big-endian)
- **Association**: Stateful TCP connection: Idle → Negotiating → Established → Releasing → Closed
- **Presentation Context**: Abstract Syntax (SOP Class) + Transfer Syntaxes
- **DIMSE Command**: Command set (group 0000, always Implicit VR LE) + optional data set
- **P-DATA-TF**: Carries DIMSE messages, may span multiple PDUs (fragmentation)
- **SCP/SCU**: Server/client roles
- **AE Title**: 16-char identifier for DICOM endpoints

## Performance Notes

- PDU decoder uses binary pattern matching (direct PS3.8 format table translation)
- Encoder uses iodata pipeline with single `IO.iodata_to_binary` only at TCP send
- GenServer-per-association: ~2-4 KB per process, negligible at 200 concurrent
- Ranch acceptor pool for TCP (same as Cowboy/Phoenix)
