# Integrate Paper

Start by inspecting the adopter's project, platform, storage and signing setup. Establish whether they want the whole iPad app, Reader synchronization, native PDF Markup, or markup review inside another app. Ask for the smallest missing decision before choosing an approach. See [README.md](README.md) for setup, requirements and verification limits.

## Code map

| Path | Responsibility |
| --- | --- |
| `Paper/PaperApp.swift`, `Paper/ReadingModel.swift` | App entry and reading/library interface |
| `Paper/NativePDFPreview.swift` | Native Quick Look/Markup bridge |
| `Paper/DocumentStore.swift` | Original/working PDFs, atomic storage, removal/restore |
| `Paper/ReaderAPI.swift`, `Paper/ReaderLibraryModel.swift`, `Paper/ReaderCatalog.swift` | Reader fetch, cached catalog and reconciliation |
| `Paper/ReaderCredentials.swift` | Keychain credentials |
| `Paper/AnthropicMarkupAPI.swift`, `Paper/ReviewModel.swift`, `Paper/ReviewView.swift` | Selected-page analysis and editable review |
| `Paper/ReaderHighlightAPI.swift`, `Paper/ReviewItem.swift` | Reader text delivery and persisted draft state |
| `project.yml` | XcodeGen project definition; regenerate after target changes |

## Configuration and integration

Use the adopter's Reader token and optional Anthropic key through the in-app screens. Never bundle `.env`, a token, a signed PDF URL or a private library. `.env.example` documents the optional development provisioning script; the application does not read it. `PAPER_DEVICE_UDID` and `PAPER_TEAM_ID` must be exported for device update scripts. Set signing in Xcode and use your own team. Do not run update/provisioning scripts while merely evaluating this repository.

`Documents/Library/{UUID}/` stores immutable `source.pdf`, edited `reading.pdf`, `document.json` and optional `review.json`. `Documents/reader-catalog.json` holds catalog metadata. Recently Removed preserves the whole document folder. Preserve these semantics when extracting storage or changing paths. Keep Keychain service identity stable for an existing install; changing bundle/signing identity can strand data. Never uninstall an existing library to test an update.

For a PDF viewer extraction, take the native wrapper and storage model first, then connect them to the target app's navigation. For Reader integration, retain pagination, rate limiting, expiring-source refresh, unauthenticated signed-file downloads and validation before committing files. For analysis, keep page selection and explicit user action; drafts must remain editable before manual sending. Review the dated research in `docs/` without treating prior account observations as guarantees for a new account.

## Verify

Read [AGENTS.md](AGENTS.md) before running tests. Discover an available iPad simulator with `xcrun simctl list devices available`; run the documented signed unit tests with that destination. `scripts/reader-test-server.py` supports controlled local service tests. Confirm download, Markup save/reopen, draft persistence, removal and restore with synthetic PDFs. Use test accounts and explicit authorization before paid analysis or creating Reader highlights. Report local tests separately from physical-device behavior and live-service delivery; those were not verified during this preparation.
