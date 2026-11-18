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
- Bundle ID `com.aayush.paper.reader` (override with `PAPER_BUNDLE_ID`). Signing team and device UDID come from `PAPER_TEAM_ID` and `PAPER_DEVICE_UDID`; the committed project leaves the team blank.
- Owner's values live in the ignored `.env.device`. Load them with `set -a; . ./.env.device; set +a` before device commands. Never commit real UDIDs or team IDs: this repository is public.
- Paper uses SideStore renewal as of 18 November 2026; see below. Preserve the same bundle/team identity; never uninstall (it would delete the local library).
- Never print, commit or pass a Reader token in command arguments.

## Unit tests (simulator)

Run signed. Do not pass `CODE_SIGNING_ALLOWED=NO`: the Keychain tests need entitlements and fail with `keychain(-34018)`.

```sh
xcodebuild test -project Paper.xcodeproj -scheme Paper \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' \
  -derivedDataPath build
```

Last run: 68 simulator unit tests passed, one opt-in physical test skipped (18 Nov 2026, PencilKit reader). Simulator UI flows passed: article one-finger scrolling with the tool picker open, ink/position restoration, review capture and one confirmed fixture delivery; EPUB chapter isolation; Quick Look Markup persistence. Simulator touches do not establish physical Pencil behavior. Rerun after the wrap merge with the committed blank team: 69 unit tests, 0 failures, 2 opt-in live tests skipped. Earlier: physical article read/render and Downloaded/Markups/review/backup UI checks (22 Oct); physical Anthropic analysis and 717-PDF full refresh (21 Oct).

## Build and install on the iPad

Load `.env.device` first. Preferred: `python3 scripts/update-ipad.py`. It backs up Documents to `~/Documents/Paper Backups`, builds, checks bundle/signing identity, installs in place, compares Library SHA-256 hashes, then launches. Keep the iPad unlocked and finish Markup edits first. The final 22 Oct update preserved all 31 Documents files; backup: `~/Documents/Paper Backups/2026-10-22-151213`. All 18 PDFs from the earlier baseline also match. Use `--renew-signing` to request fresh automatic provisioning and require a later expiry before installation. Verify embedded expiry; a normal rebuild may reuse a profile.

Manual commands (back up first):

```sh
xcodebuild build -project Paper.xcodeproj -scheme Paper \
  -destination "id=$PAPER_DEVICE_UDID" -derivedDataPath build-device \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$PAPER_TEAM_ID"
xcrun devicectl device install app --device "$PAPER_DEVICE_UDID" \
  build-device/Build/Products/Debug-iphoneos/Paper.app
xcrun devicectl device process launch --device "$PAPER_DEVICE_UDID" \
  com.aayush.paper.reader
```

## Provisioning the Anthropic key

Preferred: AI settings in the app. Development: `python3 scripts/provision-anthropic.py` reads `ANTHROPIC_API_KEY` from ignored `.env`, copies a private one-time file to `tmp/anthropic-key.txt`, then deletes the local copy. Relaunch with `xcrun devicectl device process launch --terminate-existing --device "$PAPER_DEVICE_UDID" com.aayush.paper.reader`. The app moves the key into the separate `com.aayush.paper.reader.anthropic` Keychain service and deletes the import file. Never display keys, pass them in arguments, or bundle `.env`.

Opt-in physical analysis test: `TEST_RUNNER_PAPER_LIVE_REVIEW_ID=<localUUID> xcodebuild test -project Paper.xcodeproj -scheme Paper -destination "id=$PAPER_DEVICE_UDID" -derivedDataPath build-device -allowProvisioningUpdates -only-testing:PaperUITests/ReviewLiveSmokeTests`. This sends selected saved pages to Anthropic, persists drafts, and creates no Reader highlight.

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
xcodebuild test -project Paper.xcodeproj -scheme Paper -destination "id=$PAPER_DEVICE_UDID" \
  -derivedDataPath build-device -allowProvisioningUpdates -only-testing:PaperUITests/ReaderLiveSmokeTests
