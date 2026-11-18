# Reader PDF library: API verification

Checked on 20 October 2026 against the official [Reader API documentation](https://readwise.io/reader_api) and the user's account. All account requests in this investigation were read-only. PDF testing downloaded one original file; no Reader documents or highlights were changed.

## Verified account behavior

| Measurement | Result |
| --- | --- |
| Existing token authentication | HTTP 204 |
| Complete PDF catalog | 717 documents over eight pages |
| Locations returned | Later and Archive |
| Author present | 532 documents |
| Summary present | 450 documents |
| Signed original-file URL present | 700 of 717 documents |
| One original-file download | HTTP 200, application/pdf, 364,517 bytes |
| PDFKit validation of downloaded sample | 98 pages, unlocked |

A raw source URL was absent on 17 records. Testing their original source URLs found six without an HTTPS source, five unavailable sources, and six non-PDF responses; none yielded a direct public PDF in this probe. Keep these entries visible with an explanation and Open in Reader action. The other 700 signed URLs were checked for presence, not individually downloaded or PDF-validated.

## API contract and implementation decisions

List `category=pdf`, leave location unrestricted, and follow `nextPageCursor` using `pageCursor`. Use title, author and summary for display. Retain Reader IDs independently of metadata.

`withRawSourceUrl=true` returns a signed original-source URL valid for one hour. Request a fresh URL by document ID immediately before downloading. An absent source is a supported case. Fetch the signed URL without the Reader token, validate the PDF, then commit the local record. The raw original is not documented as containing Reader's annotations.

Listing permits 20 requests per minute per token. Space requests, honor retry responses and show elapsed progress. Keep credentials and signed URLs out of logs, fixtures, repository files and permanent catalog records.

## Local runtime evidence

The iPad's existing Documents/Library was backed up successfully after a transient network connection reset. The backup contains two saved PDFs and their local records. Both working PDFs retain additional visual annotations; see [annotation research](annotation-sync-research.md). No production source was changed during this verification.

## Sources

- [Reader API](https://readwise.io/reader_api)
- [Reader PDF FAQ](https://docs.readwise.io/reader/docs/faqs/pdfs)
- [Apple PDFDocument](https://developer.apple.com/documentation/pdfkit/pdfdocument)

## EPUB catalog (18 Nov 2026)

- `GET /api/v3/list/?category=epub&withRawSourceUrl=true` is documented (`category` accepts `epub`; `withRawSourceUrl` adds `raw_source_url`, an S3 link valid for one hour, empty for non-distributable files). Pagination uses `nextPageCursor`/`pageCursor`; limit 1 to 100; 20 requests per minute.
- Observed EPUB record shapes: `source_url` is `""` for uploads Reader could not parse and `private://read/<id>` otherwise; `author` and `image_url` can be `""`; `title` can be null.
- Cause of the empty Books shelf: Swift's `URL` decoder throws on `""`, so one unparseable upload failed the whole page as "incomplete library response" and `reader-books.json` was never written. URL fields now decode leniently and a single undecodable record is skipped (logged as `reading_catalog_skipped`) instead of failing the page. Failures log `kind=<ReaderAPIError case>` without token or content.
