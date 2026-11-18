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

Reading and saving markup work independently of analysis and delivery. Sending is manual; real Reader passage matching, PDF placement and downstream Readwise retrieval still need verification in this account.

## Analysis context and cost

Claude receives the complete marked-up image and original printed text for every page in your chosen range, including unmarked pages within it. Images are rendered with a longest edge of roughly 1,560 pixels; printed text is capped at 16,000 characters per page. The suggested range starts at the first detected marked page and includes up to six consecutive pages. Check **From/To** before analyzing. Each request uses those pages and extraction instructions, without earlier analysis history or other PDF pages.

Only **Analyze with Claude** calls Anthropic. Reading, drawing, editing saved drafts and sending them to Reader incur no Anthropic analysis charge. Reanalysis makes another paid request.

As checked on 21 October 2026, [Sonnet 5.5 pricing](https://platform.claude.com/docs/en/about-claude/pricing) is US$2 per million input tokens and US$10 per million output tokens. These estimates use assumed token counts, including images; they are not measured bills:

| Analysis | Assumed input / output tokens | Approximate cost, before tax |
| --- | --- | --- |
| One page | 3,000–6,000 / 500–1,500 | US$0.01–$0.03 |
| Six pages | 15,000–30,000 / 1,000–4,000 | US$0.04–$0.10 |

A starting allowance is US$1–$3 per 100 analyzed pages, with additional cost for repeated analysis. Actual usage depends on page density and returned annotations. The app currently does not retain API usage figures or show per-analysis cost.

## Connections and keys

The Reader token and Anthropic key are stored separately in the iPad's Keychain. Reader connection and AI settings let you replace them. Downloaded PDFs survive connection failures.

The ignored `.env` on the Mac is a development configuration file; it is never bundled in the app. The existing Reader token is already in the iPad's Keychain, so it need not be copied into `.env`. Anthropic usage is billed to your API account.

## Signing and updates

The current free Personal Team profile expires **28 October 2026 at 00:03 Helsinki time**. Apple limits free development profiles to seven days. The paid Apple Developer Program is an alternative for longer-lived distribution; it requires separate enrollment.

Update over the existing app. Keep the iPad unlocked and finish any Markup edits first. The update script backs up Documents, checks signing identity, installs in place, and verifies saved file hashes.

Free renewal options researched on 21 October 2026:

| Option | Renewal requirements |
| --- | --- |
| Existing Mac update script | Reconnect and renew the current installation before expiry |
| [SideStore](https://docs.sidestore.io/docs/faq) | Initial computer setup, then on-device background renewal using its local VPN; three installed apps including SideStore with a free account |
| [AltStore Classic](https://faq.altstore.io/altstore-classic/your-altstore) | Background renewal through a reachable Mac running AltServer |

SideStore and AltStore still use seven-day development profiles. SideStore is a candidate for reducing renewal effort; migration of Paper's app identity, local data and Keychain access remains untested. TestFlight requires [Developer Program membership](https://developer.apple.com/programs/whats-included/) and [builds expire after 90 days](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/). [TrollStore's supported versions](https://github.com/opa334/TrollStore) end at iPadOS 17.0; this app requires iPadOS 18+.

## Known limitations

- Palm strokes still sometimes appear despite Pencil-only settings; the cause is unresolved.
- Some Reader PDFs have no downloadable original and offer Open in Reader.
- Text delivery is implemented; native ink/image highlights and exact placement in Reader's original PDF view are not established by its public API.

## Development

Open `Paper.xcodeproj` in Xcode with iPadOS 18+ and Developer Mode enabled. Operational commands, tests, provisioning and storage rules are in [AGENTS.md](../AGENTS.md).
