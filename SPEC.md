# Paper: Reader PDF library

## User experience

Keep Apple's Quick Look and native Markup for reading and drawing. Add two library views:

| View | Contents | Action |
| --- | --- | --- |
| Library | Every PDF in Reader across all locations, with title, author and description | Download a PDF, or open its existing local copy |
| Downloaded | Reader downloads and existing PDFs imported from Files | Open offline in Quick Look |

Search title, author and description. Show missing metadata honestly. Refresh on connection and when the user requests it; retain the last successful catalog for offline browsing. Use Reader's saved date for newest-first ordering, with title as a stable fallback. Do not download PDFs during catalog refresh.

A download opens only after validating and saving the PDF. Show active progress, elapsed seconds and a retryable error. Keep the library usable during operations. Quick Look retains its native drawing, save and share controls. The separate Review markup screen prepares and sends reviewed text highlights; native ink/image upload and contents/metadata panels remain deferred.

## Data preservation

- Reader document ID identifies a PDF regardless of title, author, source URL or Reader location changes.
- Catalog refresh replaces metadata only after all pages succeed. A partial or failed refresh retains the previous catalog.
- Downloaded documents have their own durable local record. Refresh, Reader deletion, moving or renaming never removes local files or overwrites edits.
- Each local document retains `source.pdf`, editable `reading.pdf`, and `document.json`. Existing local UUIDs and Files imports remain valid.
- Persist Reader ID, Reader URL and source URL with local downloads for later annotation export. Signed download URLs are temporary and are not stored as permanent references.
- Download each Reader document once. Reopening and repeated download requests reuse its existing local record; failed downloads create no usable library entry.
- Keep files in Documents rather than disposable caches. No automatic eviction. Local removal moves the complete document folder to Documents/RecentlyRemoved; restore retains markup and drafts. Permanent deletion requires explicit confirmation.

## Reader connection

Use the public Reader API over HTTPS. Store the token in this app's iOS Keychain. Provide connection/replacement UI and retain local downloads when connection fails. Provision the user's previously supplied token into their installed app without embedding it in source or the app bundle.

List `/api/v3/list/?category=pdf&limit=100` and follow every `nextPageCursor`. Include all Reader locations. Resolve a fresh `raw_source_url` with `id` and `withRawSourceUrl=true` when downloading. Fetch signed source URLs without the Reader authorization header. Treat unavailable sources, authentication failures, throttling, network failures and invalid PDFs as recoverable errors. When Reader provides no downloadable original, retain the catalog entry, explain the limitation and offer Open in Reader.

Space listing requests to respect the documented 20 requests/minute limit. Honor HTTP 429 retry information with a visible wait and bounded retry. Do not log tokens, signed URLs, PDF contents, titles or summaries.

## Progress and diagnostics

Use structured OSLog phase events with operation IDs, counts and elapsed time: catalog start/page/commit/failure, source resolution, download start/complete, PDF validation, local persistence, and Markup saves. Every network operation shows a spinner and live elapsed seconds; show received bytes or percentage when available. Use plain hints such as “Refreshing PDF titles and descriptions” and “Downloading your PDF.” Errors preserve local work and offer retry.

## Evidence checked on 20 October 2026

