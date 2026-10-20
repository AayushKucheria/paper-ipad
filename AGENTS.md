# AGENTS.md

Agent-facing notes for Paper. The README is for people; everything operational lives here.

## Doc map

| File | Purpose |
| --- | --- |
| `SPEC.md` | Scope, storage rules, API behavior, measured evidence |
| `PLAN.md` | Test-first plan and delivery checklist |
| `HANDOFF.md` | Current state, loose ends, next step |
| `docs/reader-api-research.md` | Reader API verification |
| `docs/annotation-sync-research.md` | Annotation export research |
| `docs/missing-pdf-sources.md` | The 17 PDFs with no download source |

## Project facts

- Project definition: `project.yml` (run `xcodegen generate` after changing targets). Targets iPadOS 18+.
- Bundle ID `com.aayush.paper.reader`; Personal Team `<your-team-id>`.
- Device: iPad Air (5th gen), UDID `<your-device-udid>`, Developer Mode on.
- Personal Team profile expires 27 Oct 2026 at 22:03:04 UTC (28 Oct 00:03:04 Helsinki). Rebuild and reinstall with the same bundle ID; never uninstall (it would delete the local library).
- Never print, commit or pass a Reader token in command arguments.

## Unit tests (simulator)

Run signed. Do not pass `CODE_SIGNING_ALLOWED=NO`: the Keychain tests need entitlements and fail with `keychain(-34018)`.

```sh
xcodebuild test -project Paper.xcodeproj -scheme Paper \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' \
  -derivedDataPath build
```

Last run: 34 unit tests, 0 failures (21 Oct 2026). Simulator review/send/restore and native Markup persistence flows passed; physical Anthropic analysis and 717-PDF full refresh passed.

## Build and install on the iPad

Preferred: `python3 scripts/update-ipad.py`. It backs up Documents to `~/Documents/Paper Backups`, builds, checks bundle/signing identity, installs in place, compares Library SHA-256 hashes, then launches. Keep the iPad unlocked and finish Markup edits first. The 21 Oct update preserved all 16 Documents files. Use `--renew-signing` to request fresh automatic provisioning and require a later expiry before installation. Verify embedded expiry; a normal rebuild may reuse a profile.

Manual commands (back up first):

```sh
xcodebuild build -project Paper.xcodeproj -scheme Paper \
  -destination 'id=<your-device-udid>' -derivedDataPath build-device \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration
xcrun devicectl device install app --device <your-device-udid> \
  build-device/Build/Products/Debug-iphoneos/Paper.app
xcrun devicectl device process launch --device <your-device-udid> \
  com.aayush.paper.reader
```

## Provisioning the Anthropic key

Preferred: AI settings in the app. Development: `python3 scripts/provision-anthropic.py` reads `ANTHROPIC_API_KEY` from ignored `.env`, copies a private one-time file to `tmp/anthropic-key.txt`, then deletes the local copy. Relaunch with `xcrun devicectl device process launch --terminate-existing --device <your-device-udid> com.aayush.paper.reader`. The app moves the key into the separate `com.aayush.paper.reader.anthropic` Keychain service and deletes the import file. Never display keys, pass them in arguments, or bundle `.env`.

Opt-in physical analysis test: `TEST_RUNNER_PAPER_LIVE_REVIEW_ID=<localUUID> xcodebuild test -project Paper.xcodeproj -scheme Paper -destination 'id=<your-device-udid>' -derivedDataPath build-device -allowProvisioningUpdates -only-testing:PaperUITests/ReviewLiveSmokeTests`. This sends selected saved pages to Anthropic, persists drafts, and creates no Reader highlight.

## Provisioning the Reader token

Preferred: the in-app Connect screen. For development, copy a one-time file to the app's `tmp/reader-token.txt`; the app stores it in Keychain and deletes the file on next launch. Delete the local copy afterwards.

```sh
xcrun devicectl device copy to --device <udid> --source <file> \
  --destination tmp/reader-token.txt --domain-type appDataContainer \
  --domain-identifier com.aayush.paper.reader
```

## On-device UI tests

Needs Settings > Developer > Enable UI Automation on the iPad. Live smoke test (passed on device 20 Oct 2026):

```sh
TEST_RUNNER_PAPER_LIVE_PDF_ID=<readerID> TEST_RUNNER_PAPER_LIVE_PDF_TITLE=<title> TEST_RUNNER_PAPER_LIVE_PDF_COUNT=<n> \
xcodebuild test -project Paper.xcodeproj -scheme Paper -destination 'id=<your-device-udid>' \
  -derivedDataPath build-device -allowProvisioningUpdates -only-testing:PaperUITests/ReaderLiveSmokeTests
```

`scripts/reader-test-server.py` is a local fake Reader service used by `ReaderLibraryFlowTests`; its token is a fake test value.

## Storage layout

`Documents/Library/{UUID}/` holds `source.pdf` (untouched original), `reading.pdf` (with saved Markup) and `document.json`. `Documents/reader-catalog.json` holds the Reader catalog. Original files are immutable; edited-copy saves validate and write atomically. `review.json` in each document folder stores drafts and delivery state. Removal moves the entire folder to `Documents/RecentlyRemoved/{UUID}`; restore moves it back. Permanent deletion is explicit. Cover images use a bounded memory cache, separate from document data.

## References

- https://developer.apple.com/documentation/quicklook/qlpreviewcontrollerdelegate/previewcontroller%28_%3Aeditingmodefor%3A%29
- https://developer.apple.com/videos/play/wwdc2019/719/
