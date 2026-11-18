# Paper: Reader library

## Direct reading and library density

Paper targets Aayush’s iPad in portrait. The direct reader uses one 820-point layout and one text size. Pencil writes on the continuous article or book chapter through a PencilKit canvas (`PKCanvasView`, Pencil-only drawing policy) layered over the HTML reader, with Apple's `PKToolPicker` for pen, highlighter, colors, eraser and lasso; there is no drawing mode. Fingers scroll; one scroll offset drives both layers, so ink stays in document coordinates. Each section's `PKDrawing` is saved in the document folder after every completed stroke. Pre-PencilKit stroke files are converted on first open and kept unmodified as a recoverable copy. Markup is enabled only after WebKit reports a document height that can reach the saved position. Review captures exclude the tool picker. PDFs keep Quick Look. Reopening restores ink and position. Document backups include the ink and original source files.

- New Reader articles keep their original HTML and canonical text. The offline reading copy caches available figures and labels missing ones. Existing PDF-backed reading copies retain their native Markup route.
- Unencrypted ePubs use the publication’s spine and local assets, with ink and reading position stored per section. At the end of a section a "Next: <title> ↓" button appears, and at its start a "↑ Previous: <title>" button; both sit in a row under the navigation bar because iPadOS doesn't report the floating Pencil palette's frame. Short sections show both immediately. Section titles collapse markup whitespace. The last-read section is remembered. (An overscroll gesture was tried first and dropped: easy to miss, and its hint sat behind the palette.) Reader downloads require an available raw ePub (`withRawSourceUrl`); records with empty URLs or unreadable uploads stay listed with Open in Reader, and one malformed record never hides the rest of a page. Books and articles refresh at launch when stale (15 minutes). Files import supports local books.
- The library has independent shelf and format filters. Downloaded, Reading and Shortlist can overlap. Opening a document updates recency. Starting or finishing reading is an explicit shelf action.
- Direct reading reuses the existing review pipeline. A marked portion of the article and its nearby text become a review capture. Before any send, match the approved quote uniquely against the retained source and deliver the exact source text. Unmatched or ambiguous drafts stay local. ePub ink and drafts stay local until Paper can verify canonical text on the original Reader item.

## 22 October iteration

These requirements supersede earlier download-opening behavior. Implemented under the user’s instruction to proceed directly; verification is recorded below.

| User requirement | Direction |
| --- | --- |
| Protect annotated PDFs | Start with backup to a user-selected cloud folder, such as Dropbox. Preserve versioned annotated PDFs and recovery metadata; show last successful backup and failures. Cross-device editing is a later decision. |
| Reduce AI cost while retaining recognition quality | Measure actual usage; compare cheaper vision models on the same user-reviewed handwriting and diagram samples. Automatic analysis depends on measured cost and quality. |
| Library behavior | Open on Downloaded; tapping a downloaded PDF opens it; downloading saves without opening. |
| Review all pending marks | Add a library-wide Markups inbox and continuously scrollable editable review cards, with PDF context. Include marks awaiting analysis as well as extracted drafts; distinguish uncertain delivery from unsent drafts. |
| Select pages visually | Prototype marked-page thumbnails and selection of new/changed marked pages, with adjacent context available. Avoid requiring remembered page numbers. |
| Marks without quoted text | Preserve the mark and page context. Proposed: suggest a meaningful nearby passage for explicit confirmation; retain a local unanchored note when no passage fits. Never invent a quote. |
| EPUBs and posts | Handwriting and drawing are essential. Explain and prototype stable page layout versus ink anchored to reflowing content before choosing a rendering approach. Reader remains the proposed catalog and highlight destination. |

**Confirmed by source inspection, 22 October:** `NativePDFPreview` handles Quick Look save callbacks; edited-copy saves validate and atomically write `reading.pdf`. This establishes save-boundary behavior, not per-stroke crash protection. The earlier device/simulator results below are historical evidence, not new runs.

