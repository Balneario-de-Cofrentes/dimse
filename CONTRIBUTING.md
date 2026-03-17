# Contributing to Dimse

Thank you for your interest in contributing. This guide covers the process
for submitting changes.

## Development Setup

### Prerequisites

- Elixir >= 1.16
- Erlang/OTP >= 26

### Getting Started

```bash
git clone https://github.com/Balneario-de-Cofrentes/dimse.git
cd dimse
mix deps.get
mix test
```

### Common Commands

```bash
mix test                         # Run all tests
mix test --cover                 # Run with coverage report
mix format                       # Format code
mix format --check-formatted     # Check formatting (CI)
mix docs                         # Generate documentation
```

## Submitting Changes

1. Fork the repository and create a branch from `master`
2. Make your changes
3. Ensure all tests pass: `mix test`
4. Ensure code is formatted: `mix format --check-formatted`
5. Ensure coverage does not regress materially in the areas you changed
6. Open a pull request against `master`

### Pull Request Guidelines

- Keep PRs focused on a single change
- Include tests for new functionality
- Update documentation for public API changes
- Follow existing code style and conventions

## Code Conventions

- All public functions return `{:ok, result}` or `{:error, reason}`
- Binary parsing uses Elixir pattern matching -- no external parsers
- PDU structs live in `Dimse.Pdu` with one struct per PDU type
- Use `@spec` on all public functions
- Use `@moduledoc` and `@doc` on all public modules and functions
- Reference specific DICOM standard sections in documentation (e.g., "PS3.8 Section 9.3")
- Prefer iodata over binary concatenation in encoding paths
- Use list accumulation + `Map.new/1` over incremental `Map.put` in parsing

## DICOM Networking Domain Notes

If you are new to DICOM networking, these concepts are essential:

- **DIMSE** -- DICOM Message Service Element (PS3.7): the application-level
  messaging protocol for DICOM networking
- **Upper Layer Protocol** (PS3.8): the transport protocol that sits on top of
  TCP and carries DIMSE messages
- **PDU** -- Protocol Data Unit: the fundamental unit of data on the wire
  (7 types: A-ASSOCIATE-RQ/AC/RJ, P-DATA-TF, A-RELEASE-RQ/RP, A-ABORT)
- **Association** -- a stateful connection between two DICOM applications,
  established via A-ASSOCIATE-RQ/AC negotiation
- **SCP** (Service Class Provider) -- the server side of a DICOM service
- **SCU** (Service Class User) -- the client side of a DICOM service
- **AE** (Application Entity) -- a named DICOM application endpoint, identified
  by a 16-character title
- **Presentation Context** -- the pairing of an Abstract Syntax (SOP Class) with
  one or more Transfer Syntaxes, negotiated during association setup
- **DIMSE-C** -- composite services: C-STORE, C-FIND, C-MOVE, C-GET, C-ECHO

The [DICOM standard](https://www.dicomstandard.org/current) is freely available.
Parts 7 and 8 are most relevant to this library.

## AI-Assisted Contributions

We welcome AI-assisted contributions under the following conditions:

1. **You are the author.** You are fully responsible for every line you submit,
   regardless of what tools produced it.

2. **Review your changes.** Read and understand all code before submitting.
   You must be able to explain your changes in your own words during review.

3. **Write in your own words.** PR descriptions, issue comments, and review
   responses should be your own writing, not raw AI output.

4. **Meet the same quality bar.** AI-assisted code must compile, pass all tests,
   maintain coverage, and follow project conventions.

See [AGENTS.md](AGENTS.md) for instructions that AI coding assistants can use
to work with this codebase.

## Reporting Issues

- Use GitHub Issues for bug reports and feature requests
- Include the Elixir and OTP versions you are using
- For PDU parsing issues, include a hex dump of the relevant PDU bytes

## Code of Conduct

This project follows a [Code of Conduct](CODE_OF_CONDUCT.md). By participating,
you are expected to uphold this code.

## License

By contributing, you agree that your contributions will be licensed under
the [MIT License](LICENSE).
