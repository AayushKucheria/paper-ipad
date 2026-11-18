# Handoff — 18 November 2026

## In progress

- Paper recovered through SideStore. User imported the retained 22 October Paper.ipa with Customize AppID enabled and Append Team ID unchecked. Original bundle ID `com.aayush.paper.reader` and the original signing team retained. Device launch succeeded; all 35 Documents hashes match the pre-migration manifest.
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


## Public adoption preparation — 18 November

Prepared in an isolated full clone, preserving owner working changes. README includes source installation and SideStore renewal; scripts accept PAPER_BUNDLE_ID. Replaced embedded document thumbnail/library metadata in white-library prototype with synthetic examples. Thirty-four signed simulator unit tests passed; missing script configuration fails before device access. No new adopter device/live-account test or shareable product demo was produced.

User authorized history cleanup and public visibility. Historical device identifiers, owner paths and embedded preview/library metadata were removed; all 111 remaining historical blobs passed the targeted privacy check, and Gitleaks 8.30.1 reported zero secret findings. A verified original-history bundle and full private release report are retained outside this repository. History has new commit IDs: existing clones must synchronize with cleaned main rather than merge old history back. Keep owner working files and local configuration backed up during synchronization.
