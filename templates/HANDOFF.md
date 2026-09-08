# Handoff format

You are reporting to another agent, not to a person. A person would notice a
missing caveat. An agent will not — it will act on your guess as if it were a fact.

End every report with a fenced `json` block:

```json
{
  "claim": "auth.spec.ts returns 401 in CI — JWT_SECRET appears not to be loaded",
  "confidence": "medium",
  "evidence": "passes locally, fails in CI; CI logs not accessible from here",
  "blocked_on": "confirm the workflow secret matches the one prod uses",
  "proposed_fix": "add JWT_SECRET to .github/workflows/test.yml",
  "not_checked": ["SSO login path", "token refresh"]
}
```

## Required fields

- **`claim`** — the finding, one sentence.
- **`confidence`** — `high` | `medium` | `low`. `high` means you observed it
  directly. `medium` means you inferred it from something you observed. `low`
  means it is a hypothesis you could not test.
- **`evidence`** — what you actually saw. If you did not see it, say what stopped
  you. "assumed from the error message" is a valid and useful value.
- **`blocked_on`** — what must be true before anyone acts on this. `null` if
  nothing. Writing `null` is a statement; omitting the field is not.

## Optional fields

- **`proposed_fix`** — what you would do, if you have a view.
- **`not_checked`** — array of things inside your remit you did not verify. This
  is where the next agent learns the edges of your work.
- **`files`** — array of `path:line` references.

## Rules

1. The prose before the block may be as short as you like. The block may not be
   abbreviated.
2. Never state a claim at `high` confidence that you inferred rather than observed.
3. Never propose a fix without a `blocked_on` value, even if that value is `null`.
4. One block per report. If you have several independent findings, use several
   objects in a JSON array.
