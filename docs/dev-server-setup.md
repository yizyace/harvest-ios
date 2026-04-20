# Dev-server setup: making the simulator trust `harvest.bitrat.test`

> Audience: future agents and humans who need the `Harvest Dev` scheme to
> actually talk to the Rails dev server. Skip to **Happy-path install** if
> you just want the command. The rest of the doc is there for when
> something's off (fresh simulator, rotated cert, cold-start debugging,
> someone proposes going back to one of the approaches we already ruled
> out, etc.).

## Why this is needed

The `Harvest Dev` scheme points at `https://harvest.bitrat.test`. That
hostname is served by **dd-ferryman**, a local reverse proxy on the
Rails-side monolith owner's machine. dd-ferryman terminates TLS using a
self-generated root CA — `dd-ferryman Local CA` — whose certificates are
not in Apple's trust store.

The iOS Simulator has its own system trust store, independent of the host
macOS keychain. Out of the box it trusts only the public CAs that ship
with iOS. Asking URLSession (or Safari, or any other tool running inside
the sim) to connect to `harvest.bitrat.test` fails at cert-chain
evaluation with:

```
NSURLErrorDomain Code=-1202
"The certificate for this server is invalid."
```

Until we install the dd-ferryman root into the sim's trust store, every
API call from the dev build will fail before it even hits Rails.

## Happy-path install

Boot the simulator you want to develop against (Xcode → Devices →
Simulators → double-click the one you use). Then:

```sh
xcrun simctl keychain booted add-root-cert "$HOME/.dd-ferryman/ca/ca.crt"
```

That's it. Connection works immediately — no rebuild, no relaunch of
Xcode. You can verify by:

```sh
xcrun simctl openurl booted https://harvest.bitrat.test/
```

Safari in the sim should load the Rails root. If it shows a cert warning,
the install didn't take — see **Troubleshooting** below.

The installed trust survives simulator reboots. It does **not** survive
`Erase All Content and Settings` on the sim; reinstall after an erase.

## Multiple simulators

`xcrun simctl keychain booted …` targets whichever simulator is booted.
To install into a specific simulator without booting anything else:

```sh
# List available simulators + their UDIDs
xcrun simctl list devices available

# Install into a specific one (replace with the UDID)
xcrun simctl keychain <UDID> add-root-cert "$HOME/.dd-ferryman/ca/ca.crt"
```

Each simulator has its own trust store. If you test on multiple, install
into each.

## If the CA rotates

dd-ferryman regenerates its root CA under these conditions (per the
Rails side):

- the `~/.dd-ferryman/ca/` directory is wiped
- someone runs a "regenerate CA" command
- a new contributor sets up dd-ferryman for the first time

When this happens, the old CA in the sim's trust store still exists and
still trusts the old cert fingerprints — but Rails now serves a cert
signed by a different root, and the sim rejects it.

Fix:

1. Pull the new CA onto your machine (it'll be at `~/.dd-ferryman/ca/ca.crt`
   again; just re-fetched or re-generated).
2. Re-run the install command:
   ```sh
   xcrun simctl keychain booted add-root-cert "$HOME/.dd-ferryman/ca/ca.crt"
   ```
   `simctl keychain add-root-cert` is additive — installing the new CA
   doesn't remove the old one. That's fine; the old one just becomes
   unused.
