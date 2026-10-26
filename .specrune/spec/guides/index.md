# Thinking Guides

> Questions worth asking before writing the code.

---

## Why Thinking Guides

Most defects and most accumulated complexity come from something nobody thought
about, not from something nobody knew how to do. These guides are checklists of
the questions that get skipped under time pressure.

---

## Available Guides

| Guide | Purpose | When to Use |
|-------|---------|-------------|
| [Code Reuse Thinking Guide](./code-reuse-thinking-guide.md) | Spot a repeated pattern before it becomes a fifth implementation | When what you are about to write feels familiar |
| [Cross-Layer Thinking Guide](./cross-layer-thinking-guide.md) | Trace data across layer boundaries | When a change touches three or more layers |
| [UI Feedback Loop Guide](./ui-feedback-loop-guide.md) | Verify the target before adjusting UI; verify asset content before adopting it | When adjusting UI by verbal description, or adopting images without seeing them |
| [Gesture Semantics Guide](./gesture-semantics-guide.md) | List the state matrix before wiring a gesture to an effect | When a requirement says "this gesture/action = this effect" |

---

## Quick Reference: Thinking Triggers

### Cross-Layer

- [ ] Does the change touch three or more layers?
- [ ] Does the data format change between layers?
- [ ] Do several consumers need the same value?
- [ ] Are you unsure which layer a piece of logic belongs to?
- [ ] Are you adding an event kind, a record format, a payload field, or a config key?

→ Read the [Cross-Layer Thinking Guide](./cross-layer-thinking-guide.md)

### Code Reuse

- [ ] Does something like this already exist? (Search before writing.)
- [ ] Is this the second or third place the same rule appears?
- [ ] Are you adding a field that has to be added in several places?
- [ ] Are you changing a constant or a config default?
- [ ] Are you creating a new helper? ← Search first.

→ Read the [Code Reuse Thinking Guide](./code-reuse-thinking-guide.md)

### Gesture Semantics

- [ ] The requirement says "gesture X = effect Y" — did you enumerate the state
      combinations (keyboard up/down, panel forced/matched) × expected effect
      BEFORE coding? An unfilled matrix cell = ambiguity to ask about, not to guess.
- [ ] Are you classifying the device/form-factor to dispatch behavior? Prefer an
      existing state signal over inventing a form-factor check.

→ Read the [Gesture Semantics Guide](./gesture-semantics-guide.md)

### Reviewing a Change

- [ ] Is the finding verified against the code, or inferred from the diff?
- [ ] Is the flagged data actually untrusted, or internal and already validated?
- [ ] Does a comment say the flagged behaviour is intentional?
- [ ] Does the test still pass if the feature it covers is deleted?

### UI Adjustment

- [ ] Have you screenshotted and located the target element before editing?
- [ ] A UI change had no visible effect — did you re-verify the target file instead of tuning parameters again?
- [ ] Adopting an image/icon you cannot see — did you pixel-diff or ASCII-render it first?
- [ ] A width/margin complaint — did you exhaustively grep ALL width constraints (maxWidth constants, contentMargins, container caps) before changing any value?
- [ ] The user reports "fine in layout A, wrong in layout B" — did you treat that as a conditional constraint and grep for constants between the two layout widths?
- [ ] A symptom report ("some paragraphs wrap early") — did the user point at the exact paragraph and breakpoint BEFORE you concluded anything? Self-invented samples prove nothing about the user's symptom.
- [ ] Removing temporary diagnostics — did you grep the `AA-DIAG:` markers and rebuild after cleanup?

→ Read the [UI Feedback Loop Guide](./ui-feedback-loop-guide.md)

---

## Pre-Modification Rule

> **Before changing any value, search for it first.**

```bash
grep -rn "the_value_you_are_about_to_change" .
```

This one habit prevents most "forgot to update the other place" defects.

---

## How to Use This Directory

1. **Before coding** — skim the guide that matches the change you are about to make.
2. **While coding** — when something feels repetitive, stop and read the reuse guide.
3. **After a bug** — add the question that would have caught it to the relevant guide.

---

## Contributing

Found a "didn't think of that" moment? Add it to the matching guide, as a question
someone can answer, not as a story.
