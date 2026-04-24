# Shipping to TestFlight

This doc is the solo-dev runbook for shipping a Harvest build to TestFlight, locally or from GitHub Actions.

## First-time prerequisites

All three are one-time setup. After this the loop is `fastlane beta` (local) or a workflow_dispatch click (CI).

### 1. App Store Connect app record

1. appstoreconnect.apple.com → **My Apps → + → New App**
2. Platforms: **iOS**, Primary Language: **English (U.S.)**
3. Bundle ID: `io.bitrat.harvest` (from dropdown)
4. Name: `Harvest`, SKU: `harvest-ios`, User Access: **Full Access**

### 2. App Store Connect API key

1. ASC → **Users and Access → Integrations → App Store Connect API → +**
2. Name: `Harvest CI`, Access: **Admin**
3. Generate → download the `.p8` immediately (one-chance download)
4. Note **Issuer ID** (top of page) and **Key ID** (per-key)
5. Install locally:
   ```sh
   mkdir -p ~/.fastlane/harvest
   mv ~/Downloads/AuthKey_*.p8 ~/.fastlane/harvest/asc_api_key.p8
   chmod 600 ~/.fastlane/harvest/asc_api_key.p8
   ```
6. Set in your shell (`~/.zshrc` or `~/.bashrc`):
   ```sh
   export APP_STORE_CONNECT_API_KEY_ID="XXXXXXXXXX"
   export APP_STORE_CONNECT_API_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
   ```

### 3. Match cert repo

1. github.com/new → **Private** → name: `harvest-ios-certs` (empty, no README)
2. Locally, export the match env vars:
   ```sh
   export MATCH_GIT_URL="git@github.com:<your-username>/harvest-ios-certs.git"
   export MATCH_PASSWORD="<pick-a-strong-passphrase-and-save-it-in-1password>"
   ```
3. Bootstrap the certs (this mints the distribution cert + App Store profiles and pushes them to the repo, encrypted):
   ```sh
   bundle install
   bundle exec fastlane match appstore
   ```
   On first run, match asks for `MATCH_PASSWORD` if the env var isn't set.

### 4. GitHub secrets (for CI uploads)

Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | How to compute |
|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID from step 2 |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID from step 2 |
| `APP_STORE_CONNECT_API_KEY_BASE64` | `base64 -i ~/.fastlane/harvest/asc_api_key.p8 \| pbcopy` |
| `MATCH_PASSWORD` | Same passphrase from step 3 |
| `MATCH_GIT_URL` | `https://github.com/<your-username>/harvest-ios-certs.git` (HTTPS for CI) |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `echo -n "<username>:<github-PAT-with-repo-scope>" \| base64` |

Generate the PAT at github.com/settings/tokens with `repo` scope.

## Local uploads

```sh
bundle exec fastlane beta
```

Prints the build number it's about to use, regenerates the Xcode project, fetches signing via match, archives Release, and uploads to TestFlight. Takes 5–10 min including ASC processing start.

## CI uploads

1. Navigate to **Actions → TestFlight** in the GitHub UI
2. Click **Run workflow** → pick `main` → **Run workflow**
3. Watch the run — ~15 min end to end

Same result as a local upload, no Mac needed on your end.

## Typical lifecycle tasks

**Bump the marketing version** (`0.1.0 → 0.2.0`): edit `CFBundleShortVersionString` in `project.yml` for both `Harvest` and `ShareExtension` targets. Commit. Next upload uses the new string.

**Rotate ASC API key**: repeat step 2, update the three GitHub secrets (`KEY_ID`, `ISSUER_ID`, `KEY_BASE64`) and the local file.

**Cert expiry (yearly)**: Apple's Distribution cert is valid one year. When it expires:
```sh
bundle exec fastlane match nuke distribution    # revokes the old cert + profiles
bundle exec fastlane match appstore             # re-mint everything
```
The `MATCH_PASSWORD` stays the same; the git repo keeps working.

**Add a new tester**: ASC → Harvest → **TestFlight** → Internal or External Testing → + → paste email. No build change needed.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `No profiles found matching 'match AppStore io.bitrat.harvest'` | Capability missing on the Dev portal App ID. Go to developer.apple.com → Identifiers → io.bitrat.harvest and enable App Groups / Associated Domains / Keychain Sharing. Then `fastlane match appstore` again. |
| `The app record does not exist on App Store Connect` | ASC app record missing — redo step 1 above. |
| `Authentication failed for 'https://github.com/...'` in CI | `MATCH_GIT_BASIC_AUTHORIZATION` wrong. Must be `base64("<user>:<PAT>")` with a literal colon. |
| `Unable to resolve dependency` during `bundle install` | Ruby version mismatch. Use `ruby-3.3` (matches CI). |
| CI build number stuck at 1 | First upload — `latest_testflight_build_number` returns 0, lane adds 1. Normal. |
