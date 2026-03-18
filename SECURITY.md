# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it
responsibly.

**Email:** david@balneariodecofrentes.es

Please include:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge receipt within 48 hours and aim to provide a fix or
mitigation within 7 days for critical issues.

## Security Considerations

### DIMSE-Specific Risks

- **Unauthenticated associations**: DICOM DIMSE does not include authentication
  in the base protocol. AE title checking is the only built-in mechanism and is
  trivially spoofable. Always deploy behind a network firewall or VPN. Consider
  TLS wrapping (DICOM PS3.15 Annex B) for transport security.

- **PDU injection**: Malformed PDUs could exploit parsing bugs. The decoder uses
  strict binary pattern matching with explicit length bounds to mitigate buffer
  overflows. Property-based testing with StreamData validates parser robustness.

- **AE title spoofing**: Any client can claim any AE title. Do not rely on AE
  titles for access control in security-sensitive environments.

- **Association flooding (DoS)**: An attacker could exhaust server resources by
  opening many associations. Mitigations:
  - `max_associations` limits concurrent connections via DynamicSupervisor
  - ARTIM timer (PS3.8 Section 9.1.4) closes idle or stalled associations
  - Ranch acceptor pool limits queued connections

- **Memory exhaustion**: Large DICOM objects in transit consume memory per
  association. Mitigations:
  - Configurable `max_pdu_length` (default 16 KB)
  - TCP backpressure via passive socket mode
  - Per-association memory monitoring via `:erlang.memory/0`

- **Patient data (PHI)**: DICOM data sets transmitted via DIMSE contain
  Protected Health Information. This library does not provide encryption —
  use TLS or a VPN for transport security. Users are responsible for HIPAA/GDPR
  compliance.

### TLS / DICOM Secure Transport (v0.6.0+)

v0.6.0 added native TLS support via OTP `:ssl` and Ranch SSL (PS3.15 Annex B).
TLS mitigates plaintext DIMSE traffic exposure and, with mutual TLS (mTLS),
client AE title spoofing. See the README for usage examples.

- `start_listener/1` accepts `:tls` option for `ranch_ssl` transport
- `connect/3` accepts `:tls` option to connect via `:ssl`
- mTLS: SCP can require client certificates via `:verify` / `:fail_if_no_peer_cert`

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 0.6.x   | Yes                |
| 0.5.x   | Yes                |
| < 0.5   | No                 |