**Confirmed by source inspection, 22 October:** `AnthropicMarkupAPI` uses Sonnet 5.5, sends full-page JPEGs plus original printed text for every selected page, and discards response usage. `ReviewModel` accepts consecutive ranges of up to six pages; repeated analysis calls the API again before deduplicating extracted items. `MarkupPages` already detects candidate marked pages by comparing annotations with the original; robustness across all Quick Look saves is unproven.

**Confirmed by source inspection, 22 October:** `PaperApp` starts with Library selected and opens a PDF after download. Review uses an item picker. The library lives in app Documents; cloud backup is not implemented.

**Documented, checked 22 October:** [Reader API](https://readwise.io/reader_api) lists EPUB/article categories, offers HTML content retrieval, and creates highlights using matching parent text. This does not establish handwriting support or a native image-highlight upload route. [Apple Files documentation](https://support.apple.com/en-us/102238) supports Dropbox as a Files location; persistent folder access, background execution and restore must be tested for Paper. [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing) provides cheaper model and batch options; their accuracy on this user's marks is unmeasured.

**Hypotheses to test:** skipping unchanged pages reduces repeated spend; cheaper vision can handle some handwriting; contextual crops can reduce input while retaining associations. Local change detection should be tried before paying an additional model to decide what needs analysis. A model's claimed confidence alone cannot establish recognition quality.

Backup acceptance: verify a completed snapshot can restore the annotated PDF and review state; a failed or partial backup retains local data and the last complete snapshot. Tokens and API keys stay outside backups. Automatic analysis remains undecided; backup is the selected initial cloud scope.

User follow-up, 22 October: quality is the priority; test Haiku first. User agrees with local change detection, cheaper-model evaluation, stronger-model retry and measured spending before automatic analysis. “Decision models” specifically means Jev and OpenAI Decisions. [TypeSafe's 14 October release](https://typesafe.ai/blog/jev-1-14) adds experimental image input; [OpenAI Decisions](https://developers.openai.com/api/docs/guides/decisions) accepts text/images and returns bounded choices, probabilities and rubric scores. Proposed role: classify marks or rank candidate anchors, subject to evaluation; handwriting transcription and open-ended diagram descriptions still need a generative vision model.

Recommended simplest reading approach, pending user response: convert EPUB/article content into a durable, paginated PDF once and reuse existing Quick Look/Markup. Keep original content and Reader identity alongside it; zooming retains page geometry. Text size and margins are chosen before writing; later conversions create separate versions and never reposition or overwrite existing ink. Prototype one math-heavy EPUB and one article before selecting a converter. Conversion fidelity, source availability, pagination and Reader passage matching remain unverified. A Mac conversion/import experiment is the smallest proof before building automatic in-app conversion; [calibre documents PDF conversion](https://manual.calibre-ebook.com/conversion.html).

Long operations require structured OSLog events with operation IDs, phase, counts and elapsed time, plus visible elapsed progress and a plain explanation. AI usage records retain model, token counts and rate version without document text; show estimated charges separately from provider billing.

Scope decision after user delegated sequencing, 22 October: start with Reader articles; defer EPUB support. Generate a stable local PDF from Reader's own HTML content, retain that original content and the article's Reader ID, and send confirmed quotations/notes to that original article. Never create a duplicate Reader PDF merely for annotation. Preserve source text through rendering and validate candidate quotations against retained Reader text; layout page numbers are local references. Existing `ReaderHighlightAPI` already sends parent ID, quote and notes without a PDF-category restriction, but article catalog/content retrieval, rendering and matching require implementation. Reader documents downstream Readwise sync; verify one user-confirmed article highlight and note end to end before claiming it works in this account. Ink remains in the backed-up PDF; image-only marks require the separately designed anchoring/local-note path. Articles are expected to have a smaller conversion surface than complete EPUB books; fidelity still needs a representative article with equations and figures.

## User experience

Keep Apple's Quick Look and native Markup for reading and drawing. Add two library views:

| View | Contents | Action |
| --- | --- | --- |
| Library | Every PDF in Reader across all locations, with title, author and description | Download a PDF, or open its existing local copy |
| Downloaded | Reader PDFs, prepared articles and existing PDFs imported from Files | Open offline in Quick Look |
| Articles | Reader article metadata, with explicit preparation into stable pages | Read and draw in native Markup; preserve original article identity |
| Markups | Pending drafts and new/changed marked pages across local documents | Scroll through editable cards; open source context; confirm each send |

Search title, author and description. Show missing metadata honestly. Refresh on connection and when the user requests it; retain the last successful catalog for offline browsing. Use Reader's saved date for newest-first ordering, with title as a stable fallback. Do not download PDFs during catalog refresh.

Downloads validate and save without opening. Downloaded is the default pane; tapping a saved document opens its local reading copy. Show active progress, elapsed seconds and a retryable error. Keep the library usable during operations. Quick Look retains its native drawing, save and share controls. The separate Review markup screen prepares and sends reviewed text highlights; native ink/image upload and contents/metadata panels remain deferred.

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


## Implementation evidence — 22 October 2026

- **Confirmed by signed simulator tests:** 58 unit tests discovered, 57 passed and the opt-in physical article test skipped. Coverage includes versioned backup restore/hash validation and exclusion of credentials, unchanged-analysis skipping, retained selected context, transcription alternatives, measured API usage, article pagination/MathML/figure rendering and canonical original-text delivery.
- **Confirmed by runtime tests:** PDF download stays in the library; direct row opening and offline reopening work; reviewed fake-service delivery survives relaunch and removal/restore; visible native ink survives save/relaunch. Corrected article inbox completion and the final native-preview dismissal boundary passed (69.687-second article reading/review/delivery flow).
- **Confirmed by live requests:** identical five-crop screening cost $0.0019437 on Haiku and $0.042184 on Sonnet; the sample is too small and lacks user ground truth to establish equal accuracy. Sonnet remains the default, Haiku is selectable. A separate request with Paper’s structured schema/prompt completed on Haiku in 8.03 seconds, returning 14 items (5,573 input / 1,033 output tokens). Private outputs remain outside Git.
- **Confirmed by visual inspection:** exported synthetic article PDFs retain readable text, stable page breaks, right handwriting margins, a superscript, a native MathML fraction and an embedded figure. Arbitrary JavaScript-dependent equation rendering remains unverified.
- **Confirmed on the physical iPad:** the final safe installation matched all 31 pre-install Documents hashes; all 18 PDFs from the first baseline remain unchanged. Downloaded, Markups, review/page thumbnails and backup settings were exercised and screenshots inspected. A real Reader source rendered 3 pages in 0.643 seconds, preserving 1,503 source characters. Its six server-failed images appear as explicit placeholders with a prominent warning; source HTML/text remain separate. This source was a document wrapper, so representative physics-article fidelity remains distinct from the synthetic MathML/figure tests. Dropbox destination setup still requires the user’s folder choice. Native image upload and real-account Reader → Readwise delivery remain unverified.

Physical debugging evidence: a compiler warning confirmed that the callback overload of callAsyncJavaScript was not awaited; explicit completion handling fixes that race. Further typed/count diagnostics showed the live failure was the deliberate missingImages guard (11 images, six HTTP 500 sources), which XCTest misleadingly formatted as InvalidTransition. Polling sleeps succeeded. The final policy keeps readable content and labels unavailable figures in place and on the first page, while storing pristine source text for delivery matching.


## Recovery evidence — 18 November 2026

Paper migrated to SideStore on 18 November 2026. Refresh Paper before its seven-day expiry in SideStore → My Apps with Wi-Fi and LocalDevVPN connected; the Mac can be off. Background renewal remains unverified. The original bundle/team identity and all 35 Documents files were preserved, and launch succeeded. See AGENTS.md for migration and backup details. No source-code change or new build was required; SideStore re-signed the retained device build.
