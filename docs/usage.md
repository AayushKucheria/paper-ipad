# Using Paper

An iPad reading library for PDFs, Reader articles and EPUBs, with Apple Pencil writing and reviewed notes sent back to Readwise Reader.

## Read and write

**Downloaded opens first.** Tap a document's cover or title to read it offline. The ••• menu offers Review markup, Export annotated PDF and Remove download. **Library** browses Reader PDFs; the compact library shows overlapping Downloaded, Reading and Shortlist shelves plus a format filter.

**Articles and EPUBs** open in a fixed portrait reader. Put the Pencil down anywhere to write; there's no mode to enter. Apple's native tool palette gives pen, highlighter, colors, eraser and lasso. One finger scrolls, and ink stays attached to the text as you scroll. Ink and reading position are saved per article or EPUB chapter, separately from the original text. Unlocked EPUBs only. Article copies prepared as PDFs by earlier versions still open with native PDF Markup, and ink from the pre-PencilKit reader is migrated automatically with the original file kept.

**PDFs** open in Apple's Quick Look Markup. Finish with **Done** to commit your edits. Paper preserves the untouched original and saves your handwriting in a separate annotated copy. Saving works independently of AI analysis.

**Recently Removed** keeps the whole document with its markup and review drafts. Restore returns it to Downloaded. Permanent deletion explicitly asks for confirmation.

**Refresh:** cached metadata appears immediately. "Check for updates" fetches changed records; "Refresh entire catalog" also reconciles remote removals. Local work remains independent.

## Review your markup

1. Open **Markups** to scroll through pending notes across your documents, or choose **Review markup** from a document’s ••• menu.
2. For PDFs, pick page thumbnails visually, up to six at a time. For articles and EPUB chapters, Paper captures your ink with the nearby original text; the tool palette is excluded from the image. Marked pages appear first; **All pages** lets you include surrounding context or flattened marks. Newly changed marked pages are selected automatically, up to the six-page limit.
3. Tap **Analyze selected pages**. Paper sends those annotated page images and their original text to Anthropic using your API account.
4. Scroll through the resulting cards. Check and edit the quoted passage, handwriting transcription and labeled AI interpretation.
5. **Confirm and send to Reader** creates a text highlight and note on the original Reader document.

Drawings without a clear text association stay as local drafts. Choose a meaningful source passage if you want to send one; Paper keeps the quote empty when association is uncertain. The original ink stays in the annotated PDF, while Reader receives reviewed text.

Delivery requires a matching source passage and a Reader document link. If a send has an unknown outcome, use **Check delivery** before allowing a retry. Sent records survive relaunch. One user-confirmed delivery through the real Reader account and downstream Readwise retrieval still needs verification. See [Reader’s highlight API](https://readwise.io/reader_api).

## AI quality and cost

Analysis is deliberate: reading, writing and editing drafts make no Anthropic request. A wholly unchanged selection is skipped unless you choose **Reanalyze unchanged pages**. Unchanged pages selected alongside new marks are included as context. Each selected page contributes a complete image, roughly 1,560 pixels on its longest edge, and up to 16,000 characters of original text.

**AI settings** offers Sonnet and cheaper Haiku. Sonnet remains the default while Haiku’s handwriting quality is evaluated. Paper retains token usage and displays estimated request costs where supported; your provider bill is authoritative. [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing):

| Model | Input / million tokens | Output / million tokens |
| --- | ---: | ---: |
| Sonnet 5.5 | US$2 | US$10 |
| Haiku 5.5, prompts under 100,000 tokens | US$0.10 | US$0.50 |

On 22 October, a private five-crop screening cost **US$0.0019437 with Haiku** and **US$0.042184 with Sonnet**, calculated from returned token counts. A separate live structured Haiku request worked: **5,573 input / 1,033 output tokens, 14 draft items, 8.03 seconds**. These establish functioning requests and sample costs; transcription, equation, diagram and passage-matching accuracy still need a reviewed benchmark. Check every result.

## Back up your library

Open **Library actions → Backups → Choose backup folder**. Select Dropbox, iCloud Drive or another folder enabled in Files. Setup requires your folder choice.

Paper keeps dated complete copies of original and annotated PDFs, article source files, review drafts, analysis records, catalogs and Recently Removed. Copies are checked against SHA-256 checksums. Earlier versions remain available after a failed backup; retained versions use additional storage. API keys are excluded. Restore into a fresh folder is covered by tests.

After setup, backups run after native saves, when leaving review and when returning to the app. Keep Paper open until verification finishes. **Last verified copy** describes the copy in your selected folder; your cloud provider controls its upload. Check the provider’s status in Files.

## Connections and keys

The Reader token and Anthropic key are stored separately in the iPad's Keychain. Reader connection and AI settings let you replace them. Downloaded documents survive connection failures. The ignored `.env` on the Mac is development configuration and is never bundled in the app.

## Signing and updates

See the [README renewal guide](../README.md#install-on-your-ipad-and-keep-it-working) for Xcode, SideStore and other distribution choices. Update over the existing app with the same bundle/signing identity, back up first, and never uninstall a library you want to preserve.

## Known limitations

- Palm strokes sometimes appear in PDF Markup despite Pencil-only settings; the cause is unresolved.
- Some Reader PDFs have no downloadable original and offer Open in Reader.
- Reader receives text highlights and notes. Native ink/image upload and exact placement in Reader's PDF view require further API support or verification.
- EPUB delivery to Reader needs a verified canonical Reader text source.

## Development

Open `Paper.xcodeproj` in Xcode with iPadOS 18+ and Developer Mode enabled. Operational commands, tests, provisioning and storage rules are in [AGENTS.md](../AGENTS.md). See [SPEC.md](../SPEC.md), [PLAN.md](../PLAN.md) and [annotation research](annotation-sync-research.md) for scope and evidence.
