# Bubbl

**One-use API token delivery for Codex.**

When a coding task needs an API token, pasting it directly into the conversation is awkward. Depending on the agent policy, the model may refuse to use it; otherwise the token can remain visible in model context and transcripts. Bubbl replaces an explicitly marked value with an opaque, one-use reference and supplies the original value directly to the program that needs it.

Both examples use a clearly fake API key. They illustrate the intended flow; exact model wording varies.

### Raw API key

![An agent declining a raw disposable API token](docs/assets/raw-token-policy-refusal.png)

The key is now part of the conversation. A safety-aligned agent treats it as exposed, refuses to use it, and asks you to rotate it.

### With Bubbl

![Bubbl intercepting a fake API key, replacing it with a different opaque reference, and delivering it to a mock API](docs/assets/bubbl-success.png)

Codex receives an opaque reference. The bundled `bubl` executable delivers the value directly to the mock API through stdin, and the reference cannot be reused.

## How it works

```text
You type [@bubl TOKEN]
        ↓
The local hook blocks the turn and seals TOKEN
        ↓
Codex receives [@bubl-ref …] with the sanitized request
        ↓
bubl supplies TOKEN once to the target program
```

Bubbl does not scan ordinary text or guess what might be secret. Only explicit `[@bubl …]` markers are intercepted. Values are encrypted into the operating system's temporary directory, expire after one hour, and are consumed when the wrapped child process starts successfully. There is no command that reveals a stored value.

`bubl run` prefers stdin:

```text
bubl run TOKEN --stdin -- PROGRAM [ARGS...]
```

For programs that cannot read a token from stdin, Bubbl can set one named environment variable:

```text
bubl run TOKEN --env NAME -- PROGRAM [ARGS...]
```

Environment delivery has a larger exposure surface and should only be used when necessary.

## Install and try it

Install Bubbl only from the public [`BubbleBuffer/Bubbl` GitHub releases](https://github.com/BubbleBuffer/Bubbl/releases). The bootstrap downloads the correct self-contained marketplace for Windows x64, Linux x64, macOS x64, or macOS arm64. Before changing your Codex configuration, it verifies the immutable release, GitHub artifact attestations, exact signing workflow and tag, SHA-256 checksum, release commit, package topology, and plugin version.

The installer requires an authenticated [GitHub CLI](https://cli.github.com/) with release-verification support and a current Codex CLI. It does not clone the repository, build code, accept an alternate repository, or place `bubl` on `PATH`.

Windows PowerShell:

```powershell
gh release download --repo BubbleBuffer/Bubbl --pattern install.ps1 --output install.ps1
.\install.ps1
```

Linux or macOS:

```sh
gh release download --repo BubbleBuffer/Bubbl --pattern install.sh --output install.sh
chmod +x install.sh
./install.sh
```

Pass `-Version 1.0.2` on Windows or `--version 1.0.2` on Linux and macOS to pin an exact stable version. By default, the latest stable release is installed. The marketplace is kept at `%LOCALAPPDATA%\Bubbl\marketplace` on Windows or `${XDG_DATA_HOME:-$HOME/.local/share}/bubbl/marketplace` elsewhere; upgrades are staged and the prior copy is restored if Codex rejects the new plugin.

After installation, open `/hooks`, inspect and trust the Bubbl `UserPromptSubmit` command, and then start a new task so Codex loads the plugin.

Test the installation only with a disposable canary:

```text
Use this value through stdin: [@bubl sk-example-7F3A-NOT-A-REAL-KEY]
```

A working hook blocks that submission before model sampling. Send an ordinary follow-up such as `continue`; Codex receives the sanitized pending request containing `[@bubl-ref …]`, not the marked value.

Prompt values must be non-empty, single-line UTF-8 without NUL. Inside a marker, `\]` represents `]` and `\\` represents `\`.

## Security reality

> [!IMPORTANT]
> Bubbl is designed to keep the marked value out of the model's working context after its local hook blocks the turn. It has not been verified—and Bubbl does not claim—that the original prompt never reaches OpenAI's servers. The Codex app and hook system see the raw prompt first.

Bubbl reduces accidental disclosure to model context, command arguments, transcripts, and ordinary logs. It is not a password manager, sandbox, operating-system keychain, or defense against a malicious same-user process. The program receiving a bubble can disclose its input, and an opaque reference is itself a bearer capability until it is consumed or expires.

See [SECURITY.md](SECURITY.md) for the complete boundary and vulnerability-reporting guidance.

## Development

Rust 1.85 or newer is required.

```text
cargo fmt --all -- --check
cargo test --locked --all-targets --all-features
cargo clippy --locked --all-targets --all-features -- -D warnings
```

Local source builds are for contributors, not an installation channel. Published installers accept only assets from the official repository's attested, immutable releases. Every archive also includes `BUILD-INFO.json`, the complete plugin, and its local Codex marketplace declaration.

See [CHANGELOG.md](CHANGELOG.md) for release notes and [RELEASING.md](RELEASING.md) for the release checklist.

Licensed under the MIT License.
