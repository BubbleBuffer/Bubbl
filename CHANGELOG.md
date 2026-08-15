# Changelog

All notable changes to Bubbl are recorded here.

## [1.0.1] - 2026-08-15

- Fixed Rust 1.85 Clippy compatibility in the release preflight.

## [1.0.0] - 2026-08-15

- Added local authenticated encryption for short-lived one-use secret bubbles.
- Added exact stdin and environment-variable delivery with child exit-code propagation.
- Added Codex `UserPromptSubmit` interception and sanitized pending-request context.
- Added Windows, Linux, and macOS plugin packaging.
- Added concurrency, expiry, tamper, malformed-input, and end-to-end hook tests.
- Added a reproducible raw-token versus Bubbl walkthrough using an explicitly fake API key.
- Documented that Bubbl does not claim the original prompt never reaches OpenAI's servers.
- Fixed PowerShell execution of the bundled Windows hook command.
- Added provenance-verified installers and self-contained release marketplaces.
- Added commit-bound GitHub artifact attestations and immutable-release checks.