```

`scripts/reader-test-server.py` is a local fake Reader service used by `ReaderLibraryFlowTests`; its token is a fake test value.

## Storage layout

`Documents/Library/{UUID}/` holds `source.pdf` (untouched original), `reading.pdf` (with saved Markup) and `document.json`. `Documents/reader-catalog.json` holds the Reader catalog. Original files are immutable; edited-copy saves validate and write atomically. `review.json` in each document folder stores drafts, transcription alternatives and delivery state; `analysis.json` stores successful page fingerprints and measured usage. Prepared articles also retain `source.html` and `source.txt`, with metadata in `Documents/reader-articles.json`. Article/EPUB ink lives beside them as `pencil-ink-<sha256(section)>.json` (a `PKDrawing` plus scroll offset, one file per article or chapter). Pre-PencilKit `direct-ink-<hash>.json` files are migrated on first open and left untouched as a recoverable copy. User-selected Files backups copy versioned Library/RecentlyRemoved/catalog snapshots and exclude credentials; provider upload is separate from local verification. Removal moves the entire folder to `Documents/RecentlyRemoved/{UUID}`; restore moves it back. Permanent deletion is explicit. Cover images use a bounded memory cache, separate from document data.

## References

- https://developer.apple.com/documentation/quicklook/qlpreviewcontrollerdelegate/previewcontroller%28_%3Aeditingmodefor%3A%29
- https://developer.apple.com/videos/play/wwdc2019/719/

## Physical article verification

Read-only real article render (no Reader writes): `TEST_RUNNER_PAPER_LIVE_ARTICLE=1 xcodebuild test -project Paper.xcodeproj -scheme Paper -destination "id=$PAPER_DEVICE_UDID" -derivedDataPath build-device -allowProvisioningUpdates -only-testing:PaperTests/ArticleLiveReadOnlyTests`. Use `test`, since a regular build does not embed the app-hosted test bundle required by `test-without-building`. The opt-in test saves source fixtures in app tmp and attaches a private rendered PDF to its result. Unavailable figures have explicit PDF placeholders/count warnings, and document.json stores optional preparationWarning; source.txt excludes Paper labels.


## SideStore renewal — 18 November 2026

Paper is now managed by SideStore on the iPad. Free signing still expires after seven days; check Paper’s counter in SideStore → My Apps and refresh before expiry. Refreshing needs Wi-Fi with internet and LocalDevVPN connected. The Mac can be off. Background refresh has not yet been verified, so manually refresh every few days for now. Downloaded reading and handwriting need neither VPN nor internet.

Migration retained `com.aayush.paper.reader` and the original signing team. For future imports, enable Settings → Advanced Settings → User Customizations → Customize AppID; leave the original App ID and uncheck Append Team ID. Never uninstall Paper. The 18 November migration preserved all 35 Documents files byte for byte and the app launched successfully. Reader and Anthropic Keychain credentials survived the migration (18 Nov: Reader catalog refreshed; an Anthropic request returned HTTP 200).

Package SideStore builds with `scripts/package-ipa.py` (see INTEGRATE.md); never `ditto --sequesterRsrc`, which produced the rejected `Payload/._Paper.app`. To stage an IPA, copy it into SideStore's app container `Documents/` with `xcrun devicectl device copy to --domain-type appDataContainer --domain-identifier com.SideStore.SideStore.$PAPER_TEAM_ID`, then import from Files. The PencilKit build (`~/Documents/Paper Backups/SideStore Setup/Paper-PencilKit.ipa`) was installed in place this way on 18 Nov; all 59 migrated strokes survived and new strokes saved.

After verifying each SideStore update, keep the current Paper IPA in SideStore’s Files folder and remove superseded Paper IPA copies after confirming they match the Mac archives byte for byte.

Backup: `~/Documents/Paper Backups/2026-11-18-213214/before`; SHA-256 manifest: `library-sha256.json` in its parent. Post-install verification copy: `~/Documents/Paper Backups/2026-11-18-sidestore-verification`. Prepared IPA: `~/Documents/Paper Backups/SideStore Setup/Paper.ipa` (retained 22 October build; re-sign before installation).

The old profile expired 27 October 2026 at 22:03:04 UTC. Xcode recovery failed because no cached profile or configured Apple Account was available. SideStore recovery succeeded; no application code was changed or rebuilt this session. Future Xcode updates must coordinate certificate use with SideStore and retain identity, backup and hash checks.

Setup/refresh instructions: https://docs.sidestore.io/docs/installation/install and https://docs.sidestore.io/docs/installation/prerequisites .

## Reuse status

Stealable: yes. The repository is public; `wrap` keeps README.md (people) and INTEGRATE.md (agents) current and scans each diff for owner identifiers. Last checked 18 Nov 2026.

| Dimension | Status | Evidence |
| --- | --- | --- |
| Docs | Current through PencilKit reader | INTEGRATE code map and packaging updated 18 Nov |
| Current-file privacy | Owner UDID/team moved to ignored `.env.device`; gitleaks run on the commit set | 18 Nov wrap |
| History privacy | Public history rewritten and rescanned; old repo kept as private archive; the pre-public history lives only in `~/Documents/Paper Backups/public-adoption-review-2026-11-18/pre-public-history.bundle` | Local pre-push guard blocks it and owner identifiers |
| Setup verification | Simulator unit/UI tests; owner device via SideStore. Fresh adopter account untested | 18 Nov |
| License | MIT | `LICENSE` |
| Demo | 23-second PDF Markup demo + screenshots, synthetic documents | `docs/demo.mp4`, `docs/images/README.md`; doesn't show the PencilKit reader yet |
