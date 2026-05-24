---
name: harvest-dev-simulator
description: Use when running the harvest-ios Dev/TEST build in the iOS Simulator, making it reach the local harvest.bitrat.test server, signing into the dev app (magic link / verify token), or scripting taps/typing in the Simulator. Covers simulator CA trust and reliable UI automation from a headless agent.
---

# Running & driving the Harvest Dev build in the iOS Simulator

## Overview

"**TEST build**" = the **Dev** build: scheme `Harvest Dev`, config `Debug-Dev`,
bundle `io.bitrat.harvest.dev`, which points `HARVEST_BASE_URL` at
`https://harvest.bitrat.test` (the local Rails server). There is no separate
"Test" environment. The project uses **XcodeGen** — `Harvest.xcodeproj` is
gitignored and regenerated.

Two things make this hard, and both are solved below: (1) the simulator must be
taught to trust the local server's private CA, and (2) driving the SwiftUI UI
from a headless agent needs the right input channels (most obvious ones silently
fail).

## When to use

- "Run / launch the dev (or TEST) build in the simulator"
- "Make the simulator reach harvest.bitrat.test" / TLS or "session expired" issues
- "Log into the dev app" / magic link / paste verify token
- Any time you must tap or type in the Simulator programmatically

## Order of operations (do it in THIS order)

1. `export DEVELOPER_DIR=…`, pick + boot an iPhone (iOS 17+) sim, `open -a Simulator`.
2. `xcodegen generate` → build `Harvest Dev` → `simctl install`.
3. **Trust the CA** (§2) while the sim is booted.
4. **Launch** the app (after trust, so its first request succeeds).
5. Drive the UI / log in (§3, §4).

Cross-cutting facts that prevent wasted reboots:
- **Full Keyboard Access is OFF by default — keep it off.** Do NOT enable it
  (it breaks keystroke text entry). No reboot is needed in the normal path.
- **The added CA trust persists across sim reboots** and app reinstalls — add it
  once; you never need to re-add it on the same device.
- Any reboot (or the FKA fix in §3) **kills the app** → `simctl launch` it again.
- Each step: act, then **screenshot and Read it** before the next step.

## 1. Build & launch (no sudo needed)

Full Xcode is installed at `/Applications/Xcode.app`, but `xcode-select` may
point at CommandLineTools. **Use `DEVELOPER_DIR` instead of `sudo xcode-select`:**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=$(xcrun simctl list devices available | grep -m1 "iPhone 17 Pro" | grep -oE '[0-9A-F-]{36}')
[ -z "$UDID" ] && echo "no iPhone 17 Pro sim — pick any available iPhone (iOS 17+) or 'simctl create' one"
xcrun simctl boot "$UDID" 2>/dev/null || true   # harmless if already booted
open -a Simulator; xcrun simctl bootstatus "$UDID"

cd /Users/andrew1/work/harvest-ios
xcodegen generate
xcodebuild -project Harvest.xcodeproj -scheme "Harvest Dev" -configuration Debug-Dev \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath /tmp/harvest-dd build
APP=$(find /tmp/harvest-dd/Build/Products -maxdepth 3 -name "*.app" -not -path "*/PlugIns/*" | head -1)
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" io.bitrat.harvest.dev
```

## 2. Make the simulator trust harvest.bitrat.test (CRITICAL)

DNS already works (the sim shares the Mac's network; `harvest.bitrat.test` →
`127.0.0.1` via `/etc/resolver/test` → the Mac's loopback where Rails listens).
The only gap is **TLS trust**: the server cert is signed by a private
**"dd-ferryman Local CA"** that the Mac trusts but a fresh simulator does not.

There are **multiple** "dd-ferryman Local CA" roots in the System keychain — do
NOT pick one by common name. Take the exact root the **server presents** and add
it to the booted simulator:

```bash
echo | openssl s_client -connect harvest.bitrat.test:443 -servername harvest.bitrat.test -showcerts 2>/dev/null \
  | awk '/-----BEGIN CERTIFICATE-----/{i++} i==2{print} /-----END CERTIFICATE-----/{if(i==2) exit}' > /tmp/harvest-root.pem
