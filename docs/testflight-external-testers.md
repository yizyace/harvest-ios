# Adding External TestFlight Testers

Runbook for inviting external (public) beta testers to Harvest Reader. Written to be self-contained for a fresh agent with no prior context. For build/upload mechanics and API key setup, see [`release.md`](release.md).

## Context

Harvest Reader is the iOS client for Harvest, a read-it-later service. It lives in this repo; the backend is in a separate Rails monolith at `/Users/andrew3/work/makaira.feat-3` (or wherever it's checked out). The iOS app ships via TestFlight.

**Already in place** (don't re-do; verify via the referenced locations if unsure):

- Apple Developer Team ID `37A42LB22L`, account `yizyace@gmail.com`.
- App IDs + App Group registered at developer.apple.com → Identifiers:
  - `io.bitrat.harvest` (App Groups, Associated Domains enabled; App Group = `group.io.bitrat.harvest`)
  - `io.bitrat.harvest.ShareExtension` (App Groups only)
- App Store Connect app record: "Harvest Reader", Apple ID `6763221159`, SKU `harvest-ios`.
- ASC API Key `Harvest CI` (Admin role). Key ID `WK26QY2H55`, Issuer ID `dcc503ad-2376-4a0d-97bf-5ae489e0e662`. The `.p8` lives at `~/.fastlane/harvest/asc_api_key.p8` (chmod 600). Values also in `fastlane/.env` (gitignored).
- Signing via `fastlane match` in a separate private repo `github.com/yizyace/harvest-ios-certs`. Match passphrase is saved in 1Password (and in `fastlane/.env` locally as `MATCH_PASSWORD`).
- Fastlane `beta` lane archives Release + uploads to TestFlight. GHA workflow at `.github/workflows/testflight.yml` does the same from CI (manual trigger).
- Internal Testing group "Internal Testers" exists with `yizyace@gmail.com` and `vze3qx35@gmail.com`.

**Not in place yet** (these are prerequisites the first External submission blocks on):

- Privacy policy page at `https://harvest.bitrat.io/privacy` — must return 200, publicly reachable. Content spec'd in `/tmp/harvest-privacy-policy-handoff.md` (if still around) or reconstruct from Apple Guideline 5.1.1(i). Backend team's branch `chore/privacy-policy-page` handles this server-side.
- App Store Connect "Test Information" fields (Beta App Description, Feedback Email, Contact Info, Privacy Policy URL, Review Notes with demo token).
- Any Tag-based or automated CI trigger. Current workflow is manual `workflow_dispatch`.

## Internal vs External — when to use which

| | Internal | External |
|---|---|---|
| **Who** | ASC team users (must be added in Users and Access first) | Public email addresses (no ASC membership) |
| **Beta App Review** | None — instant access after build processes | Required on first build of a new marketing version (24–48h); subsequent builds on same `CFBundleShortVersionString` often skip review |
| **Cap** | 100 testers | 10,000 testers |
| **Distribution speed** | Minutes (after processing) | Hours–days |
| **Use when** | Dev team dogfooding, rapid iteration | Real beta users, invite-only launches |

For both, the **same uploaded build** goes to both groups — they're independent tester buckets on top of one `.ipa`.

## Before your first External submission (one-time)

### 1. Privacy policy URL must exist

Verify `https://harvest.bitrat.io/privacy` returns 200:
```sh
curl -sS -o /dev/null -w "%{http_code}\n" https://harvest.bitrat.io/privacy
```
Must be **200**, no auth, no geo-fence, indexable by bots.

If 404/500, coordinate with backend — the page has to ship before you can submit external.

### 2. Fill ASC Test Information

ASC → Harvest Reader → **TestFlight** tab → **Test Information** (left sidebar).

Required for external review to pass:

- **Beta App Description** — short pitch. Example: "Harvest is a read-it-later service. Save links from Safari's share sheet, read them later in the in-app feed."
- **Feedback Email** — monitored inbox. Use `hello@bitrat.io` or whatever's live. Apple reviewers may send probe emails here; a bounce is a rejection.
- **Contact Information** — your name, email, phone. Goes to Apple, not to testers.
- **Privacy Policy URL** — `https://harvest.bitrat.io/privacy`.
- **Demo Account / Sign-In Info + Review Notes** — critical for magic-link auth:

  The app's sign-in requires either (a) clicking a magic-link from an email Apple reviewers can't receive, or (b) pasting a bearer token. Put this in Review Notes:

  > To sign in during review, tap "Or paste a token" on the sign-in screen and paste the bearer token below. This bypasses email verification.
  >
  > Token: `<mint-a-fresh-token-at-submit-time>`

  Mint the token against **prod** (harvest.bitrat.io), not dev:
  ```ruby
  # On the prod Rails console (not makaira.feat-3 dev)
  user = Harvest::User.find_by(email: "<your-harvest-prod-account>")
  session = Harvest::Session.create_for(user: user)
  puts session.token
  ```
  Token doesn't need to be long-lived — Apple review takes ~48h max. But don't rotate it during review or Apple will bounce.

Click **Save**. These fields persist across builds; you only fill them once per major rewrite.

### 3. Upload a build if you haven't already

If TestFlight has no build for the current `CFBundleShortVersionString`:
```sh
bundle exec fastlane beta
```
Wait for ASC processing (~10–30 min); build must show "Ready to Submit" status before you can submit to review.

## Adding External testers (the recurring part)

Once the one-time setup above is done, inviting new external testers is ~2 minutes.

### Option A: ASC web UI

1. appstoreconnect.apple.com → **Harvest Reader** → **TestFlight** tab.
2. **External Testing** section in left sidebar → click **+** (New Group) if none exists; otherwise click the existing group.
   - Suggested name: "Public Beta" or "Beta Testers".
3. **Add Testers** (top-right button):
   - Paste emails, one per line or comma-separated.
   - First + last name per tester is optional but nice to have.
4. **Builds** tab (within the group) → **Add to Group** → pick the latest build that's "Ready to Submit".
5. If this is the **first** build of the current `CFBundleShortVersionString` being shown externally, Apple prompts you to submit to **Beta App Review**. Confirm.
6. Wait:
   - First review on a new version: **24–48h** typical.
   - Subsequent builds on same version: often auto-approve in minutes.
7. Once approved, Apple emails testers with a "Start Testing" link. They install the TestFlight app on their iPhone and accept.

### Option B: fastlane `pilot` (scriptable)

```sh
bundle exec fastlane run pilot \
  distribute:true \
  groups:"Public Beta" \
  app_identifier:io.bitrat.harvest \
  app_version:0.1.0 \
  build_number:<N> \
  changelog:"What's new in this build" \
  api_key_path:$HOME/.fastlane/harvest/asc_api_key.json
```

Requires a JSON-formatted API key file (different from the `.p8`). Skip this until you want repeatability; the web UI is fine for one-off invites.

## Common Beta App Review rejection reasons (and fixes)

| Symptom | Cause | Fix |
|---|---|---|
| "Missing Privacy Policy" | Policy URL 404 or times out | Verify URL returns 200 publicly. If backend hasn't deployed, wait. |
| "Could not sign in" | Magic-link flow, reviewer has no email access | Paste-token instructions missing from Review Notes. Re-submit with correct notes + fresh token. |
| "Missing Marketing Icon" | 1024×1024 AppIcon missing from .ipa | Verify `Harvest/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` exists + Contents.json references it. |
| "Invalid bundle" iPad orientations | `UISupportedInterfaceOrientations` missing one of Portrait/UpsideDown/LandscapeLeft/LandscapeRight | All 4 must be present for TARGETED_DEVICE_FAMILY=1,2. Declared in `project.yml`. |
| 409 on upload: encryption questionnaire | `ITSAppUsesNonExemptEncryption` not declared | Already `false` in `project.yml`. If regressed, re-add. |
| Review stuck >72h | Rare — usually a reviewer-queue issue, not your bundle | Email Apple via ASC → **Resolution Center** if it drifts past 72h. |

## Where credentials live

- `~/.fastlane/harvest/asc_api_key.p8` — ASC API key file (600 perms).
- `fastlane/.env` (gitignored) — all env vars: `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `MATCH_GIT_URL`, `MATCH_PASSWORD`.
- 1Password (or equivalent) — same values, authoritative backup. If `.env` is lost, restore from here.
- GitHub Actions Secrets (for CI) — `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_BASE64`, `MATCH_PASSWORD`, `MATCH_GIT_URL`, `MATCH_GIT_BASIC_AUTHORIZATION`. See `release.md` §4.

## If this is your first time and nothing's set up

You probably want [`release.md`](release.md) first, not this doc. This one assumes the pipeline and keys already work end-to-end.

## Appendix: relevant bundle ID map

- Main app: `io.bitrat.harvest`
- Share Extension: `io.bitrat.harvest.ShareExtension`
- Shared App Group: `group.io.bitrat.harvest`
- Shared Keychain access group: `$(AppIdentifierPrefix)io.bitrat.harvest`

All of the above are configured in `project.yml` (xcodegen source of truth) and `Config/*.xcconfig`.
