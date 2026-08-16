## What this changes

Explain the user/system outcome in plain English. Do not use only an epic or slice ID.

## Why

What problem does this solve, and why is this the right change now?

## How it works

Describe the design in ordinary language first. Add type-, file-, or symbol-level detail afterwards where useful.

## What I should test

Give concrete manual steps the owner can perform in the real app. Write `Not required` only when the change is genuinely non-user-facing.

1.
2.
3.

## Risks and limits

State known compromises, remaining edge cases, consciously deferred work, and anything that could still surprise a user or maintainer.

## Verification

- [ ] Relevant package/unit/integration tests pass
- [ ] Formatter passes
- [ ] Strict lint passes
- [ ] App builds in the required configuration
- [ ] Required UI or Release-build dogfood path executed
- [ ] Performance evidence recorded where the change affects a hot path
- [ ] Documentation and issue state reconciled with what actually shipped

Commands/evidence:

```text
<commands and concise results>
```

## Technical detail

Optional deeper implementation notes, important types, migration detail, or reviewer guidance.

## Traceability

Epic/issue:
Architecture document:
Implementation slice(s):
