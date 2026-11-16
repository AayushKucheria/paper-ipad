# Library improvements — initial audit 20 October 2026

The findings below motivated the approved implementation installed on 21 October. Current behavior and verification are in HANDOFF.md; historical proposal wording below describes the design stage.

Paper was rebuilt and installed in place. All 15 library files have identical SHA-256 hashes before and after installation. The app launched successfully. Its embedded profile still expires **27 October 2026, 14:32:40 UTC**; this rebuild reused the profile.

The durable backup is `~/Documents/Paper Backups/<backup-timestamp>`. `before`, `after-install`, and `library-sha256.json` retain the verification. An earlier two-document snapshot was also moved out of `/tmp`.

## Recommended changes

| Priority | Finding and evidence | Proposed change | Effort |
| --- | --- | --- | --- |
| P1 | Source-verified: `start()` always refreshes; `listPDFs` follows the full catalog without `updatedAfter`. | Load cached data immediately; incremental refresh with a durable checkpoint, plus explicit full reconciliation. | M |
| P1 | Observed: Downloaded has only Open. Source confirms no removal operation. | Per-document menu: export annotated PDF, remove, restore. Clearly explain whether markup is retained and whether storage is freed. | M |
| P1 | User-reported dark appearance; source uses adaptive system backgrounds. | Default to white library and light native reader chrome; inspect native Markup separately. | S |
| P2 | Observed: title-only rows have no covers. | Local first-page thumbnail for downloaded PDFs; remote cover when available; honest fallback. Cache images separately from authoritative PDFs. | M |
| P2 | Observed: searching “margins” shows one row but the heading still says 3 PDFs. | Count matching records; keep the library total available as secondary text. | S |
| P2 | Observed: keyboard remains open after returning from Quick Look. | Dismiss search focus when opening a PDF; preserve the query when returning. | S |

The removal proposal uses Recently Removed and explicit permanent deletion. It preserves markup until that final action, but does not free PDF storage immediately. This choice awaits the user's preference.

## Runtime coverage

Signed simulator test `ReaderLibraryFlowTests/testConnectPaginateSearchDownloadAndReopenOffline` passed. The controlled service recorded 3 list requests (two catalog pages and source resolution), one PDF transfer, and zero Reader authorization headers sent to the PDF endpoint. These are fixture measurements, not live incremental-API validation.

Four screenshots were opened and inspected in `/tmp/paper-audit-attachments`: library, download progress, native reader, and downloaded library. Result bundle: `/tmp/paper-audit-20261020.xcresult`.

| Flow/state | Coverage |
| --- | --- |
| Connect, paginate, search | Exercised by simulator UI test |
| Download, Quick Look, return | Exercised; screenshots inspected |
| Relaunch offline and reopen | Passed |
| Safe physical-device update | Backup, build, install, exact file comparison, launch passed |
| Dark appearance | User report and source inspection; no fresh dark screenshot |
| Removal, covers, review | New prototypes only |
| Landscape, Dynamic Type, VoiceOver, hardware keyboard | Not evaluated this pass |
| Palm strokes | Unresolved; simulator cannot establish Pencil/palm behavior |

This is a focused core-flow review, not a complete accessibility audit. Preserve working offline reopening, native Markup, atomic edited-copy saves, and immutable originals.

## Design review

- `prototypes/white-library.html`: white list, two real PDF covers, search/count, update progress, per-document actions, and recoverable removal. All mutations are simulated.
- `prototypes/markup-review.html`: page context, separate quote/note fields, skip and reviewed delivery. The sample is explicitly illustrative; nothing uploads.

## Incremental refresh design

Reader documents `updatedAfter`; current code does not use it. Start the checkpoint before the first page, overlap it slightly on the next request, and merge records by Reader ID only after every page succeeds. Keep the previous checkpoint/catalog on failure. An empty delta retains existing records. A new connection performs a full fetch; never merge different accounts blindly.

The documented list response has no deletion tombstone contract. An explicit full reconciliation can remove stale remote entries while retaining every local PDF and edit. Do not infer deletion from absence in an incremental response. Preserve known download availability when a delta omits temporary source URLs; resolve a fresh source only on download.

Live behavior of incremental PDF updates, deletion handling, and cover availability still needs measurement before implementation claims.

[Reader API](https://readwise.io/reader_api) documents incremental filtering, pagination, cover metadata, and text-highlight creation.

Prototype verification: Playwright exercised search, removal confirmation, restore, and simulated review submission without browser errors. At 600 px width the library had no horizontal overflow. Both desktop preview screenshots were opened and inspected (`/tmp/paper-white-preview.png`, `/tmp/paper-review-preview.png`). This validates the prototypes only; native implementation remains pending.