- **Confirmed by measurement:** existing app uses `QLPreviewController`; storage separates original and working PDFs. Existing tests cover immutable originals and saved edits.
- **Confirmed by user report:** app opens on the physical iPad; Pencil and reading experience are satisfying. Palm strokes still occur with Pencil-only settings already enabled. Cause remains unresolved; this feature does not claim to fix it.
- **Confirmed by measurement:** the previously supplied token authenticates successfully with HTTP 204. Full pagination returned **717 PDFs in eight pages**, in Later and Archive; 532 have authors and 450 have summaries.
- **Confirmed by measurement:** resolving one real PDF returned a signed source URL. Download without Reader authorization returned HTTP 200, `application/pdf`, 364,517 bytes and a `%PDF-` signature.
- **Confirmed by measurement:** physical iPad is connected over the local network, running iPadOS 26.7 with Developer Mode enabled. An initial connection reset recovered; its existing Documents/Library was copied successfully to a private local backup.
- **Documented:** original-file URLs expire after one hour and may be absent for nondistributable documents. Listing allows 20 requests/minute. [Reader API](https://readwise.io/reader_api)
- **Confirmed by measurement:** 700 of 717 records provide signed original-file URLs. The other 17 yielded no direct PDF via their original sources in this probe (six lack HTTPS sources, five failed, six returned other content). Each signed PDF still needs validation at download time.
- **Confirmed by measurement:** both saved iPad PDFs contain five added Stamp annotations with appearance streams; ordinary PDFKit fields expose no text, ink paths or highlight geometry for those marks. Handwriting/image extraction fidelity remains unverified.

## Later annotation work

Keep Quick Look for editing; inspect stable saved PDFs with PDFKit in the approved review workflow. Reader supports creating text highlights from exact matching passages on a parent document. Ink and rectangular image highlights have no documented write API. Preserve original visual meaning before attempting OCR or conversion. See [annotation research](docs/annotation-sync-research.md).

## Design review

Interactive previews: [Library](prototypes/reader-library.html), [Downloaded](prototypes/reader-downloaded.html). Six real catalog entries are shown; preview downloads are simulated. The user approved this layout and implementation on 20 October 2026.

## Library refinement — approved and implemented 21 October

Implemented user requests: white appearance, PDF covers, recoverable local removal, smarter metadata refresh, and reviewed handwritten markup extraction. Existing storage preservation rules remain mandatory. See [measured findings and proposed behavior](docs/library-improvements.md).

- Refresh: render saved metadata immediately; use `updatedAfter` for changes, merge by ID, atomically advance a start-of-request checkpoint only after complete pagination. Explicit full reconciliation handles stale remote entries. Local files remain independent. Live delta behavior is unverified.
- Covers: use the first page of local source PDFs; otherwise a cached Reader cover where available. Missing images retain a simple placeholder. PDF download is always explicit.
- Removal: export annotated PDF from a row menu, then recoverable removal; explicit permanent deletion frees space and removes markup. Recoverable removal is the default; permanent deletion requires explicit confirmation.
- Review: the full scrollable PDF beside separately editable quoted passage, handwritten note, and labeled AI interpretation. Delivery and duplicate recovery are tested with a controlled Reader service; real-account matching and downstream retrieval remain unverified.
- Progress: catalog/download logs include operation IDs, phase, counts and elapsed time; review logs include phase, page counts and elapsed time. Network operations show a spinner and elapsed seconds. Covers render off the main thread with a placeholder and bounded memory cache. Failed operations retain saved data.



## Review direction — 21 October 2026

User likes the white library with covers and per-document controls. For markup review, use the complete, independently scrollable PDF on the left and the quoted passage plus notes on the right. Support one review item spanning multiple pages. Start with landscape iPad; a separate laptop app is deferred. Narrow screens may stack the PDF above the draft.

Anthropic vision is implemented; the earlier baseline used Apple Vision OCR. Distinguish source passage, literal handwritten transcription, and AI interpretation of diagrams or other nontext marks. Label interpretations and retain the original page/ink for review. Accuracy has no ground-truth benchmark; all extracted fields require review. Multi-page Reader passage matching remains unverified.

Updated `prototypes/markup-review.html` demonstrates full-page scrolling, page navigation, a two-page passage and separate transcription/diagram interpretation fields. Browser checks passed for independent scrolling, retained draft visibility, editing, simulated sending, and a 600 px stacked layout.

## Approved implementation — 21 October

User approved implementation of the library and revised review preview, and supplied an Anthropic API key in ignored `.env`. Use direct API access with a per-user key in device-only Keychain; provision it through a temporary file, never bundle it. Existing Reader token remains in its Keychain service.

Review uses PDFKit as a read-only, scrollable context beside editable passage, handwriting transcription and labeled AI interpretation. Native Quick Look remains the editing path. User selects up to six pages per analysis, allowing multi-page passages; only those page images and source text go to Anthropic. Explain this beside Analyze. Persist drafts locally before delivery; confirmations send text to the original Reader document. Ambiguous delivery must reconcile or remain blocked against duplicate creation. Source and working PDFs remain authoritative.

Local removal uses Recently Removed with restore and explicit permanent deletion. Moving there retains all markup and draft records; storage is freed only by permanent deletion. This reversible default resolves the unanswered removal preference.


## Delivery evidence — 21 October 2026

- Renewed profile installed: expires 27 October 22:03:04 UTC / 28 October 00:03:04 Helsinki.
- Safe feature update: all 16 Documents files matched pre-install hashes. After real-device analysis, all 15 original Library files still matched; one new review.json contained six drafts and zero sent items.
- Anthropic key authenticated via Models API, provisioned through a private one-time file, consumed into Keychain (import file absent). Shipping API client exercised live with Sonnet 5.5 structured JSON. Forced tool calls were rejected by this model; output_config JSON schema succeeded.
- Physical iPad review test passed in 28.281 seconds: selected saved pages analyzed, drafts persisted, screenshot opened and inspected. Landscape PDF and fields fit side by side. No live Reader highlight created.
- 34 signed simulator unit tests pass, including incremental merge, preservation, removal/restore, malformed/truncated AI output, ambiguous delivery recovery, and reanalysis of a sent passage. Native visible-ink/save/relaunch UI test passed in 49.518 seconds.
- Reader delivery is exercised against the controlled local service. Matching and downstream Readwise retrieval in the user's real account remain unverified. Imported Files PDFs require a Reader document identity before sending; their analysis/drafts work locally.


Live cover validation: the first full refresh exposed a malformed image_url at result index 39. A content-free decoder probe confirmed the field; an API test reproduced the failure. Tolerant optional cover decoding fixed it. All 34 unit tests pass. Final physical refresh passed (717 records, 690 remote cover values), and all 16 Library files including review.json retained their hashes. Missing/invalid covers use a placeholder.
