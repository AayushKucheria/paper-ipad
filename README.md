# Paper

An iPad PDF library for reading and scribbling with Apple Pencil, connected to Readwise Reader. Keep the original PDF untouched, save native Markup in a working copy, and optionally turn selected marked pages into editable review notes with Claude.

## Try it

You need a Mac with Xcode, an iPad running iPadOS 18+, and your own Apple signing team. Readwise Reader synchronization needs your Reader account/token; Claude analysis optionally needs your own Anthropic API key and incurs usage charges.

1. Open `Paper.xcodeproj` in Xcode. Choose your signing team for the app and test targets. For a separate installation, choose your own bundle identifier; preserve the existing identity when updating an existing Paper library.
2. Choose an iPad simulator or your own connected iPad and run the Paper scheme. Hardware needs Developer Mode.
3. Connect Reader in the app; enter the optional Anthropic key in AI settings. Keys stay in separate Keychain services. Check that library entries load, then download a PDF and reopen its saved Markup.

Project/scheme discovery was checked on 16 November 2026. Running the app and simulator tests in this preparation was blocked by a local CoreSimulator/Xcode version mismatch; the steps above still need verification on a compatible Mac. No account or hardware operation was performed.

The [usage guide](docs/usage.md) describes library, review, delivery and storage behavior, with dated research and historical pricing estimates. Check your provider's current pricing. Analysis sends selected page images and source text to Anthropic; sending a reviewed note to Reader is a separate manual action. Real Reader passage matching and downstream placement remain unverified.

## Make it yours

The PDF storage, native Markup wrapper, Reader client and review workflow can be adapted independently. Read [INTEGRATE.md](INTEGRATE.md), or give your agent this prompt:

> Read INTEGRATE.md and help me adapt this project to my setup. First understand what I want and inspect my environment, then propose the smallest useful integration.

Developer commands and data-preservation rules live in [AGENTS.md](AGENTS.md). The original code is available under the [MIT License](LICENSE). Third-party dependencies and assets retain their own terms.
