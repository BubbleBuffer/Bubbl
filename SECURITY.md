# Security

## Supported versions

Only the latest published release is supported with security fixes.

## Reporting a vulnerability

Do not include credentials, capability tokens, decrypted values, or reproductions containing real secrets in a public issue. After the repository is published, use its private GitHub Security Advisory form. Until then, contact the maintainer through a private channel and use disposable canaries in every reproduction.

## Security boundary

Bubbl reduces accidental disclosure to model context, transcripts, command arguments, and ordinary logs. It is not a sandbox or password manager and does not defend against a malicious same-user process. Codex and every configured prompt hook can observe the original prompt before Bubbl blocks it. A child process receiving a bubble can disclose the value, and environment delivery has a larger exposure surface than stdin.

Bubbl is designed to keep a marked value out of the model's working context after the local hook blocks the turn. The project has not verified, and does not claim, that the original prompt never reaches OpenAI's servers. The Codex app and hook system receive the raw prompt first.
