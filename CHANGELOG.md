# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.1] - 2026-03-18

### Added

- `bench/` directory with five Benchee suites: PDU encode/decode, command encode/decode, message fragmentation/assembly, persistent-connection throughput, and end-to-end round-trip benchmarks
- `benchee` dev dependency for the benchmark suites

### Changed

- `Dimse.connect/3` and `Dimse.Scu.open/3` now enforce a single timeout budget across socket connect plus association negotiation
- PDU encoder keeps iodata throughout — no intermediate `IO.iodata_to_binary` flatten; sizes computed via `:erlang.iolist_size/1`
- PDU encoder fast-path for single-PDV `P-DATA-TF` (the common case) avoids `Enum.map` list allocation
- PDU decoder accumulates presentation contexts with `[h | t]` + `Enum.reverse/1` instead of `++ [item]` (O(n) vs O(n²))
- Command encoder uses compile-time pattern-match dispatch for VR lookup instead of `Map.get/3` at runtime
- Message fragmentation rewritten as a tail-recursive accumulator — no intermediate chunk lists, direct struct construction
- `Association` TCP receive handler skips binary concatenation when the buffer is already empty (common case: one PDU per segment)

### Fixed

- SCP examples now declare `supported_abstract_syntaxes/0` for the non-Verification services they advertise
- TLS failure-path tests now require synchronous `connect/3` failure instead of tolerating the old async-connect behavior

## [0.6.0] - 2026-03-18

### Added

- TLS / DICOM Secure Transport (PS3.15 Annex B) support for both SCP and SCU
- `start_listener/1` accepts `:tls` option to use `ranch_ssl` transport
- `connect/3` accepts `:tls` option to connect via `:ssl` instead of `:gen_tcp`
- Full mutual TLS (mTLS) support: SCP can require client certificates
- All standard `:ssl` options (`:certfile`, `:keyfile`, `:cacertfile`, `:verify`, `:fail_if_no_peer_cert`) passed through to OTP
- `:ssl` and `:public_key` added to `extra_applications` (OTP stdlib, zero new deps)
- 7 TLS integration tests: C-ECHO over TLS, C-STORE over TLS, mutual TLS, DIMSE-N over TLS, mixed TCP+TLS listeners, untrusted CA rejection, missing client cert rejection
- Dynamic test certificate generation using OTP `:public_key` (no cert files in repo)

### Changed

- `handle_info/2` now uses guards (`when proto in [:tcp, :ssl]`) instead of atom-specific clauses for socket messages
- `send_pdu/2`, `reactivate_socket/1`, and `close_socket/1` handle `:ssl` transport alongside `:gen_tcp` and Ranch transports
- Implementation version bumped to `DIMSE_0.6.0`

### Fixed

- `Dimse.connect/3` and `Dimse.Scu.open/3` now wait for association negotiation to succeed or fail before returning
- `Dimse.n_create/4` now returns the created SOP Instance UID alongside status and response data
- `N-CREATE` requests without an Attribute List now set `CommandDataSetType` correctly

## [0.5.1] - 2026-03-18

### Fixed

- `N-GET` now correctly encodes and decodes multi-valued Attribute Identifier Lists instead of crashing on a documented list input
- `N-CREATE` SCP handlers can now return the created SOP Instance UID for inclusion in the response command
- DIMSE-N SCU helpers now return explicit error tuples for DIMSE failure statuses instead of reporting them as `{:ok, status, data}`

## [0.5.0] - 2026-03-18

### Added

- All 6 DIMSE-N services (PS3.7 Chapter 10): N-EVENT-REPORT, N-GET, N-SET, N-ACTION, N-CREATE, N-DELETE
- SCU modules: `Dimse.Scu.NGet`, `Dimse.Scu.NSet`, `Dimse.Scu.NAction`, `Dimse.Scu.NCreate`, `Dimse.Scu.NDelete`, `Dimse.Scu.NEventReport`
- Public API: `Dimse.n_get/4`, `Dimse.n_set/5`, `Dimse.n_action/6`, `Dimse.n_create/4`, `Dimse.n_delete/4`, `Dimse.n_event_report/6`
- 6 optional handler callbacks: `handle_n_get/2`, `handle_n_set/3`, `handle_n_action/3`, `handle_n_create/3`, `handle_n_delete/2`, `handle_n_event_report/3`
- SCP dispatch for all 6 DIMSE-N command fields with `function_exported?/3` fallback (0x0112 No Such SOP Class)
- Correct Requested vs Affected SOP Class/Instance UID handling per PS3.7 Table 10.1
- DIMSE-N response builder with data set support (CommandDataSetType 0x0000 when data present)
- Extra response tags: AffectedSOPInstanceUID, EventTypeID, ActionTypeID echoed in N-*-RSP
- 35 SCU unit tests (build_command_set for all 6 services)
- 9 integration tests: N-GET, N-SET, N-ACTION, N-CREATE, N-DELETE, N-EVENT-REPORT round trips, error handling, mixed DIMSE-C+N, Storage Commitment flow

### Changed

- `send_dimse_request/4` now checks both AffectedSOPClassUID (0000,0002) and RequestedSOPClassUID (0000,0003) for context lookup
- `request_on_negotiated_context?/2` validates both Affected and Requested SOP Class UIDs
- Response builder dynamically sets CommandDataSetType based on response data presence (was hardcoded 0x0101)

## [0.4.1] - 2026-03-18

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

[Unreleased]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.6.1...HEAD
[0.6.1]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.3.0...v0.4.1
[0.3.0]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Balneario-de-Cofrentes/dimse/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Balneario-de-Cofrentes/dimse/releases/tag/v0.1.0
