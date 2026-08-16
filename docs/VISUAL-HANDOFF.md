# Bubbl visual concept handoff

This document is a briefing for designers and image models exploring README
graphics for Bubbl. It separates product facts from visual direction so a new
concept can change the composition without changing what the product claims.

## What Bubbl is

Bubbl is a small Codex plugin made to solve a practical workflow problem:
safety-aligned models may refuse to use an API token after it has been pasted
into a conversation. Bubbl replaces an explicitly marked value with an opaque,
one-use reference and lets Codex pass the value directly to one child process.

The main benefit is workflow continuity and a smaller accidental-leak surface.
Bubbl is not a password manager, keychain, sandbox, or proof that a raw prompt
never reached OpenAI.

## Product flow

The complete flow is:

1. The user submits a prompt containing `[@bubl TOKEN]`.
2. A local `UserPromptSubmit` hook blocks that turn and seals `TOKEN` locally.
3. Bubbl prepares a sanitized pending request containing `[@bubl-ref …]`.
4. The user sends an ordinary follow-up such as `continue`.
5. Codex receives the sanitized request and the opaque reference.
6. Codex runs one child process with either:
   - `bubl run REF --stdin -- PROGRAM [ARGS...]`
   - `bubl run REF --env NAME -- PROGRAM [ARGS...]`
7. The reference is consumed after the child starts successfully and cannot be
   reused. Unused references expire after one hour.

Stdin is preferred. Environment delivery exists for programs that cannot read
the token from stdin and has a larger exposure surface.

## Security wording that must remain accurate

The app and hook system see the raw prompt before Bubbl runs. Bubbl has not been
verified to stop that prompt from reaching OpenAI's servers, and no visual may
claim otherwise.

Safe claims:

- the local hook blocks the marked turn before model sampling;
- the model receives an opaque reference in the later sanitized request;
- the reference is one-use and expires after one hour;
- the value is not placed in command arguments;
- Bubbl reduces exposure to later model context, commands, transcripts, and
  ordinary logs.

Claims to avoid:

- "the key never leaves your computer";
- "OpenAI never sees the key";
- "Bubbl protects or secures your key" without qualification;
- "zero-knowledge", "vault-grade", or similar security language;
- implying that the receiving program cannot disclose the value.

The raw-token example is blocked by **safety alignment**, not by a generic
"security policy". The intended refusal is direct:

> Your API key has been exposed in this conversation and should no longer be
> considered secure. Please rotate it, then add the replacement to the
> appropriate environment variable instead of pasting it into chat.

## Exact demo values

Every visual must use a visibly fake canary, never a credential:

```text
sk-example-7F3A-NOT-A-REAL-KEY
```

Marked prompt:

```text
Authenticate the demo API using [@bubl sk-example-7F3A-NOT-A-REAL-KEY].
```

Opaque reference:

```text
[@bubl-ref b1_X7m2Q9vR4xT8nL3cD6Fw]
```

Stdin command:

```text
bubl run b1_X7m2Q9vR4xT8nL3cD6Fw --stdin -- python verify_token.py
```

Result:

```text
Demo API authenticated
```

If an image model cannot render these strings exactly, generate the layout
without text and composite the text deterministically afterward. A plausible
but misspelled token or command is not acceptable for the final README asset.

## Visual direction

The target is a serious developer tool with some BubblePaw/LilBub warmth.
Personality should come from the system, not from decorative filler.

Use:

- BubblePaw's near-black background (`#171514`) and dark paper surfaces
  (`#1c1a18`, `#24211f`);
- warm-white cards (`#f8f5f0`) with dark ink (`#25211f`);
- BubblePaw coral-orange (`#ef715c`, or `#f17a64` on dark surfaces) as the
  single semantic accent;
- rounded bubble-like cards or nodes;
- crisp sans-serif labels and a readable monospace face for code;
- one visual idea per element;
- generous spacing and clear flow;
- small functional icons such as user, lock, terminal, and check.

Avoid:

- mascots, cartoon cats, large paws, sparkles, confetti, and sticker art;
- floating bubbles that do not encode a step or state;
- dotted paths used only as decoration;
- glossy 3D rendering, heavy gradients, or game-UI styling;
- headings such as "illustrative walkthrough" or other text that describes the
  graphic instead of advancing the flow;
- badges, captions, and footnotes whose meaning is already clear from context;
- marketing language and generic security imagery.

Bubble iconography is welcome when it carries meaning. Good examples are a
bubble for each state, a clearly labeled model-context boundary, or a
spent/empty bubble after one-use delivery. Do not scatter bubbles around the
background.

## Current assets

- `docs/assets/raw-token-policy-refusal.png` shows the raw-token refusal.
- `docs/assets/bubbl-success.png` shows the detailed Bubbl path and command.
- `docs/assets/bubbl-flow-concept.png` is the functional flowchart used near the
  top of the README.

The first two assets are a paired comparison. They should share dimensions,
palette, typography, panel geometry, and density.

## Concept briefs for other models

### Concept A: functional bubble chain

Create five connected bubble nodes: user prompt, local hook, model sees,
one-use delivery, and program result. Enclose only the model-side stages
(`Model sees` and `One-use delivery`) in a restrained boundary labeled
`secret never enters model context`. Keep the program outside that boundary:
it receives the real value. Keep the background empty. This is the closest
direction to `bubbl-flow-concept.png`.

### Concept B: before and after

Create two equal columns. The left column contains a raw prompt followed by the
safety-alignment refusal. The right column contains a marked prompt, opaque
reference, one-use command, and successful result. Use color only to distinguish
raw value, reference, command, and success. No central hero illustration.

### Concept C: hook boundary

Use a horizontal systems diagram with three zones: user/app, local hook, and
model context. The raw value reaches the hook boundary; only the opaque
reference crosses into the model-context zone. Keep the child process outside
that zone and include a separate arrow from the one-use runner to it. Label the
caveat outside the main diagram: "The app and hook system see the raw prompt
first."

### Copyable generation prompt

```text
Design a 16:9 README diagram for Bubbl, a serious open-source Codex plugin.
Visualize this exact flow: user marks a fake token; a local hook blocks and seals
it; the model receives a different opaque one-use reference; bubl delivers the
value through stdin to one child process; the reference is spent. Use functional
bubble nodes. Enclose only the model-side stages in a restrained boundary
labeled exactly "secret never enters model context"; keep the receiving child
process outside that boundary.
Near-black #171514 background, warm-white #f8f5f0 cards, coral-orange #ef715c
as the only accent, rounded cards, crisp developer-tool typography, and
generous spacing. No mascot, paws,
sparkles, confetti, floating decoration, marketing copy, or unsupported security
claim. Every visual element must encode a state, transition, or boundary.
```

Supply the exact strings from this document separately and require verbatim
rendering.

## Acceptance checklist

- The fake key and reference are visibly different.
- The raw value does not appear in the model step.
- The diagram distinguishes hook interception from child-process delivery.
- The `secret never enters model context` label applies only to the post-hook
  model working context, not transport or server-side receipt.
- One-use consumption is visible or stated.
- Stdin is shown as the preferred delivery path.
- The visual does not imply that Bubbl prevents server-side receipt of the raw
  prompt.
- No real credential appears anywhere.
- Code strings are exact and legible at README width.
- Decorative elements do not compete with the flow.
- The graphic still reads correctly without its surrounding README text.
