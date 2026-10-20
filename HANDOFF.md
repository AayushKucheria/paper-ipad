# Handoff — 2026-10-20

## In progress

- The user will give feedback to the next agent. Start there; implementation and installation are already authorized.
- **Paper is installed on the physical iPad Air (5th generation), iPadOS 26.7.** Developer Mode is enabled. Xcode 27.1 is signed into Personal Team `<your-team-id>`.
- Last verified launch was denied by iPadOS with an untrusted developer-profile error. Local signature verification passes and the provisioning profile includes this iPad. The user was directed to Settings → General → VPN & Device Management → their Apple Development profile → Trust/Allow. They have not confirmed that final trust step or a successful physical launch.
- Device UDID: `<your-device-udid>`. Bundle ID: `com.aayush.paper.reader`. Signed product: `build-device/Build/Products/Debug-iphoneos/Paper.app`. Build/install/launch commands are in README.md.

## Decided but not built

- Reader stays the intended central library for content, notes, and highlights. This experiment imports PDFs from Files and stores annotated PDFs locally. Reader downloads come after the reading experience earns the additional work.
- Future Reader import must download each document once, preserve its Reader ID, and never overwrite annotations or re-download documents merely because they were moved or renamed. Uploaded PDFs must be investigated rather than assumed unavailable. No verified original-file download endpoint was established this session.
- Write-back, articles, sync folders, custom margins, and advanced library organization are deferred.
- A Reader token was supplied in the conversation but was not used or persisted. Do not copy it into source, docs, commits, or logs. Credential setup will be needed when integration starts.

## Known issues / loose ends

- The current free Personal Team provisioning profile expires **2026-10-27 14:32:40 UTC**. Renew by rebuilding/reinstalling with the same bundle ID; preserve the installed app and its Documents directory.
- Actual Pencil feel, palm rejection, and physical-device save behavior remain unmeasured. The user wants simplicity: compare existing apps if this requires substantial ongoing work.
- The implemented surface is Apple's **Quick Look PDF preview with native Markup**, presented modally so its toolbar appears. A custom PDFKit/PencilKit overlay implementation captured/restored ink but showed zero ink pixels in screenshots; standalone canvases rendered the same data. Its precise framework interaction was not established. That implementation and temporary probes were removed. Avoid reviving it without evidence that native Markup cannot meet the user's needs.
- Files live in `Documents/Library/{UUID}/`: immutable `source.pdf`, editable `reading.pdf`, and `document.json`. Quick Look updates only the working PDF; the fallback edited-copy callback validates and writes atomically.
- Verification: three storage tests pass; native Markup UI test passes visible drawing, save/close, termination, relaunch, and visible restored ink. Latest successful UI result: `build/Logs/Test/Test-Paper-2026.10.20_17-26-56-+0300.xcresult`. Signed physical-device build and installation also pass. No code changes followed those checks; only signing configuration and documentation changed.
- There is no Git remote configured. Session work is committed locally.

## Next logical step

Hear the user's feedback, confirm Paper opens after profile trust, and assess the actual Pencil reading experience before adding Reader downloads.
