# Handoff — 18 November 2026

## In progress

- Paper recovered through SideStore. User imported the retained 22 October Paper.ipa with Customize AppID enabled and Append Team ID unchecked. Original bundle ID `com.aayush.paper.reader` and team `<your-team-id>` retained. Device launch succeeded; all 35 Documents hashes match the pre-migration manifest.
- Verify a subsequent SideStore refresh and background renewal. Until verified, manually refresh every few days using Wi-Fi and LocalDevVPN. Mac can be off. Check the current expiry in SideStore; no exact new profile expiry was measured.
- Verify Reader and Anthropic Keychain access after migration without exposing credentials or sending an unconfirmed highlight.

## Known issues / loose ends

- Pre-existing feature edits and untracked article/backup/markup files remain in the working tree; they were present before this recovery session and are excluded from its commit. Earlier 22 October notes report 57 passing unit tests and five UI flows; no code tests were rerun for this signing-only recovery.
- Real Reader passage matching, original PDF placement and downstream Readwise retrieval still need a user-confirmed end-to-end check. Sending remains manual. Native ink/image upload is not promised.
- User still needs to choose an in-app Files backup destination. Provider upload is separate from local checksum verification.
- Palm strokes, older Files imports lacking Reader association, representative physics-article rendering, broader accessibility/interruption/performance coverage and 17 PDFs without download sources remain open. EPUB support is deferred.
- Sonnet remains the analysis default; Haiku is selectable. Existing small-sample cost comparisons do not establish equal quality.

Recovery backup: `~/Documents/Paper Backups/2026-11-18-213214/before` with sibling `library-sha256.json`. Post-install copy: `~/Documents/Paper Backups/2026-11-18-sidestore-verification`. All 35 files matched before launch. Earlier October backups remain retained. Prepared IPA: `~/Documents/Paper Backups/SideStore Setup/Paper.ipa`.

The previous profile expired 27 October 22:03:04 UTC. Xcode renewal stopped on missing cached profiles; a normal build failed with No Accounts/no matching profile. Official iloader 2.4.1 was installed in /Applications; user completed SideStore 0.7.0 setup and certificate replacement. Do not uninstall Paper. Future Xcode installs must preserve identity and coordinate signing with SideStore.

## Next logical step

Verify Paper’s next SideStore refresh and preserved Reader/Anthropic access; continue manual refreshes until background renewal is proven.
