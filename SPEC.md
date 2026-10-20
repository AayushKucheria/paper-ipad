# Paper: Reader PDF library

## User experience

Keep Apple's Quick Look and native Markup for reading and drawing. Add two library views:

| View | Contents | Action |
| --- | --- | --- |
| Library | Every PDF in Reader across all locations, with title, author and description | Download a PDF, or open its existing local copy |
| Downloaded | Reader downloads and existing PDFs imported from Files | Open offline in Quick Look |

Search title, author and description. Show missing metadata honestly. Refresh on connection and when the user requests it; retain the last successful catalog for offline browsing. Use Reader's saved date for newest-first ordering, with title as a stable fallback. Do not download PDFs during catalog refresh.

A download opens only after validating and saving the PDF. Show active progress, elapsed seconds and a retryable error. Keep the library usable during operations. Quick Look retains its native drawing, save and share controls. Contents, metadata panels, and annotation upload are deferred.

## Data preservation

- Reader document ID identifies a PDF regardless of title, author, source URL or Reader location changes.
- Catalog refresh replaces metadata only after all pages succeed. A partial or failed refresh retains the previous catalog.
- Downloaded documents have their own durable local record. Refresh, Reader deletion, moving or renaming never removes local files or overwrites edits.
- Each local document retains `source.pdf`, editable `reading.pdf`, and `document.json`. Existing local UUIDs and Files imports remain valid.
- Persist Reader ID, Reader URL and source URL with local downloads for later annotation export. Signed download URLs are temporary and are not stored as permanent references.
- Download each Reader document once. Reopening and repeated download requests reuse its existing local record; failed downloads create no usable library entry.
- Keep files in Documents rather than disposable caches. No automatic eviction or local-delete action in this version.

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

Keep Quick Look; inspect stable saved PDFs with PDFKit after a future extraction phase is approved. Reader supports creating text highlights from exact matching passages on a parent document. Ink and rectangular image highlights have no documented write API. Preserve original visual meaning before attempting OCR or conversion. See [annotation research](docs/annotation-sync-research.md).

## Design review

Interactive previews: [Library](prototypes/reader-library.html), [Downloaded](prototypes/reader-downloaded.html). Six real catalog entries are shown; preview downloads are simulated. The user approved this layout and implementation on 20 October 2026.
