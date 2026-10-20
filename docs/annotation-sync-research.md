# Retrieving meaning from PDF markup

Research date: 20 October 2026. Scope: keep Quick Look for reading and drawing; investigate retrieving that work through Reader or Readwise. This document proposes later work. Annotation upload is not implemented or tested against this account.

**Recommendation:** preserve the edited PDF and inspect it with PDFKit after saving. A real iPad backup contains five added `Stamp` annotations with appearance streams, with no exposed ink paths, text highlight quadrilaterals, or textual contents. For these samples, visual crops plus reviewed transcription are the useful retrieval path. Genuine text highlights, if later captured, can be tested for export into their original Reader document. Image and ink upload into Reader's native PDF notebook needs further API support or a verified alternative.

## What the public interfaces support

| Interface | Documented behavior | Consequence |
| --- | --- | --- |
| Quick Look | Saves edits in place or returns an edited copy through delegate callbacks. [Apple](https://developer.apple.com/documentation/quicklook/qlpreviewcontrollerdelegate/previewcontroller(_:editingmodefor:)) | Use these save boundaries to queue inspection. Callbacks provide files, not semantic drawing events. |
| PDFKit | Enumerates page annotations, selects text in rectangles, and renders pages. [PDFPage](https://developer.apple.com/documentation/pdfkit/pdfpage) | Inspection can run independently of the reading interface. |
| PDFKit ink and text markup | Exposes ink paths and quadrilaterals around marked text. [Ink paths](https://developer.apple.com/documentation/pdfkit/pdfannotation/paths), [quadrilaterals](https://developer.apple.com/documentation/pdfkit/pdfannotation/quadrilateralpoints) | Extraction depends on the annotation types Quick Look actually writes. |
| Reader PDF UI | Snapshot tool saves a selected PDF rectangle as an image in the Notebook. Annotated PDF download includes highlights and notes. Import currently does not recognize other apps' PDF highlights as Reader highlights. [PDF FAQ](https://docs.readwise.io/reader/docs/faqs/pdfs) | Uploading an edited PDF alone does not complete semantic synchronization. |
| Reader → Readwise | Reader highlights automatically flow to Readwise and onward to configured note applications. [Export FAQ](https://docs.readwise.io/reader/docs/faqs/exporting) | Prefer creating in Reader when a passage can be anchored there. |

### Reader API: text can return to its source

`POST /api/v3/save/` now creates a highlight with `parent_id` and matching passage `content`; optional fields include `notes`, `tags`, and `saved_using`. A passage absent from the parent content returns HTTP 400. Fetch content using `withHtmlContent=true`. Listing returns highlight parent IDs, DOM locations, and character offsets; these are not PDF page coordinates. Highlight updates accept notes and tags. The documented create/update fields offer no ink paths, PDF rectangles, image-highlight upload, PDF-byte replacement, or highlight idempotency key. [Reader API](https://readwise.io/reader_api)

This capability was announced on 18 September 2026, so earlier advice that Reader cannot create highlights through its API is out of date. [Changelog](https://docs.readwise.io/changelog)

**Unverified:** how PDF original-view selection, Reader's parsed text, repeated passages, and image-only PDFs behave with this endpoint. Public fields do not establish that an API-created highlight will paint the corresponding rectangle in Reader's original PDF view. Verify both Notebook retrieval and page placement separately.

### Readwise API: a fallback for searchable notes

`POST /api/v2/highlights/` accepts text, source title/author/URL, note, timestamp, page location, and `highlight_url`. Its `image_url` describes the source's cover, not an annotation image attachment. Creation deduplicates by title/author/text/source URL; supplying the same `highlight_url` supports updating text. Responses include modified highlight IDs. Export exposes Reader source IDs via `external_id` when the source is Reader. No documented create field attaches directly to an existing Reader document. [Readwise API](https://readwise.io/api_deets)

**Implication:** direct Readwise export can make an independently written note retrievable, with page and source context. It may create a separate source collection. Treat merging with the existing Reader-derived collection as an experiment, not a guaranteed behavior. Choose a single destination per annotation to avoid duplicates through Reader's automatic downstream sync.

Readwise also accepts annotated PDFs by upload or email and describes limitations for scanned, multi-column, and nonstandard highlight annotations. This is useful for a manual compatibility experiment, but supplies no guarantee for Quick Look marker strokes or handwriting. [PDF import](https://docs.readwise.io/readwise/docs/importing-highlights/pdf)

## What the app currently establishes

Code inspection of `Paper/NativePDFPreview.swift` and `Paper/DocumentStore.swift` at the start of this investigation showed Quick Look editing with both save callbacks and separate original/working PDFs. That establishes a place to retain edits and schedule later inspection. No live Reader highlight or downstream Readwise result was inspected for this research.

The PDF remains the authoritative visual artifact. A successful save does not establish that drawing data is available as standard `/Ink` objects, that marker strokes identify intended text, or that handwriting was converted into extractable strings.

### What Quick Look saved on this iPad

A read-only macOS Swift/PDFKit probe compared both original/working pairs in the device backup at `/tmp/paper-ipad-library-backup-20261020`. Documents are numbered anonymously; no document titles, private text, geometry values, images, raw annotation values, or drawings were logged or copied into this repository. The probe read files without writing them.

| Anonymous document | Version | Pages | File bytes | Annotation inventory |
| --- | --- | --- | --- | --- |
| 1 | Original | 66 | 377,474 | 2 `Link` |
| 1 | Edited | 66 | 484,515 | 2 `Link`, 3 `Stamp` |
| 2 | Original | 2 | 15,665 | None |
| 2 | Edited | 2 | 758,576 | 2 `Stamp` |

Across the five added annotations, PDFKit reported:

- Five appearance streams: saved graphical appearances that PDFKit can render.
- Zero exposed ink paths and zero text markup quadrilaterals.
- Zero nonempty `contents` strings: zero UTF-8 bytes of annotation text.
- Zero annotation identifiers under `/NM`, the standard annotation name key used for identity.
- Standard dictionary key names exposed for each added annotation: `/Border`, `/DA`, `/F`, `/M`, `/Name`, `/Rect`, `/Subtype`, `/T`. `/Name` is distinct from `/NM`; its presence does not establish a stable annotation ID.
- The original and edited file bytes differ for both documents; page counts are preserved.

**Measured consequence:** these five marks are standard `Stamp` annotations with rendered appearances, rather than ordinary `/Ink` paths or `/Highlight` selections. A PDFKit inventory alone cannot recover handwriting text or the user's intended quoted passages from them. Preserve their appearances and the complete PDF; crop rendered page context around each stamp before trying OCR or human review.

**Limits:** this is a sample of two documents and five added annotations, read through macOS PDFKit. No controlled per-tool sequence or visual inspection was performed, so each stamp cannot be assigned to a particular pen, marker, shape, or handwriting action. The probe did not decode appearance stream internals; those may retain additional graphical information, but editable stroke recovery is unproven. PDFKit's public dictionary view can normalize or omit underlying entries. Repeat the controlled iPad experiment below before generalizing to every Quick Look tool or OS version. Future stable identity must account for absent `/NM` IDs and possible grouping of several marks in one stamp.

## Mapping interactions without losing meaning

This table is a proposed extraction policy, pending real iPad samples.

| Saved interaction | Preserve | Proposed retrieval format |
| --- | --- | --- |
| Standard text highlight | Original annotation, quadrilaterals, page and extracted text | Matching Reader passage plus optional note; review uncertain text order. |
| Underline or strikeout | Annotation subtype and exact region | Passage plus a note naming the operation; preserve its different intent. |
| Typed/free-text annotation | Text, placement and nearby passage | Note on a matching Reader passage, or standalone Readwise note with page context. |
| Marker drawn across text | Stroke appearance and nearby page region | Candidate passage requiring confirmation; drawing across words does not prove a text selection. |
| Handwritten margin note | Original ink/PDF and contextual crop | Image plus optional reviewed transcription; use a nearby quote only when association is clear. |
| Circle, arrow, diagram or boxed region | Markup and the enclosed/pointed-to source material | Contextual image and caption. Avoid reducing a diagram to OCR text. |
| Signature, incidental mark or accidental palm stroke | Original working PDF | Keep local until explicitly included in export. |

PDF annotation `contents` can contain textual data or an alternative description; it is not automatically the quoted text under every highlight. Annotation `name` can identify an annotation within its page. Neither promises stable identifiers across every Quick Look rewrite. [Contents key](https://developer.apple.com/documentation/pdfkit/pdfannotationkey/contents), [annotation name](https://developer.apple.com/documentation/pdfkit/pdfannotationkey/name)

For scans, render the relevant region and try Apple's on-device Vision text recognition. `RecognizeDocumentsRequest` can recover structured text, including paragraphs, lists, and tables. Handwriting accuracy and supported OS versions need testing on the actual target device. Retain recognition confidence/candidates and label transcription as derived. Preserve the crop when recognition fails. [Vision document recognition](https://developer.apple.com/documentation/vision/recognizedocumentsrequest), [Apple's walkthrough](https://developer.apple.com/videos/play/wwdc2025/272/)

## Proposed local records

Keep these records independently of the refreshed Reader catalogue:

| Record | Fields and purpose |
| --- | --- |
| Document identity | Local UUID, Reader document ID, canonical source URL, Reader URL; stable association even if title or author changes. |
| PDF versions | Untouched source PDF and hash; edited PDF and hash; last known save and inspection times. Remote refresh must not replace the edited file. |
| Annotation identity | Local UUID; page index plus displayed page label; optional native annotation name; raw subtype, bounds, quadrilaterals/paths, contents, color and modification date. |
| Derived content | Quote, typed note, OCR candidate/confidence, crop path, extraction version and optional confirmed interpretation. Distinguish source words from user's words. |
| Delivery record | Destination, Reader/Readwise IDs, payload hash, attempt time, success/error, and last acknowledged remote content. |

Use a native annotation name when reliable. Otherwise reconcile geometry/content fingerprints against the prior inventory; assign a local UUID on first discovery. A fingerprint changes when ink is edited, so hashing alone cannot establish identity. Compare with the untouched source to avoid exporting pre-existing annotations as new work.

Process a stable copy after save/dismissal, away from the main UI thread. Keep the previous successful inventory until the new one is complete. If edits are flattened into page graphics or encoded in unsupported appearance streams, retain the PDF and use page/crop rendering; exact per-stroke reconstruction is then unproven.

## Delivery and retry policy

1. Persist an outbound item locally before starting a request, keyed by local annotation UUID, chosen destination, and payload version.
2. For text, extract by individual highlight quadrilaterals/lines, preserve order, then compare with Reader content. Resolve hyphenation and whitespace conservatively. Repeated passages require review because the create API exposes no explicit occurrence selector.
3. Record returned remote IDs immediately. On an ambiguous network timeout, reconcile recent remote highlights before retrying; Reader does not document an idempotency key.
4. Reuse acknowledged IDs for permitted updates. Detect user edits made in Reader before overwriting notes or tags. Display conflicts for review.
5. Keep erasures and deletions local in the first release. Automatic remote deletion should wait for stable identity and explicit conflict behavior.
6. Retry transient failures with backoff and honor HTTP 429. Show pending/error states separately from downloaded/offline status. A failed upload must never discard the PDF.

For ink images, use local export bundles first: annotated PDF, contextual PNGs, and Markdown/JSON carrying source IDs and page references. A later remote image solution needs durable storage and an authenticated retrieval design. Temporary raw PDF download URLs are unsuitable as permanent references. Markdown image links may be worth a controlled rendering experiment; the public APIs do not document these as a native image-highlight upload contract. Do not publish private document crops merely to obtain public image URLs.

## Phased implementation and proof

1. **Current library work:** sync document metadata, download on request, retain local source/edited PDFs and Reader identity. Continue using Quick Look. The real device sample confirms that preserving graphical PDF annotations is essential.
2. **Local annotation inventory:** create one controlled digital PDF and one scan. On a real iPad add a text selection highlight if offered, marker stroke, handwriting, free text, box, arrow and erasure. Save/reopen each. Record PDF annotation types and render before/after crops to verify visible preservation. Repeat a save to test identity stability.
3. **One Reader text highlight:** choose one unique source passage; create it on the original document, fetch it back, inspect Reader Notebook and original PDF view, then verify downstream Readwise. Reopen the app and retry once to prove no duplicates. Test an unmatched and a repeated passage separately.
4. **Useful handwriting retrieval:** export original images locally with page/source context. Measure OCR on the user's writing. Let the user correct transcription before posting a note; preserve images alongside text.
5. **Image round trip experiment:** inspect one Reader-created snapshot via supported list/export responses and annotated PDF download. Check what survives each export. Reproduce it only through documented writable fields; if unsupported, retain the export bundle and seek an official image-upload/geometry API before promising full fidelity.

Acceptance for later synchronization: reopening or catalogue refresh preserves all local ink; every delivered item has a source link and page context; handwriting remains visually available; Reader/Readwise retrieval is demonstrated; repeated sync does not duplicate; failures remain recoverable offline.

## Sources

Official Readwise and Apple documentation is linked beside each finding. Device measurements used the temporary `/tmp/paper-annotation-probe.swift` script and the read-only backup described above; no private document values were persisted here. No credentials, private APIs, or network writes were used. API capabilities were checked on the research date; the controlled tool and remote synchronization experiments remain future verification work.


## Follow-up: local OCR on the five saved stamps

On 20 October 2026, `scripts/inspect-markup.swift` rendered five context crops from the two preserved PDFs and ran macOS Vision `VNRecognizeTextRequest` at accurate recognition level. All five crops were visually inspected. The source files were read only; private images and transcriptions remain outside the repository in `~/Documents/Paper Backups/2026-10-20-ocr-experiment`.

Context recognition returned 5, 3, 2, 9, and 11 text lines respectively. Many were printed source text. Visible handwriting was omitted, and incorrect strings sometimes received confidence 1.0. These counts measure returned candidates, not accuracy; no ground-truth transcription was available.

A second pass drew each Stamp alone on white, using PDFAnnotation's appearance drawing, then ran the same OCR. It returned 1, 2, 0, 1, and 0 lines. Visual inspection of the second crop confirmed that printed background text was removed while the handwriting and circle remained. One previously missed handwritten word on the sample page was recovered; another short handwritten note became incorrect character strings. Ink isolation is feasible for this sample, but does not establish reliable handwriting recognition. Outputs: `~/Documents/Paper Backups/2026-10-20-ink-only-experiment`.

**Recommendation:** retain both context and isolated ink. Use the original PDF text layer for candidate quotations and the ink image for note transcription. Show both to the user for correction. Detecting what a circle encloses or an arrow points at still needs geometric/visual interpretation; a single Stamp may contain several unrelated marks. A later vision-language experiment could help with association, but was not run here. No image was publicly hosted and no remote highlight was created.

The next useful proof is a controlled page with one circle and one legible margin note, followed by a reviewed Reader passage match and delivery round trip. Measure original-PDF placement and downstream Readwise retrieval independently.


## User direction — 21 October 2026

The user prefers full-PDF context beside the review, including scrolling between pages and passages spanning pages. First target: landscape iPad. Retain separate quoted passage and note fields, and label diagram interpretation explicitly.

The baseline above used Apple's Vision OCR. A vision-language model remains the next experiment. [Anthropic's vision documentation](https://platform.claude.com/docs/en/build-with-claude/vision) supports jointly analyzing multiple labeled images, suitable for adjacent pages and isolated ink. This documents a feasible input route; it does not establish transcription quality on these samples. Compare models with human-reviewed reference transcriptions and check diagram labels, inferred relationships, and source passage matching separately. Do not present an interpretation as verbatim handwriting.

## Implemented and measured — 21 October

The shipping app uses direct Anthropic Sonnet 5.5 vision with structured JSON (`output_config.format`), selected full-page images, and original PDF text. The account's Models endpoint authenticated and listed this model. A live forced-tool request returned HTTP 400 because the model does not support forced tool_choice; structured JSON succeeded. The app validates completion status, page bounds and item size before persisting.

The actual API client produced five draft items from the earlier crop sample. A physical iPad run analyzed four saved pages and persisted six items. The screenshot was opened and inspected: full PDF/ink on the left, editable quote/transcription/interpretation on the right. This verifies the complete Keychain/render/request/decode/persist path; it is not a ground-truth accuracy benchmark. The response labels uncertain interpretation, and all fields remain reviewable.

The app implements confirmed Reader text delivery and ambiguous-send reconciliation, covered by a controlled HTTP service and persistence tests. No highlight was created in the real Reader account during verification. Native PDF placement, real matching of passages across pages and downstream Readwise retrieval remain to be verified.
