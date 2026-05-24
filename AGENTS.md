# AGENTS.md — Harvest iOS

Canonical agent guide for this repo. (Claude also loads this via `CLAUDE.md`.)

## What this is
iOS client for **Harvest**, a Pocket-replacement bookmarking tool. SwiftUI, min iOS 17.
Targets: `Harvest` (app), `ShareExtension` (posts URLs to the API), `HarvestTests`.
The Rails backend and Chrome extension live in separate repos.

## XcodeGen-driven (don't hand-edit the project)
`Harvest.xcodeproj` is **gitignored** and generated from `project.yml`. Edit
`project.yml`, then `xcodegen generate` (`brew install xcodegen`). The pbxproj is
never committed — that's deliberate (avoids merge conflicts).

## Toolchain (read first)
Full Xcode is at `/Applications/Xcode.app`, but `xcode-select -p` may still point at
CommandLineTools. Either prefix Xcode commands with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or make it permanent:
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

## Environments
| Build | Scheme | Config | Bundle id | Base URL |
|-------|--------|--------|-----------|----------|
| Prod | `Harvest` | Debug / Release | `io.bitrat.harvest` | `https://harvest.bitrat.io` |
| Dev ("TEST") | `Harvest Dev` | Debug-Dev / Release-Dev | `io.bitrat.harvest.dev` | `https://harvest.bitrat.test` (local Rails) |

"**TEST build**" = the **Dev** build. `harvest.bitrat.test` uses a private CA the
simulator must be told to trust — see the simulator skill below.

## Build / run / test
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild -scheme Harvest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' test
```
- `.githooks/pre-push` runs `xcodegen generate && xcodebuild test` before every push
  (enable once: `git config core.hooksPath .githooks`). `--no-verify` skips it on
  known-red WIP branches.
- CI (`.github/workflows/ci.yml`) runs on push to `main` only — a post-merge safety
  net, not a per-branch gate (macOS runners bill at 10× on private repos).
- TestFlight: `bundle exec fastlane beta`, or the TestFlight GitHub Action. Runbooks:
  `docs/release.md`, `docs/testflight-external-testers.md`.

## MCP tools — prefer these for Xcode/simulator work
- **`xcodebuildmcp`** (declared in the repo's `.mcp.json`; needs `npm i -g
  xcodebuildmcp@latest`): build/run/test, simulator + device control, and **UI
  automation** — `tap` by accessibility label, `type-text`, `snapshot-ui` (view tree
  with coordinates), `screenshot`, etc. Prefer it for building, launching, and driving
  the app in the simulator.
- **`xcode`** (optional, per-machine user scope; Apple's `xcrun mcpbridge`): access to
  the **open** Xcode project/IDE. Enable via Xcode → Settings → Intelligence, open the
  project in Xcode, then `claude mcp add`.

Both need the full Xcode toolchain (their config carries `DEVELOPER_DIR`). If their
tools aren't present in a session, restart — MCP servers load at startup.

## Running the Dev build in the simulator / dev login
See `.claude/skills/harvest-dev-simulator/` — simulator CA trust for
`harvest.bitrat.test`, build/launch, and the magic-link / `letter_opener` login flow.
With `xcodebuildmcp` connected, prefer its UI-automation tools over the manual fallback
documented in that skill.

## Conventions
- **Conventional Commits** (`feat:`, `fix:`, `chore:`, `docs:`; scopes like `feat(dev):`).
- Branch → PR; keep commits atomic. Never commit secrets (PATs, keys, `Config/Secrets.xcconfig`).
- `project.yml` is the source of truth for project structure.

## Key files
`project.yml`, `Config/*.xcconfig`, `fastlane/Fastfile`, `.github/workflows/`,
`.githooks/pre-push`, `README.md`, `docs/release.md`.
