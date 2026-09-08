You investigated a failing test. These are your raw observations, in full:

1. tests/auth.spec.ts "rejects expired token" returns 401 in CI, expected 200.
2. The same test passes locally.
3. .github/workflows/test.yml sets NODE_ENV, TZ, CI and DATABASE_URL for the test
   job, but has no JWT_SECRET entry.
4. You ran `gh run view --log` and got "log expired" — retention is 0 days, so you
   are working from the workflow file and the local repro alone.
5. infra/README.md documents the June key rotation, notes in passing that staging
   was not updated at the time, and does not say whether CI reads the staging
   value or a separate one of its own.
6. You spent the rest of your time on the workflow file rather than on the SSO
   login path or the token refresh flow.

Write your report for the agent that will act on it.
