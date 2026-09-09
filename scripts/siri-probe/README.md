# SendMoi preview probe

This is an opt-in, non-sending experiment. It is not the production Siri feature.

## Run the app

Open this worktree's `SendMoi.xcodeproj`, select **SendMoiProbe**, and run on Mac or a simulator. For a physical device, use your normal development signing setup for the probe's separate bundle identifiers.

The `SiriProbe` configuration defines `SENDMOI_SIRI_PROBE`. The normal Debug and Release configurations do not. The probe has a separate bundle ID, no OAuth callback, and no App Group/keychain-sharing entitlements. It launches a preview screen instead of AppModel; its embedded share extension exits without doing work. `sendEmail` throws immediately in this configuration. No Gmail connection or recipient setup is needed.

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project SendMoi.xcodeproj -scheme SendMoiProbe -configuration SiriProbe \
  -destination 'platform=macOS' -derivedDataPath build/probe-mac \
  CODE_SIGN_IDENTITY='Apple Development' CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER='' build

xcodebuild -project SendMoi.xcodeproj -scheme SendMoiProbe -configuration SiriProbe \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/probe-ios \
  CODE_SIGNING_ALLOWED=NO build
```

Use a signed Mac build for runtime Shortcuts checks. Current limitation: invocation/return is verified, but workflow completion stalled in this Mac beta environment; see the findings report. An unsigned build is sufficient for compilation but not a reliable runtime integration test.

## Shortcuts and Siri checks

1. Launch the probe once to register its action.
2. In Shortcuts, create a shortcut with **Preview with SendMoi** and give Article URL a public article URL. Run it. It returns preview text, never a sent status. The app itself displays the full HTML preview.
3. Repeat with the app closed and then already running. Record whether a window appears and whether a result returns.
4. On a compatible physical iPhone with Siri AI, view an article in Safari and try “Preview this with SendMoi Probe.” Record the exact phrase, supplied URL, clarifications, timing, and result. A request for a URL means onscreen resolution was not established.
5. Repeat using an explicitly supplied URL in Shortcuts. Do not confuse that success with conversational Siri routing.

The custom App Shortcut is deliberately not a `.mail` schema. Apple's current mail domain requires actions outside SendMoi's scope. Do not add fake send/read/archive actions to satisfy it.

## Reproduce the content comparison

```sh
scripts/siri-probe/run-fidelity.sh
scripts/siri-probe/check.sh
```

The harness compiles the current production content builder with the probe seam. It renders URL-only and browser-context versions without sending. It uses an 8-second total preview budget and 5-second model budget; the production metadata cache is bypassed in probe builds to avoid hiding latency. Model availability is recorded but does not prove the model produced a given summary: existing fallback behavior remains active.

`corpus.json` freezes the sample and thresholds. Do not replace failing URLs. Results and HTML previews are under ignored `build/siri-probe-fidelity/`; they include source text for local comparison and should not be committed or published. The included sample is science/nature/technology-heavy and does not establish general consumer sharing reliability.

The browser baseline runs the actual Safari preprocessor in a nonpersistent WKWebView. Its image comes from page metadata, not an actual Safari share attachment. Safari/iPhone parity, authenticated pages, selected text, X, and other diagnostic sources require follow-up device testing. No browser session or account credentials are reused.

`check.sh` verifies invalid-input rejection, disabled sending, and cancellation. It does not claim to test production queue safety, which has not been changed.

## Normal-build checks

```sh
xcodebuild -project SendMoi.xcodeproj -scheme SendMoi -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/normal-mac CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SendMoi.xcodeproj -scheme SendMoi -configuration Release \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/normal-ios CODE_SIGNING_ALLOWED=NO build
```

Do not archive/distribute the probe as SendMoi. It exists only for development evaluation.
