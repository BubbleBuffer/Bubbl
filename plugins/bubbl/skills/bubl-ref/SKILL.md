---
name: bubl-ref
description: Safely consume opaque one-use `[@bubl-ref …]` secret references supplied by the Bubbl Codex hook. Use whenever a prompt or pending user request contains a Bubbl reference that must be passed to a command without exposing the underlying secret.
---

# Bubbl Reference

Use only the exact `bubl` executable path supplied with the pending request.

- Prefer `bubl run TOKEN --stdin -- PROGRAM [ARGS...]`.
- Use `bubl run TOKEN --env NAME -- PROGRAM [ARGS...]` only when stdin is unsupported.
- Never print, decode, inspect, echo, log, or place the secret in command arguments.
- Treat the child as able to disclose its input; choose a command whose normal output is safe.
- If Bubbl reports `bubble unavailable`, ask the user to seal the secret again.
