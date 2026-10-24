# Cross-Layer Thinking Guide

> Trace the data, not just the call.

---

## Why This Matters

Most expensive bugs live between layers, not inside them. Each layer is internally
consistent; the defect is in what one layer assumes about another.

Typical shapes:

- A field is optional in one layer and required in the next.
- A value is computed in two layers, and the two computations disagree.
- An error is swallowed at a boundary and surfaces as a wrong result rather than
  a failure.
- A payload is cast into a local shape at each consumer, so a schema change breaks
  the ones nobody remembered to update.

---

## When to Use This Guide

- [ ] The change touches three or more layers.
- [ ] A data format changes anywhere in the path.
- [ ] Several consumers read the same value.
- [ ] You are adding a field to something that crosses a boundary.
- [ ] You cannot decide which layer a piece of logic belongs to.

---

## Step 1 — Draw the Path

Write down where the value is produced, where it is transformed, and where it is
consumed. Include the places it is *not* used, if that surprised you while writing
the list.

---

## Step 2 — Name the Shape at Each Hop

For every boundary, answer:

- What is the field called here?
- Is it required or optional here?
- What is its type, exactly?
- What is the single source of truth for its meaning?

Two different names for the same thing is a rename waiting to be forgotten; two
different meanings for the same name is a bug that reads as correct code.

---

## Step 3 — Find the Consumers

Search for every reader before changing a producer.

```bash
grep -rn "field_or_event_name" .
```

The cost of this search is seconds. The cost of skipping it is a defect in the one
consumer you did not think of.

---

## Step 4 — Decide the Ownership of Each Rule

For every rule you find, ask which layer owns it. A rule enforced in two layers is
enforced in neither once they disagree.

---

## Step 5 — Check the Change Propagation

When adding a kind, a record format, a payload field or a config key, walk this list:

- [ ] Producer
- [ ] Every intermediate transformation
- [ ] Every consumer
- [ ] Validation and schema definitions
- [ ] Tests that assert the old shape
- [ ] Documentation that describes the old shape

---

## Anti-Patterns

### Casting at the Consumer

Each consumer declaring its own local type for a shared payload. It compiles, and
it means a schema change has as many blast radii as there are consumers.

### The Silent Boundary

A layer that converts a failure into a default value. The caller cannot distinguish
"absent" from "failed", so the wrong result looks like a valid one.

### Two Writers, One Field

Two layers both deriving a value. They agree today. The first change to either
reasoning makes them disagree, and nothing fails at the point of the change.

---

## Checklist

- [ ] Path drawn, producers and consumers listed
- [ ] One name per concept, one meaning per name
- [ ] Every consumer found by search, not by memory
- [ ] Ownership of each rule assigned to exactly one layer
- [ ] Errors at boundaries either propagated or deliberately converted, and said so
- [ ] Tests cover the boundary, not just each side
