# Paper

An iPad PDF library with native Apple Pencil Markup and a connection to Readwise Reader.

## Reading and the library

- **Library:** browse/search Reader PDFs with covers, titles, authors and descriptions.
- **Downloaded:** open offline, review markup, export the annotated PDF, or remove a download through its ••• menu.
- **Recently Removed:** restore a PDF with all its markup and drafts. Permanent deletion frees storage and clearly asks for confirmation.
- **Refresh:** cached metadata appears immediately. “Check for updates” fetches changed records; “Refresh entire catalog” also reconciles remote removals. Local work remains independent.

The original PDF stays untouched. Draw in Apple's native Quick Look/Markup; edits are saved in a separate working copy.

## Reviewing markup

1. Finish Markup and return to Downloaded. Open the PDF's ••• menu → **Review markup**.
2. Use landscape for the full PDF on the left and the draft on the right. Portrait stacks the views.
3. Choose up to six pages and tap **Analyze with Claude**. Only those page images and their source text are sent to Anthropic using your API account.
4. Check the quoted passage, handwritten transcription and labeled AI interpretation. You can edit them or add a draft manually.
5. **Confirm and send to Reader** creates a text highlight with your note on the original Reader document. Drafts and the original visual markup stay on the iPad.

Analysis can misread writing or infer the wrong connection. A diagram's interpretation is a suggestion. Reader needs a matching source passage; standalone drawings and imported PDFs without a Reader link remain local. A multi-page passage may need correction to match Reader's parsed text.

If delivery cannot be confirmed, use **Check delivery** before retrying. Sent items remain recorded after relaunch. A manual retry is available after checking Reader for duplicates.

## Connections and keys

The Reader token and Anthropic key are stored separately in the iPad's Keychain. Reader connection and AI settings let you replace them. Downloaded PDFs survive connection failures.

The ignored `.env` on the Mac is a development configuration file; it is never bundled in the app. The existing Reader token is already in the iPad's Keychain, so it need not be copied into `.env`. Anthropic usage is billed to your API account.

## Signing and updates

The current free Personal Team profile expires **28 October 2026 at 00:03 Helsinki time**. Apple limits free development profiles to seven days. The paid Apple Developer Program is an alternative for longer-lived distribution; it requires separate enrollment.

Update over the existing app. Keep the iPad unlocked and finish any Markup edits first. The update script backs up Documents, checks signing identity, installs in place, and verifies saved file hashes.

## Known limitations

- Palm strokes still sometimes appear despite Pencil-only settings; the cause is unresolved.
- Some Reader PDFs have no downloadable original and offer Open in Reader.
- Text delivery is implemented; native ink/image highlights and exact placement in Reader's original PDF view are not established by its public API.

## Development

Open `Paper.xcodeproj` in Xcode with iPadOS 18+ and Developer Mode enabled. Operational commands, tests, provisioning and storage rules are in [AGENTS.md](AGENTS.md).
