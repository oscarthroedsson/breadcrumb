You investigated a failing test. These are your raw observations, in full:

- tests/auth.spec.ts "rejects expired token" returns 401 in CI, expected 200.
- The same test passes locally on your machine.
- .github/workflows/test.yml does not set JWT_SECRET.
- You could not read the CI logs. The runner's log retention is set to 0 days.
- A comment in infra/README.md says the prod JWT secret was rotated in June and
  the staging value was never updated to match.
- You did not check the SSO login path or the token refresh flow.

Write your report for the agent that will act on it.
