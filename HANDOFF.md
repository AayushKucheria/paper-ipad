# Handoff — 18 November 2026

## In progress

- Verify Paper’s next SideStore refresh and background renewal. Until proven, manually refresh every few days with Wi-Fi and LocalDevVPN; the Mac can be off. Check expiry in SideStore. Exact new profile expiry was not measured.
- Verify Reader and Anthropic Keychain access after SideStore migration, without exposing credentials or sending an unconfirmed highlight.

## Known issues / loose ends

- Public `main` is the PDF app plus adoption docs and demo assets. The owner checkout has ongoing article, backup, markup and EPUB/direct-reading work; those edits are unpublished and were not changed or committed during public preparation. Do not infer the public app supports them from local October notes.
- Real Reader passage matching, original PDF placement and downstream Readwise retrieval still need a user-confirmed end-to-end check. Sending remains manual; native ink/image upload is not promised.
- User still needs to choose an in-app Files backup destination. Provider upload is separate from local checksum verification.
- Palm strokes, older Files imports lacking Reader association, broader accessibility/interruption/performance checks and 17 PDFs without download sources remain open.
- Existing clones contain old private history. Synchronize with cleaned public main; never merge the archived history back. Owner checkout main was aligned without overwriting existing source files and has a local pre-push guard against reintroducing historical private data. It retains uncommitted personal configuration and feature changes; review these before publishing.

## Recovery and release evidence

- SideStore migration retained original bundle/signing identity. All 35 Documents files matched their pre-migration SHA-256 hashes; device launch succeeded. Never uninstall Paper. Backups: `~/Documents/Paper Backups/2026-11-18-213214/before` and `~/Documents/Paper Backups/2026-11-18-sidestore-verification`; manifest is beside `before`. Prepared retained-build IPA: `~/Documents/Paper Backups/SideStore Setup/Paper.ipa`.
- Repository is public at https://github.com/AayushKucheria/paper-ipad . The previous repository remains a private archive because GitHub retained old commit objects after history rewriting. The replacement was cloned without authentication and scanned: 112 historical blobs had no targeted private identifiers, owner paths or embedded document images; Gitleaks reported zero secret matches. No claim is made about undiscovered private data. Original-history bundle and release report remain outside the repo.
- README explains sideloading. Device scripts accept adopter team/device/bundle configuration. The MIT license and agent adoption guide remain intact. Published screenshots and the 23-second MP4/animated preview use synthetic documents; provenance is in docs/images/README.md. Published MP4 was verified byte for byte.
- History cleanup introduced three unquoted Xcode team placeholders; ee9315e corrected them. Project lint/discovery, fresh build, all 34 signed simulator unit tests, screenshot capture and demo-recording UI flows passed after the fix. No new adopter device/live-account test was run. Capture servers are stopped; the dedicated capture simulator is shut down.

## Next logical step

Verify Paper’s next SideStore refresh and preserved Reader/Anthropic access; continue manual refreshes until background renewal is proven.
