# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-03-18

### Added

- C-MOVE SCU (`Dimse.Scu.Move`) — retrieve instances to a destination AE via C-STORE sub-operations
- C-GET SCU (`Dimse.Scu.Get`) — retrieve instances on the same association via interleaved C-STORE sub-ops
- `Dimse.move/4` public API with query level convenience atoms (`:patient`, `:study`) and `dest_ae` option
- `Dimse.get/4` public API with query level convenience atoms (`:patient`, `:study`)
- `Association.get_request/4` for C-GET multi-response with interleaved C-STORE handling
- `resolve_ae/1` optional handler callback for C-MOVE destination AE resolution
- Sub-operation state machine in `Association.State` for tracking C-GET/C-MOVE progress
- SCP dispatch for C-GET-RQ (0x0010) and C-MOVE-RQ (0x0021) with asynchronous sub-operation processing
- SCU `get_mode` for auto-accepting C-STORE sub-operations during C-GET retrieval
- Sub-operation count tracking (remaining/completed/failed/warning) in C-GET/C-MOVE responses
- C-GET integration tests (basic retrieval, empty, error, mixed echo+get)
- C-MOVE integration tests (basic retrieval, empty, error, resolve_ae failure, mixed echo+move)
- Unit tests for `Dimse.Scu.Move` and `Dimse.Scu.Get` (SOP class mapping, command set building)

### Changed

- **Breaking**: `handle_move/3` now returns `{:ok, [{sop_class_uid, sop_instance_uid, data}]}` (was `{:ok, [String.t()]}`)
- **Breaking**: `handle_get/3` now returns `{:ok, [{sop_class_uid, sop_instance_uid, data}]}` (was `{:ok, [binary()]}`)
- `MoveOriginatorMessageID` tag (0000,1031) added to command VR map for correct US encoding

### Fixed

- SCU requests now fail closed when no negotiated presentation context matches the requested SOP Class
- `Dimse.find/4` now returns an explicit cancellation error when a peer ends the operation with status `0xFE00`

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

[Unreleased]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Balneario-de-Cofrentes/dimse/releases/tag/v0.1.0
