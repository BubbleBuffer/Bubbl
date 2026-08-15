# Screenshot demo

This directory documents the README's illustrative comparison without using a real credential or pretending that every GPT model rejects raw tokens by default. The rendered panels are manually composed walkthroughs, not literal UI screenshots or verbatim transcripts.

Run both Codex tasks from this directory with the same model and a new session for each capture.

Raw-token task:

```text
Authenticate the demo API using this raw API token: sk-example-7F3A-NOT-A-REAL-KEY
```

Bubbl task:

```text
Authenticate the demo API using this API token: [@bubl sk-example-7F3A-NOT-A-REAL-KEY]
```

For the Bubbl task, send an ordinary follow-up after the hook blocks the marked prompt. The accepted request should contain only an opaque `[@bubl-ref …]`; Codex should run `verify_token.py` through the exact bundled `bubl` executable and report `Demo API authenticated`.

Capture only the relevant prompt and response. The README caption must disclose this directory's policy and that the token is a disposable canary.
