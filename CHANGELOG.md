# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-03-18

### Added

- C-FIND SCU (`Dimse.Scu.Find`) — query DICOM data sets from remote SCPs
- `Dimse.find/4` public API with query level convenience atoms (`:patient`, `:study`, `:worklist`)
- `Dimse.cancel/2` for C-CANCEL-RQ (PS3.7 §9.3.2.3)
- Multi-response handling in Association for Pending + Success response sequences
- `Association.find_request/4` for multi-response DIMSE commands
- Query SOP Class UID mapping (`Dimse.Scu.Find.sop_class_uid/1`)
- C-FIND integration tests (basic, empty, many results, error, mixed operations, cancel)
- Late response tolerance — SCU ignores responses after operation completes

### Changed

- SCP C-CANCEL-RQ handling — no longer sends erroneous response to C-CANCEL

## [0.2.0] - 2026-03-18

### Added

- C-STORE SCU (`Dimse.Scu.Store`) — send DICOM instances to remote SCPs
- `Dimse.store/5` public API with priority and move originator support
- Command-level telemetry events (`[:dimse, :command_start]`, `[:dimse, :command_stop]`)
- `AffectedSOPInstanceUID` echo-back in C-STORE-RSP (PS3.7 Table 9.1-1)
- Property-based tests using StreamData for PDU encode/decode roundtrips
- `@type t()` specs on all PDU structs (fixes `mix docs` warnings)
- StreamData generators in test helpers for all PDU types
- C-STORE integration tests (basic, multiple, large data set fragmentation, mixed echo+store)

## [0.1.0] - 2025-12-15

### Added

- PDU type structs for all 7 DICOM Upper Layer PDU types (PS3.8 Section 9.3)
- PDU encoder (struct → iodata) and decoder (binary → struct)
- DIMSE command set encode/decode (Implicit VR Little Endian, group 0000)
- DIMSE command field constants (PS3.7 Annex E)
- DIMSE status code constants and classification (PS3.7 Annex C)
- Association GenServer with 5-phase state machine (PS3.8 Section 9.2)
- ARTIM timer for connection timeout compliance
- Presentation context negotiation (abstract syntax + transfer syntax matching)
- Max PDU length negotiation with automatic message fragmentation
- Handler behaviour (`Dimse.Handler`) for SCP service class implementations
- Built-in C-ECHO SCP and SCU
- SCU client API (`Dimse.Scu.open/3`, release, abort)
- Ranch TCP acceptor integration
- Telemetry event definitions for association lifecycle and PDU I/O
- CI workflow with Elixir 1.16/1.17/1.18 matrix

[Unreleased]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Balneario-de-Cofrentes/dimse/releases/tag/v0.1.0
