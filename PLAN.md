# Paper delivery plan — 21 October 2026

The approved library and markup review workflow are implemented and installed. Scope and storage rules are in SPEC.md; earlier measurements remain in docs/.

## Completed

- [x] Reader listing, pagination, nullable metadata, search, source resolution, secure PDF download, Keychain connection and offline reopening.
- [x] Immutable originals and atomic edited-copy saves, verified through unit tests and native Markup save/relaunch UI tests.
- [x] White appearance, local first-page/remote covers, matching search counts, per-document export/review/removal actions and search focus handling.
- [x] Reproduce redundant cached-launch scan with a failing test; implement cached startup, incremental merge with overlapped checkpoint and explicit full reconciliation.
- [x] Recoverable removal/restore and explicit permanent deletion. Test that edited bytes and original bytes survive restoration; restore reuses the local copy.
- [x] Approve and implement full-PDF review beside passage, handwritten transcription and labeled AI interpretation; portrait stacks views.
- [x] Selected-page rendering and Anthropic structured analysis, cancellation, elapsed progress, safe errors, validated page references and local draft persistence.
- [x] Persist confirmed delivery payload before POST; retain returned Reader IDs; reconcile ambiguous sends; preserve sent items during reanalysis. Red/green regression tests cover both duplicate risks.
- [x] Measure live full-refresh decode failure at image_url, record index 39. Reproduce in a failing API test; tolerate malformed optional covers; verify live refresh succeeds.
- [x] Renew signing, back up Documents, install over the app and compare hashes. Latest backup: `~/Documents/Paper Backups/<backup-timestamp>`.
- [x] Provision Anthropic through a private one-time file; verify it was consumed into Keychain. Keep .env and private samples outside Git.

## Verification

| Check | Result |
| --- | --- |
| Signed simulator unit tests | 34 passed |
| Library connect/paginate/search/download/offline reopen | Passed; four screenshots inspected |
| Simulator analysis/edit/send/relaunch/remove/restore | Passed; one analysis, one Reader POST; restoration adds no PDF transfer |
| Native visible ink/save/relaunch | Passed, 49.518 s |
| Physical iPad with real Keychain/Anthropic | Passed, 28.281 s; four pages produced six saved drafts; no live Reader send |
| Physical full Reader refresh | Passed, 31.614 s; 717 records, 690 with remote cover metadata |
| Data after final refresh | All 16 Library files, including review.json, retained their hashes |
| Screenshots | Library, download, Quick Look, landscape review and physical refreshed library opened and inspected |

Results are under `/tmp/paper-review-green-20261021.xcresult`, `/tmp/paper-live-review-20261021.xcresult` and `/tmp/paper-live-covers-green-20261021.xcresult`. Durable data snapshots are under Documents/Paper Backups.

## Follow-up

- [ ] Verify one user-confirmed highlight in the real Reader account, then inspect original PDF placement and downstream Readwise retrieval. Controlled-service delivery is already covered.
- [ ] Associate older Files imports with existing Reader documents for sending.
- [ ] Diagnose palm strokes on the physical iPad; simulator tests cannot establish Pencil/palm behavior.
- [ ] Renew before **28 October 00:03 Helsinki**, or move to longer-lived signing/distribution through paid membership.
- [ ] Broaden coverage for interrupted removal, account replacement, cover cache/scroll performance, VoiceOver, Dynamic Type and hardware keyboard.
- [ ] Consider automatic connection-sheet presentation on authentication failure; current errors direct the user to replace the token manually.

No native image/ink upload is promised. Recognition accuracy has no ground-truth benchmark; users review all derived text and interpretations.
