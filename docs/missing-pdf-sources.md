# Why 17 Reader PDFs have no download link

Checked against the account on 20 October 2026, using read-only requests. A fresh complete catalog returned 717 PDF records over eight pages. With `withRawSourceUrl=true`, 700 contained a download link; the other 17 omitted the `raw_source_url` field entirely.

**The missing link comes from Reader's API response. Its underlying reason is not exposed for these records.** This is not evidence that the PDFs are absent from Reader, that the user deleted them, or that all 17 have a licensing restriction.

## What their original sources reveal

These checks use the original source without Reader credentials. They explain why the original URL is usually insufficient as a fallback; they do not explain why Reader omitted its own stored-file link.

| Records | Measured original-source behavior | What that means for downloading |
| --- | --- | --- |
| 6 | `file://` paths | These reference a local file rather than an internet download. They cannot be fetched from this app's catalog. |
| 4 | HTTP 403 | The source server refused these requests. This alone does not establish whether a browser login, access policy, or automated-request protection caused it. |
| 1 | HTTP 404 | The recorded source did not resolve to an available file during this check. |
| 6 | Successful HTTP response containing HTML | These are web pages or wrappers, rather than direct PDF responses. |

The six HTML responses include a GitHub PDF preview. Requesting the same GitHub file's raw representation returned a `%PDF-` signature, so **one of the 17 has a verified public-source recovery route**. This is separate from Reader providing a stored-file URL. Other tested download links and citation metadata did not produce a PDF. The remaining 16 have no verified direct recovery route from this investigation.

The signature probe confirms PDF bytes at the GitHub route; it is not a complete download, PDFKit parsing check, or a guarantee of future availability. No original files were reuploaded and no Reader records were modified.

## What Reader documents

The [official Reader API documentation](https://readwise.io/reader_api) says source links are valid for one hour and may be empty for documents that cannot be distributed, with Wisereads previews as an example. None of these 17 records identifies its source as Wisereads discovery. The API does not provide a restriction flag or a per-record explanation. It would therefore be inaccurate to label the entire group as restricted content.

The observed import-source labels are unspecified (10), Readwise web highlighter (4), and one each from Android sharing, iOS sharing, and an in-app link save. These labels describe how the records were added, not why a stored-file link is absent.

## App wording

Use **“Reader hasn't provided a download link for this PDF. Open it in Reader.”** Keep the entry visible and preserve any already downloaded local copy. Do not label these records “deleted,” “unavailable everywhere,” or “copyright restricted.” Download availability can be checked again when the catalog refreshes.

Per-document metadata and source-probe evidence are retained separately in a private report outside the repository. Document titles, original URLs, and signed URLs are excluded from this document.
