# Paper delivery plan — 21 October 2026

## Direct reading verification

- Verify the compact library’s filters overlap and shelf membership survives relaunch.
- Prepare a Reader fixture as an article, draw directly, relaunch and reopen, then check that ink persists. Verify reviewed text goes to the original Reader ID through the fixture service.
- Verify EPUB spine order, original retention, local assets, and rejection of unsafe archives. Verify article snapshots preserve original text and offline figures.
- Verify an invented or ambiguous quote never reaches the highlight endpoint, and a verified quote is sent with exact source spelling and punctuation.
- Check portrait layout on the simulator and measure actual Pencil input, finger scrolling and offline reopen on Aayush’s iPad when the signed build is available.

## PencilKit direct reader — 18 November 2026

- [x] Replace the custom recognizer and shape-layer ink with `PKCanvasView` + `PKToolPicker` over the HTML reader, Pencil-only, one shared scroll source.
- [x] Migrate saved strokes to `PKDrawing`, retaining the original file. Reopened a copy of a release-marked article first: all 59 strokes migrated, original byte-identical.
- [x] Review capture places PencilKit ink correctly and excludes the palette; quote verification and delivery rules unchanged.
- [x] Wait for the saved position to become reachable before enabling markup (WebKit grew the document from 1,410 to 2,863 points after load).
- [x] Simulator: 68 unit tests passed, 1 opt-in skipped; article, chapter-isolation and Quick Look UI flows passed.
- [x] Physical iPad: installed in place via SideStore; user confirmed Pencil writing works; migrated and new strokes persisted.
- [ ] Physical hands-on checklist not individually recorded: draw across a sentence and figure, scroll with the palette open, color change, highlight, erase, lasso, reopen, review capture, EPUB chapter isolation.

## 22 October implementation

User selected backup first and requires handwriting. Articles use stable PDF pages; EPUBs are deferred. Analysis stays explicit, Sonnet remains the default, and all backup versions are retained. User requested direct implementation and installation with subagents; completed checks follow below.

Follow-up: user agrees with the proposed cost approach and prioritizes Haiku quality evaluation. Investigate Jev/OpenAI Decisions only for bounded classification or anchor selection. First reading experiment should convert one EPUB/article into a stable PDF and reuse native Markup; validate math, pagination, text extraction and retained Reader identity before adding an automated converter.

Sequencing decision: articles first; EPUBs deferred. Start the reading experiment with Reader HTML rendered to a PDF that retains the original article identity. Test exact quotations, line/page wrapping, repeated passages, equations, images, and preservation of ink after reopen. Implement article listing/content retrieval and source-text association before delivery; verify a user-confirmed highlight plus note in the original Reader article and downstream Readwise. A manually imported PDF currently lacks Reader identity and does not prove that flow.

1. Finish design choices and prototype Downloaded/library tapping, the global scrolling Markups inbox, marked-page thumbnail selection, backup status, and a handwritten article/book page. Review the concrete prototype before implementation.
2. Write failing behavior tests before library changes: Downloaded starts selected, row tap opens, download completion does not present a PDF, menus remain independently usable.
3. Write failing review tests: pending items across documents, unanalyzed marks, persistent edits while scrolling, sent/skipped filtering, and ambiguous delivery never enabling duplicate sends. Verify against the real simulator UI.
4. Test changed-page selection and analysis history before implementing: unchanged pages avoid another request; changed marks become eligible; failed/cancelled analysis does not count as successful; adjacent context and multi-page passages survive. Preserve reviewed drafts and delivery identities.
5. Instrument usage and compare current Sonnet with a cheaper vision candidate on identical, user-reviewed samples of handwriting, equations, diagrams and unanchored marks. Record transcription/anchor errors, omissions, latency and actual tokens. Check model/structured-output availability before live requests. Select automatic-analysis policy only after presenting measured costs and accuracy.
6. Test backup before implementation: complete snapshot/restore preserves PDF bytes and review state; offline provider, revoked access, interrupted copy and retention never destroy the prior snapshot. Test the selected provider on the physical iPad. Choose retention and destination during design.
7. Investigate EPUB/article rendering with one representative source of each type. Test handwritten placement after reopen, rotation and any supported text resizing; verify equations/images and original Reader identity. Choose stable page rendering or persistent content anchors from the prototype.
8. For each analysis/backup pipeline, test structured start/phase/complete/failure logs with elapsed time and content-free identifiers. UI keeps a spinner and elapsed seconds running through slow phases; failed operations retain saved work. Run signed simulator checks and physical save/restore checks before an in-place device update with backup/hash verification.

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
- [x] Recover expired signing through SideStore (18 November); retain app identity and verify all 35 Documents hashes and launch.
- [ ] Verify next SideStore refresh, background renewal and Reader/Anthropic credential continuity.
- [ ] Broaden coverage for interrupted removal, account replacement, cover cache/scroll performance, VoiceOver, Dynamic Type and hardware keyboard.
- [ ] Consider automatic connection-sheet presentation on authentication failure; current errors direct the user to replace the token manually.

No native image/ink upload is promised. Recognition accuracy has no ground-truth benchmark; users review all derived text and interpretations.


## 22 October implementation checks

- [x] Implement Downloaded default, direct document opening and download without presentation.
- [x] Implement global editable pending Markups, scrolling document review, visual page selection and unanchored-note guidance.
- [x] Persist successful page fingerprints and usage; retain selected cross-page context and alternative transcriptions without duplicate delivery.
- [x] Compare Haiku/Sonnet on private saved marks; verify Haiku structured output. Retain Sonnet default pending user quality review.
- [x] Implement user-selected, versioned Files backups with checksums, restore proof, elapsed progress and source-preserving failure behavior.
- [x] Implement Reader articles as stable native PDF pages with original identity/content; preserve source quotations through layout whitespace. EPUB remains deferred.
- [x] Signed unit checks: 57 passed, one opt-in physical test skipped (58 discovered).
- [x] Simulator PDF connect/download/offline, review/send/relaunch/remove/restore and visible native ink/save/relaunch.
- [x] Corrected article inbox completion and final article delivery flow, 69.687 s.
- [x] Final safe install: all 31 Documents hashes match; all 18 baseline PDFs unchanged. Physical article render and browse checks passed, screenshots inspected, normal app launched.

Result bundles: `/tmp/paper-final-20261022.xcresult` (one initial article completion-state assertion exposed the empty-state issue); `/tmp/paper-corrected-20261022.xcresult` (corrected verification passed). No real Reader highlight has been created in this update.

Final results: `/tmp/paper-delivery-final-20261022.xcresult` contains the final 57 passing simulator unit tests plus a UI dismissal timing failure; `/tmp/paper-article-flow-verified-20261022.xcresult` verifies that corrected harness boundary and the complete article flow. `/tmp/paper-live-article-final-20261022.xcresult` contains the passing real iPad article render with explicit unavailable figures; physical browse screenshots are in `/tmp/paper-physical-verified-20261022.xcresult`. Latest durable backup: `~/Documents/Paper Backups/2026-10-22-151213`. No real Reader highlight was created.
