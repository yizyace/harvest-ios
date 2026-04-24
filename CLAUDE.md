# Claude agent notes

Instructions that apply to every session in this repo. Read these before acting.

## Time-sensitive: GitHub PAT rotation

The CI TestFlight workflow clones the private `harvest-ios-certs` repo via the
`MATCH_GIT_BASIC_AUTHORIZATION` secret, which embeds a classic GitHub PAT.

- **PAT created:** 2026-04-23
- **90-day expiry:** **2026-07-22**
- **Warn-window start (T-14):** **2026-07-08**

On every session start, compare today's date against those dates:

- If today ≥ **2026-07-08** and ≤ **2026-07-22**: surface a one-line warning to
  the user in your first message — *"PAT rotation: MATCH_GIT_BASIC_AUTHORIZATION
  expires on 2026-07-22. See CLAUDE.md for rotation steps."*
- If today > **2026-07-22**: surface the warning **every session, every day**
  until the user confirms rotation. After expiry, the CI `TestFlight` workflow
  will fail at `match` with `fatal: Authentication failed for
  'https://github.com/...'` on the clone step.

### Rotation steps

1. `github.com/settings/tokens` → regenerate the existing token
   `harvest-ios-ci-match` (or create a new one, classic, `repo` scope, 90 days).
2. Recompute the secret: `echo -n "yizyace:<new-PAT>" | base64 | pbcopy`
3. Update the secret at
   `github.com/yizyace/harvest-ios/settings/environments/production` →
   `MATCH_GIT_BASIC_AUTHORIZATION`.
4. Update this file: set **PAT created** to today and advance the two expiry
   dates by 90 and 76 days respectively. Commit on a PR titled
   `chore: PAT rotation reminder refresh`.
5. Trigger the TestFlight workflow once to confirm the new PAT works.
