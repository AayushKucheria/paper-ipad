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
- Personal Team profile expires 27 Oct 2026. Rebuild and reinstall with the same bundle ID; never uninstall (it would delete the local library).
- Never print, commit or pass a Reader token in command arguments.

## Unit tests (simulator)

Run signed. Do not pass `CODE_SIGNING_ALLOWED=NO`: the Keychain tests need entitlements and fail with `keychain(-34018)`.

```sh
xcodebuild test -project Paper.xcodeproj -scheme Paper \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' \
  -derivedDataPath build
```

Last run: 22 unit tests, 0 failures.

## Build and install on the iPad

```sh
xcodebuild build -project Paper.xcodeproj -scheme Paper \
  -destination 'id=<your-device-udid>' -derivedDataPath build-device \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration
xcrun devicectl device install app --device <your-device-udid> \
  build-device/Build/Products/Debug-iphoneos/Paper.app
xcrun devicectl device process launch --device <your-device-udid> \
  com.aayush.paper.reader
```

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

`Documents/Library/{UUID}/` holds `source.pdf` (untouched original), `reading.pdf` (with saved Markup) and `document.json`. `Documents/reader-catalog.json` holds the Reader catalog. Original files are immutable; edited-copy saves validate and write atomically.

## References

- https://developer.apple.com/documentation/quicklook/qlpreviewcontrollerdelegate/previewcontroller%28_%3Aeditingmodefor%3A%29
- https://developer.apple.com/videos/play/wwdc2019/719/
