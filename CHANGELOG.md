# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Project scaffold with module stubs and comprehensive PRD
- PDU type structs for all 7 DICOM Upper Layer PDU types (PS3.8 Section 9.3)
- DIMSE command field constants (PS3.7 Annex E)
- DIMSE status code constants and classification (PS3.7 Annex C)
- Association state machine struct (PS3.8 Section 9.2)
- Handler behaviour for SCP service class implementations
- Built-in C-ECHO SCP handler
- Telemetry event definitions and span helpers
- CI workflow with Elixir 1.16/1.17/1.18 matrix

[Unreleased]: https://github.com/Balneario-de-Cofrentes/dimse/commits/master
