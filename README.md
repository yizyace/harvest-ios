# Harvest iOS

iOS client for [Harvest](https://harvest.bitrat.io), a Pocket-replacement
bookmarking tool. Third of three clients, after the Rails backend and the
Chrome extension.

## Requirements

- Xcode 16+ (iOS 17 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Getting started

```
xcodegen generate
git config core.hooksPath .githooks
open Harvest.xcodeproj
```

The `.xcodeproj` is gitignored; regenerate it from `project.yml` whenever you
pull or change targets. The `core.hooksPath` line wires up the pre-push hook
described below.

## Tests

Local runs are the primary gate. The committed `.githooks/pre-push` hook runs
`xcodegen generate && xcodebuild test` before every push; activate it once
with the `core.hooksPath` line above. Skip with `git push --no-verify` for
known-red WIP branches.

CI (GitHub Actions, `.github/workflows/ci.yml`) runs on push to `main` only —
i.e., after a merge — as a safety net, not a per-branch gate. macOS runners
are billed at 10× on private repos, so this stays cheap.

### Running tests manually

```
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme Harvest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  test
```

The `DEVELOPER_DIR` prefix is only needed on machines where `xcode-select -p`
still points at CommandLineTools. To make it permanent:
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

## Project shape

- **`Harvest/`** — main iOS app. SwiftUI lifecycle, min iOS 17.
- **`ShareExtension/`** — Share Extension target that posts URLs to
  `/api/v1/bookmarks` using the session token from the shared keychain group.
- **`HarvestTests/`** — XCTest unit tests.
- **`Config/*.xcconfig`** — per-configuration build settings, including
  `API_BASE_URL`.
- **`project.yml`** — XcodeGen manifest that defines all of the above.

### Bundle ID + signing

- Bundle ID: `io.bitrat.harvest`
- Share Extension bundle ID: `io.bitrat.harvest.ShareExtension`
- Development Team: `37A42LB22L`
- Shared keychain access group: `$(AppIdentifierPrefix)io.bitrat.harvest`
- App Group: `group.io.bitrat.harvest`
- Associated Domains: `applinks:harvest.bitrat.io`

### Environment / base URL

Debug and Release both point at `https://harvest.bitrat.io`. The dev monolith
at `harvest.bitrat.test` uses a local-only CA that the simulator won't trust,
so routing debug builds at dev requires per-device CA setup. To override
locally, create a gitignored `Config/Secrets.xcconfig` with
`API_BASE_URL = https:/$()/your-host` and `#include "Secrets.xcconfig"` at the
bottom of `Config/Debug.xcconfig`.

(Note: xcconfig treats `//` as a comment, so URLs use `/$()/` to break up the
double-slash.)

## Why XcodeGen?

The generated `.xcodeproj/project.pbxproj` is a large, line-noise file that
produces painful merge conflicts on multi-contributor repos. XcodeGen keeps
the source of truth in `project.yml` (diffable YAML) and regenerates the
project on demand. The `.xcodeproj/` directory is gitignored.

## Why no SwiftData?

v1 caching is "nice to have" per the handoff, and adding SwiftData introduces
a schema-migration surface for a feature we don't need. List/detail views
fetch on appear. Revisit if list responsiveness becomes a problem.

## Universal Links status

Universal Links need a server-side Apple App Site Association file. Until the
Rails monolith ships that (separate repo), the app uses a paste-token
fallback on the sign-in screen — users open the verify link in Safari, copy
the token from the HTML page, and paste it into the app. See the handoff doc
for the AASA JSON payload.