3. **Optional** — if you want to clean up stale trust entries, reset the
   sim's trust store:
   ```sh
   xcrun simctl keychain booted reset
   ```
   This wipes the trust store (you'll need to reinstall the current CA).

To sanity-check which CA is currently issuing certs:

```sh
openssl x509 -in "$HOME/.dd-ferryman/ca/ca.crt" -noout -subject -fingerprint -sha256
```

Compare the SHA-256 fingerprint to what `openssl s_client` reports for a
live connection:

```sh
openssl s_client -showcerts -servername harvest.bitrat.test \
  -connect harvest.bitrat.test:443 </dev/null 2>&1 |
  openssl x509 -noout -issuer -fingerprint -sha256
```

If fingerprints differ between `~/.dd-ferryman/ca/ca.crt` and the live
cert's issuer, the CA on disk is stale — ask the Rails agent where the
current CA lives.

## Troubleshooting

**"Can't reach Harvest" in the app after install.**

1. Confirm the sim is actually booted and is the one you installed into:
   `xcrun simctl list devices booted`.
2. Re-run the install. `simctl keychain add-root-cert` has no output on
   success; silence means it worked.
3. In the sim's Safari, open `https://harvest.bitrat.test/`. If Safari
   loads the page, trust is fine and the issue is in the app. If Safari
   shows a cert warning, trust isn't set up — continue below.
4. Reset the sim's trust store and try again:
   `xcrun simctl keychain booted reset` then reinstall.
5. As a last-resort diagnostic, open Settings on the sim → General →
   VPN & Device Management (or Profiles) → you should see a profile for
   the CA. If it's there but not trusted, go to General → About →
   Certificate Trust Settings and toggle the CA on. (With
   `simctl keychain add-root-cert` you usually don't need this manual
   step, but some Xcode/iOS combinations are finicky.)

**dd-ferryman isn't running / no `~/.dd-ferryman/ca/ca.crt` exists.**

Problem's on the Rails side, not iOS. Ask the Rails agent. Don't work
around this with a test fixture CA — it has to be the actual CA Rails is
using, otherwise the installed cert won't match what the server serves.

**`curl` from the Mac works, Safari in the sim fails.**

This is the normal state before CA install. Mac and sim have separate
trust stores. Installing the CA in the sim fixes it.

**CA install succeeded but Safari still says "connection not private."**

Almost certainly **not** a CA-trust problem — the CA install works. Most
likely culprit: the leaf cert dd-ferryman is serving has a validity
period >398 days, which iOS 13+ rejects for any cert issued under a
user-installed root CA
([Apple HT211025](https://support.apple.com/en-us/HT211025)).

Diagnose. First stream the sim's trust log while loading the URL:

```sh
xcrun simctl spawn booted log stream --style compact \
  --predicate 'subsystem == "com.apple.securityd" AND eventMessage CONTAINS[c] "trust"' &
xcrun simctl openurl booted https://harvest.bitrat.test/
```

If you see `Trust evaluate failure: [leaf OtherTrustValidityPeriod]`,
that's the 398-day rule. Confirm the leaf's validity period:

```sh
DATES=$(openssl s_client -showcerts -servername harvest.bitrat.test \
  -connect harvest.bitrat.test:443 </dev/null 2>/dev/null \
  | openssl x509 -noout -dates)
echo "$DATES"
```

Calculate `notAfter - notBefore` in days. Anything >398 fails under
user-installed-root rules.

**Fix: server-side only.** Reconfigure dd-ferryman (or whatever tool
issues leaf certs on the Rails side) to issue leaf certs with a ≤398-day
validity. 397 is safer — some iOS versions have counted bounds
inclusively. After the reissue, the sim doesn't need any changes (root
didn't change); just restart the dev server.

No iOS-side workaround exists for this short of disabling cert trust in
code, which we ruled out. Do not disable cert trust to work around a
server-side config issue.

**"Invalid CA certificate" when running `add-root-cert`.**

The file at `~/.dd-ferryman/ca/ca.crt` isn't a valid X.509 cert (maybe
truncated, maybe binary-corrupted, maybe wrong file). Inspect it:

```sh
openssl x509 -in "$HOME/.dd-ferryman/ca/ca.crt" -noout -subject
```

Should print `subject= /CN=dd-ferryman Local CA/O=dd-ferryman`. If it
errors, the file is bad — ask the Rails agent.

## Things we tried that didn't work (don't re-invent)

**ATS Info.plist exception (`NSAppTransportSecurity > NSExceptionDomains
> harvest.bitrat.test > NSExceptionAllowsInsecureHTTPLoads: true`).**

Apple's docs imply this relaxes server-trust evaluation for the listed
domain. On iOS 26 (and we suspect iOS 18+), it does not. Verify with:

```sh
nscurl --ats-diagnostics https://harvest.bitrat.test/
```

which tries every ATS permutation Apple exposes. All fail with `-1202`
(certificate invalid), including `NSAllowsArbitraryLoads: true`. Cert
trust is now evaluated **before** ATS and is independent of it on modern
iOS. There is no Info.plist key that bypasses it for a
simulator-untrusted root.

If you're tempted to revive this because it used to work: run `nscurl`
first. If it still fails for every configuration, ATS isn't the layer
you need.

**Programmatic `URLSessionDelegate` that accepts any cert for
`harvest.bitrat.test`.**

Technically works (implement `didReceive challenge` for
`NSURLAuthenticationMethodServerTrust`, check `host == devHost`,
`completionHandler(.useCredential, URLCredential(trust: trust))`).

We deliberately didn't take this path because:

- It's dev-only code that ships in the dev binary and has to be kept in
  sync with the dev host.
- It masks real TLS issues — if Rails ships a broken cert chain, the app
  doesn't notice during dev; you'd only catch it once prod traffic
  starts failing (where the delegate isn't active).
- Option 1 (CA install) mirrors production's TLS posture exactly, which
  is what you want from a dev environment.

If circumstances change (e.g. CI sims that can't have state baked in,
mandatory org policy against CA installs) and this approach becomes
necessary, the right shape is:

```swift
final class DevHostTrustingDelegate: NSObject, URLSessionDelegate {
    // Gate on baseURL.host == "harvest.bitrat.test" at construction so
    // prod builds (which point at harvest.bitrat.io) cannot construct
    // this delegate and cannot use relaxed trust.
}
```

with optional CA-fingerprint pinning (compare
`SecCertificateCopyData(leaf)` SHA-256 to a known-good hash of
dd-ferryman's root). But please exhaust option 1 before adding any
custom trust code.

## Why no `bin/install-dev-ca` script?

The install is one command that's memorable once you've run it once. A
script would wrap `xcrun simctl keychain booted add-root-cert` with the
path, which is:

```sh
xcrun simctl keychain booted add-root-cert "$HOME/.dd-ferryman/ca/ca.crt"
```

If you find yourself running this more than a few times, add the script
— it belongs in `bin/install-dev-ca` with a shebang. But for a solo-dev
workflow where you install on a fresh sim once every few months, the
docs are enough.
