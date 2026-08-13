# Bubbl

Bubbl keeps explicitly marked, short-lived secrets out of an agent's model context. The `bubl` executable seals a single-line secret into an encrypted, one-use bubble and later delivers it directly to a child process through stdin or one environment variable.

```text
Deploy with [@bubl sk-example-secret]
```

The Codex plugin blocks that raw prompt, replaces the marker with an opaque `[@bubl-ref …]`, and carries the sanitized request into the next accepted turn. The model receives only the capability and the exact safe command needed to consume it.

## CLI

```text
bubl seal
bubl run TOKEN --stdin -- PROGRAM [ARGS...]
bubl run TOKEN --env NAME -- PROGRAM [ARGS...]
bubl codex-hook
```

`bubl seal` reads the secret from stdin and prints only the capability. `bubl run` inherits the child's stdout and stderr and returns its exit status. Prefer `--stdin`; use `--env` only when the target program does not accept stdin.

Input secrets must be non-empty, single-line UTF-8 without NUL. In prompt markers, `\]` encodes `]` and `\\` encodes `\`. Every bubble expires after one hour and pops as soon as its child process starts successfully.

## Build and test

Rust 1.85 or newer is required.

```text
cargo build --release
cargo test
cargo clippy --all-targets --all-features -- -D warnings
```

The release workflow builds plugin archives for Windows x64, Linux x64 musl, macOS x64, and macOS arm64. Each archive contains the matching executable; no daemon, MCP server, PATH installation, or runtime download is required.

## Security boundary

Bubbl reduces accidental secret exposure in model context, normal CLI output, transcripts, and casual temporary-file inspection. It does not defend against a malicious same-user process or agent with arbitrary local code execution. Codex, the originating UI, and every configured prompt hook see the raw prompt before Bubbl can block it. A wrapped child can disclose its input, and environment variables may be observable to the child, descendants, or OS inspection tools.

Capabilities are bearer credentials. They remain useful until consumed or expired and may be persisted in Codex context. Bubbl stores authenticated ciphertext under the OS temporary directory, but does not promise secure deletion or OS-keychain protection.

Licensed under the MIT License.
