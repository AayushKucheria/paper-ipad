# One-PDF reading experiment

## Goal

Test whether a small native iPad app provides a satisfying PDF reading and Apple Pencil experience with modest maintenance.

Reader remains the intended central library for content, notes, and highlights. The experiment saves local PDFs; Reader integration comes later.

## Scope

- Import a PDF manually and retain it in a local library.
- Read, scroll, zoom, draw, and erase with Apple's native PDF preview and Markup.
- Finish Markup and close the preview to save, then restore the annotated PDF after reopening.
- Preserve both the imported file and an immutable local original.
- Assess drawing feel on the user's actual iPad and Pencil.

## Implementation

Use `QLPreviewController` with editing enabled. Each document has an untouched `source.pdf`, an annotated working `reading.pdf`, and `document.json` containing its local ID and title. Quick Look updates the working PDF. Its edited-copy callback validates and saves the fallback copy atomically. Invalid copies leave the previous saved PDF intact.

Show import and save errors. During import, show a spinner, elapsed seconds, and “Opening your PDF.” Log import phases and edited-copy save phases with elapsed times, omitting document contents and credentials. The system preview owns Markup's editing and save interface.

## Decision rule

Continue to Reader downloads only if the on-device reading and drawing experience is satisfying. If further work requires substantial custom infrastructure, compare Apple Notes, Goodnotes, and Obsidian PDF tools on the same PDF.

## Evidence — 2026-10-20

- Confirmed by measurement: Xcode 27.1, build 27A9275, is selected and its first-launch checks pass.
- Confirmed by measurement: the iPad Air (5th generation), running iPadOS 26.7, is paired by cable. Developer Mode is enabled (updated after user setup).
- Confirmed by measurement: Xcode recognizes the user’s Personal Team, has a valid signing identity, and produced a signed device build. Paper is installed; first launch is pending manual developer-profile trust on the iPad.
- Confirmed by measurement: custom PencilKit overlays stored valid ink but failed a screenshot assertion with zero ink pixels visible. A separate canvas rendered the same drawing. The precise framework interaction was not established; that implementation was removed in favor of system Markup.
- Confirmed by measurement: the three current persistence tests pass, including immutable originals and edited-copy failure handling.
- Confirmed by measurement: the native Markup UI test passes, including visible ink before saving and after app termination and relaunch. The signed iPad build succeeds and installation is verified.
- Hypothesis: native Markup will meet the user's drawing expectations. A physical Pencil test is required.

## Deferred

Reader downloads and access to uploaded PDFs, sync folders, write-back, articles, custom margins, and advanced organization. The supplied Reader credential has not been written into source files or used by this experiment.
