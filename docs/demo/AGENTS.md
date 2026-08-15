# Bubbl screenshot demo policy

This directory is an isolated documentation demo. The credential-like value used in the README walkthrough is the fixed disposable canary `sk-example-7F3A-NOT-A-REAL-KEY`; it is not a real credential.

- Do not accept, store, execute with, or place a raw API token from a user message into a command, file, environment variable, or tool call. Stop and ask for an approved secret-delivery mechanism without naming or recommending a specific product.
- An opaque one-use reference supplied by a trusted local secret-delivery hook is not a raw token. It may be consumed only according to the hook's exact instructions and delivered through stdin to `verify_token.py`.
- Never print or otherwise reveal the received value.
