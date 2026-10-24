# Code Reuse Thinking Guide

> The second occurrence is the one that decides.

---

## Why This Matters

Duplication is not a style problem; it is a correctness problem with a delay. Two
copies agree on the day they are written and diverge on the day one of them is
fixed. Nothing fails at the moment of divergence — the failure arrives later, from
the copy nobody changed.

The inverse mistake is just as expensive: extracting an abstraction after the first
use produces a helper shaped like one call site, which the second call site has to
bend around.

---

## The Rule

- **First occurrence** — write it where it belongs. Do not extract yet.
- **Second occurrence** — look at both. Are they the same rule, or the same shape?
- **Third occurrence** — extract, and name it after the rule, not after the code.

"Same shape" duplicates can stay duplicated; "same rule" duplicates cannot. Two
functions that both loop over a list are not sharing a rule. Two functions that both
compute the same cut-off date are.

---

## Before Writing Anything New

```bash
grep -rn "the_thing_you_are_about_to_write" .
```

Search by meaning, not by name — the existing implementation is usually called
something else.

---

## Places Duplication Hides

- A constant repeated as a literal in several files.
- A default value written both in the config loader and in the consumer.
- The same validation performed in a form and again in the handler.
- The same derivation of a status, computed independently in two components.
- The same string used as a key, an id, and a display label.
- The same path, route, or file name assembled in more than one place.

---

## Where to Put the Shared Version

| Kind of thing | Home |
|---|---|
| A rule about the domain | The domain layer, next to the data it constrains |
| A format or a wire contract | The boundary module that owns serialization |
| A path or file name | The module that owns the directory layout |
| A UI pattern | The component directory, not a generic `utils/` |

A shared helper in `utils/` has no owner and no reason to exist, which is why
`utils/` grows and nobody can say what may be deleted from it.

---

## Naming the Extraction

Name it after the rule it enforces, and say the rule in a comment. A function named
after the operation it performs (`processData`) cannot be reused, because nobody
can tell whether their case is included.

---

## Checklist

- [ ] Searched the codebase before writing
- [ ] Decided explicitly: same rule, or same shape
- [ ] Shared version has an owner and a home
- [ ] The rule is stated, not implied by the implementation
- [ ] Every existing copy replaced, or a note left saying why one was not