xcrun simctl keychain "$UDID" add-root-cert /tmp/harvest-root.pem   # sim must be booted
```

The leaf cert is iOS-policy compliant (has a SAN, ~397-day validity), so once
the root is trusted, `URLSession` works with **no Info.plist / ATS changes and no
code edits**.

> **FALSE ORACLE — do not be fooled:** `curl` *inside* the sim
> (`xcrun simctl spawn <UDID> curl https://harvest.bitrat.test`) uses LibreSSL's
> CA-bundle file, NOT the keychain/SecTrust the app's `URLSession` uses. It will
> report `self signed certificate in certificate chain` even when the app trusts
> the cert perfectly. **Verify via the app**, not sim-curl: trigger a request in
> the app (e.g. send a magic link), then read the log retrospectively (this
> command terminates — don't use `log stream`, which hangs):
> `xcrun simctl spawn "$UDID" log show --last 2m --predicate 'process == "Harvest" OR process == "trustd"' | grep -iE "verify result|TLS Trust result|harvest.bitrat"`
> → success shows `Setting verify result to true` / `TLS Trust result 0` and the
> request completing to `https://harvest.bitrat.test/...`.

## 3. Driving the Simulator UI from a headless agent

The obvious channels **silently fail** — avoid them:

- `osascript "click at {x,y}"` → only AX-presses a container *group*, never a
  real tap on SwiftUI content.
- The Simulator's accessibility tree (`entire contents` / `AXPress`) → **flaky**;
  returns 0 / 82 / 151 elements call-to-call and degrades over a session. Don't
  build on it.

Use these instead:

### Typing into text fields — keystroke (keep Full Keyboard Access OFF)

FKA is **OFF by default — keep it that way; do NOT enable it.** With FKA ON,
keystrokes are silently swallowed (the field shows focus but text never enters).
Only if a prior step enabled FKA, disable it and reboot once to apply:

```bash
xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility FullKeyboardAccessEnabled -bool false
xcrun simctl shutdown "$UDID"; xcrun simctl boot "$UDID"; open -a Simulator; xcrun simctl bootstatus "$UDID"
# reboot kills the app → simctl launch it again
```

With FKA off, `Tab` cycles **text fields** (not buttons) and `Return` submits a
field that has `.onSubmit`:

```bash
osascript <<'EOF'
tell application "Simulator" to activate
delay 0.5
tell application "System Events"
  key code 48            -- Tab → focus 1st text field (Tab again → 2nd, etc.)
  delay 0.4
  keystroke "test@example.com"
  delay 0.4
  key code 36            -- Return → triggers .onSubmit (e.g. Send magic link)
end tell
EOF
```

### Tapping buttons — real CGEvent click (this works)

A genuine mouse event via the bundled `simclick.swift` works. (Earlier failures
were stale window coordinates, not permissions.) Use `tapnative.sh`, which takes
**native screenshot pixels** and maps them to screen points using the *current*
window geometry (re-fetched every call — the window moves on reboot/`open`):

```bash
zsh .claude/skills/harvest-dev-simulator/tapnative.sh 300 1490   # tap control at native px (300,1490)
```

Mapping (for reference / other devices): screenshot is native px at @3x (iPhone
17 Pro = 1206×2622 → 402×874 pt). With Simulator window `(wx,wy,ww,wh)`:
`z=(wh-28)/874; ox=wx+(ww-402*z)/2; oy=wy+28; screen=(ox+nx/3*z, oy+ny/3*z)`.

Starting native-px coords for the dev **sign-in screen** (iPhone 17 Pro) —
**always screenshot-verify; Y shifts ~+40px once the "Magic link sent" footer
appears**:

| Control | native (x, y) |
|---------|---------------|
| Email field | ~(600, 704) |
| "Send magic link" button | ~(300, 860) |
| "Paste verify token" field | ~(600, 1230) → ~(600, 1270) after footer |
| "Sign in with token" button | ~(300, 1450) → ~(300, 1490) after footer |

Tip: text fields are reachable by `Tab` (no coords needed); you only need coords
for the **buttons**.

### Always verify with a screenshot

After every action: `xcrun simctl io "$UDID" screenshot /tmp/s.png` then Read it.
Read coordinates off the screenshot in native px (multiply the displayed-image
coords by the factor the Read tool reports) and feed them to `tapnative.sh`.

## 4. Dev login flow (magic link → verify token)

`letter_opener` (the dev mail catcher) is at
**`https://harvest.bitrat.test/letter_opener`** — NOT `/privacy` (that path is
the real Privacy Policy page).

1. Type email into the first field → `Return` (or tap "Send magic link"). The
   footer should read "Magic link sent to …".
2. Pull the **newest** email and extract the token (tokens expire in minutes):
   ```bash
   newest=$(curl -sS https://harvest.bitrat.test/letter_opener \
     | grep -oiE '/letter_opener/[0-9]+_[0-9]+_[0-9a-f]+/rich' \
     | sed -E 's#/letter_opener/##; s#/rich##' | sort -t_ -k1,1nr | head -1)
   curl -sS "https://harvest.bitrat.test/letter_opener/$newest/rich" \
     | grep -oiE 'auth/verify\?token=[A-Za-z0-9]+' | head -1 | sed -E 's#.*token=##'
   ```
3. `Tab Tab` to focus the "Paste verify token" field, `keystroke` the token,
   then **CGEvent-tap** "Sign in with token" (it is a button — not Tab-reachable).
4. Success = the root view switches to the bookmark list ("No bookmarks yet").
   Don't pre-open the verify URL in curl — that can consume the single-use token;
   let the app do the verify.

## Quick reference

| Need | Command / fact |
|------|----------------|
| Toolchain w/o sudo | `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` |
| Generate project | `xcodegen generate` (Harvest.xcodeproj is gitignored) |
| Build dev | `xcodebuild ... -scheme "Harvest Dev" -configuration Debug-Dev ...` |
| Trust local CA | extract server-presented root → `simctl keychain <UDID> add-root-cert` |
| Type text | FKA **off** → `activate` + `Tab` (key 48) + `keystroke` + `Return` (key 36) |
| Tap a button | `tapnative.sh <native_x> <native_y>` (real CGEvent click) |
| Dev inbox | `https://harvest.bitrat.test/letter_opener` |
| Verify a request worked | app logs (`trustd`/boringssl), NOT sim-curl |

## Common mistakes (each cost real time)

| Trap | Reality |
|------|---------|
| `sudo xcode-select` to fix toolchain | Just `export DEVELOPER_DIR=...`; full Xcode is already installed. |
| Trusting `curl` inside the sim | It uses LibreSSL's CA bundle, not the keychain. False negative. Verify via the app. |
| Adding any "dd-ferryman Local CA" by name | Multiple exist; only the **server-presented** root validates the chain. |
| `osascript click at` / AX tree for taps | Don't work / flaky. Use a real CGEvent click (`simclick.swift`). |
| Enabling Full Keyboard Access to reach buttons | FKA breaks keystroke text entry. Keep FKA OFF; tap buttons with CGEvent. |
| Reusing computed tap coordinates after a reboot | The Simulator window moves; re-fetch geometry each tap (`tapnative.sh` does). |
| Stale verify token "session expired" | Tokens expire in minutes; regenerate and use immediately. |
