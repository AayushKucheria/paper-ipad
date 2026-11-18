# Handoff — 18 November 2026

## State

The PencilKit direct reader is installed on the iPad through SideStore (in-place update, `com.aayush.paper.reader`, Append Team ID off). Articles and EPUB chapters use `PKCanvasView` + Apple's tool picker over the HTML reader with one shared scroll offset; PDFs still use Quick Look. The user confirmed Pencil writing works on the device. All 59 strokes from the release-marked article migrated to `PKDrawing` with the original file kept byte-for-byte, and new strokes saved. Only `Paper-PencilKit.ipa` remains in SideStore's Files folder; older installers were removed after their Mac copies were confirmed.

Pre-update backup: `~/Documents/Paper Backups/*-before-pencilkit` (with `library-sha256.json`). Full working-tree backup taken before this wrap's merge: `~/Documents/Paper Backups/worktree-before-wrap-2026-11-18`.

This wrap published the long-running local feature work (direct reader, EPUB, backups, Markups inbox, shelves, PencilKit) onto the public-release commits without undoing their privacy cleanup. Owner device/team values now live in the ignored `.env.device`; device scripts read `PAPER_DEVICE_UDID`/`PAPER_TEAM_ID`. `scripts/package-ipa.py` replaces the `ditto` packaging that produced SideStore's `._Paper.app` rejection.

## Known issues / loose ends

- Physical hands-on checklist not individually recorded: draw across a sentence and a figure, scroll with the palette open, change color, highlight, erase, lasso, reopen (ink + position), review capture, EPUB chapter isolation.
- SideStore background renewal and Reader/Anthropic Keychain continuity after migration are still unverified; refresh manually every few days with Wi-Fi + LocalDevVPN.
- Real Reader passage matching, PDF placement and downstream Readwise retrieval need one user-confirmed end-to-end send. EPUB delivery needs a verified canonical Reader text source.
- In-app Files backup destination still needs choosing on the device.
- Palm strokes in PDF Markup, 17 PDFs without download sources, and broader accessibility/performance coverage remain open.
- README demo (docs/demo.mp4, demo.gif) and screenshots show only the PDF Markup flow on synthetic documents; they predate the PencilKit reader. A demo of direct article writing would match the current app better.
- Published history was rewritten for privacy; the previous repository stays a private archive. Never merge archived history back. The owner checkout has a local pre-push guard against reintroducing historical private data.

## Next logical step

Run the physical PencilKit checklist on the iPad and record results in PLAN.md.
