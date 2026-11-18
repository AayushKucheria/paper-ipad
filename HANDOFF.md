# Handoff — 18 November 2026

## State

The PencilKit direct reader is installed on the iPad through SideStore (in-place update, `com.aayush.paper.reader`, Append Team ID off). Articles and EPUB chapters use `PKCanvasView` + Apple's tool picker over the HTML reader with one shared scroll offset; PDFs still use Quick Look. The user confirmed Pencil writing works on the device. All 59 strokes from the release-marked article migrated to `PKDrawing` with the original file kept byte-for-byte, and new strokes saved. Only `Paper-PencilKit.ipa` remains in SideStore's Files folder; older installers were removed after their Mac copies were confirmed.

Pre-update backup: `~/Documents/Paper Backups/*-before-pencilkit` (with `library-sha256.json`). Full working-tree backup taken before this wrap's merge: `~/Documents/Paper Backups/worktree-before-wrap-2026-11-18`.

This wrap published the long-running local feature work (direct reader, EPUB, backups, Markups inbox, shelves, PencilKit) onto the public-release commits without undoing their privacy cleanup. Owner device/team values now live in the ignored `.env.device`; device scripts read `PAPER_DEVICE_UDID`/`PAPER_TEAM_ID`. `scripts/package-ipa.py` replaces the `ditto` packaging that produced SideStore's `._Paper.app` rejection.

## 19 November fixes (staged, awaiting install)

- Article analysis "incomplete": Paper sent region ids like 100001 and the model answered pages [1], failing validation. Now sends 1..n and maps back; failure reasons are logged (OSLog `analysis-api`/`analysis-decode`). Confirmed with two real API calls.
- EPUB: finger overscroll (80 pt) past a section edge opens the next/previous section; Pencil never navigates; last section remembered.
- Reader EPUBs never loaded: some records have `source_url: ""`, which failed the whole page decode. URLs now decode leniently, bad records are skipped and logged, books/articles refresh at launch when stale.
- Reader and Anthropic credentials verified after the SideStore migration.
- Simulator: 72 unit tests (2 opt-in skipped) and all ReaderLibraryFlowTests/ReadingFlowTests passed. UI tests need `python3 scripts/reader-test-server.py` running on 18767; stop stale copies first, they serve old fixtures.
- `Paper-EPUB-Analysis-Fix.ipa` is staged in SideStore's Files (hash-verified). Pre-update backup: `~/Documents/Paper Backups/2026-11-19-000148-before-epub-analysis-fix`. After install: compare library hashes, re-check analysis/EPUB scroll/Books on device, remove `Paper-PencilKit.ipa` from SideStore Files.

## Known issues / loose ends

- Physical PencilKit checklist passed 18 Nov (draw, scroll with palette, color, highlight, erase, lasso, reopen); EPUB scrolling issue found and fixed above.
- SideStore background renewal and Reader/Anthropic Keychain continuity after migration are still unverified; refresh manually every few days with Wi-Fi + LocalDevVPN.
- Real Reader passage matching, PDF placement and downstream Readwise retrieval need one user-confirmed end-to-end send. EPUB delivery needs a verified canonical Reader text source.
- In-app Files backup destination still needs choosing on the device.
- Palm strokes in PDF Markup, 17 PDFs without download sources, and broader accessibility/performance coverage remain open.
- README demo (docs/demo.mp4, demo.gif) and screenshots show only the PDF Markup flow on synthetic documents; they predate the PencilKit reader. A demo of direct article writing would match the current app better.
- Published history was rewritten for privacy; the previous repository stays a private archive. Never merge archived history back. The owner checkout has a local pre-push guard against reintroducing historical private data.

## Next logical step

Install the staged build, then verify analysis, EPUB section scrolling and Reader Books on the iPad; then record the README demo.
