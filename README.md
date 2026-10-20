# Paper

An iPad app for reading PDFs and marking them up with Apple Pencil. It uses Apple's own PDF preview (Quick Look) and its built-in Markup tools, and connects to your Readwise Reader library of PDFs.

## What it does

- **Library**: browse every PDF in your Reader account with title, author and description. Search across all three.
- **Downloaded**: PDFs you have saved to the iPad. They open offline.
- **Markup**: tap Markup in the preview and draw with your Pencil. Your marks are saved on the iPad.
- **Safe refreshes**: refreshing the Library updates titles and details only. It never deletes downloads or overwrites your markup.
- **Files import**: you can also add a PDF from the Files app.

Your original PDF is always kept untouched; marks are saved in a separate working copy. Use the preview's Share button to export a copy.

## Connecting Reader

On first launch, open the Connect screen and paste your Readwise access token (from readwise.io/access_token). It is stored in the iPad's Keychain. You can replace it later without losing downloads.

## Current limitations

- Palm marks sometimes appear even with Pencil-only drawing enabled. The cause is not yet known.
- 17 of 717 Reader PDFs have no download link. They show as unavailable, with an option to open them in Reader.
- Marks are not yet sent back to Reader or Readwise.
- The app is signed with a free Personal Team profile that expires on 27 October 2026. After that date the app must be rebuilt and reinstalled from Xcode (over the existing install, not after deleting it, so your library is kept).

## Building

Open `Paper.xcodeproj` in Xcode, choose your signing team, and run on an iPad (iPadOS 18 or later) with Developer Mode on.

## For developers and agents

See [AGENTS.md](AGENTS.md) for commands, test setup and the documentation map.
