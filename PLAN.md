# Experiment plan

1. [x] Verify Xcode and detect the paired iPad.
2. [x] Review import and reading layout previews; the user approved proceeding.
3. [x] Research Apple's PencilKit, PDFKit, and native Markup guidance.
4. [x] Test preservation of the original PDF, reopening edited content, invalid imports, and edited-copy failures. Confirm failures first, then implement and pass the tests.
5. [x] Implement import and the local library with logged import phases and live elapsed progress.
6. [x] Replace custom overlays with Apple's native PDF preview and Markup after visual testing exposed invisible ink in the custom integration.
7. [x] Pass the system Markup UI test: open a PDF, draw visible ink, finish editing, terminate, reopen, and verify visible ink remains.
8. [x] Build the final app for the iPad.
9. [x] Configure signing and install on the physical iPad.
10. [ ] Verify launch after the user trusts the development profile.
11. [ ] Have the user compare drawing and navigation with Apple Notes on the same PDF before expanding scope.

## Physical device status

Developer Mode is enabled. Xcode is signed into the user’s Personal Team (`<your-team-id>`), and the development certificate and provisioning profile are present. The signed build succeeds and Paper is installed. First launch is pending the iPad’s manual trust approval for the development profile; the local signature and device membership checks pass. App implementation and installation are authorized.

## Verification

- Three current persistence tests pass.
- Earlier custom-overlay tests passed data restoration, then a stronger screenshot assertion exposed invisible ink. The system Markup test retains the screenshot check.
- Native Markup UI test: passed, with visible ink after saving and relaunch. Result: `build/Logs/Test/Test-Paper-2026.10.20_17-26-56-+0300.xcresult`.
- Final signed device build: passed. Installation verified with `devicectl device info apps`. Bundle ID: `com.aayush.paper.reader`. Launch initially denied by iPadOS profile trust.
- Current Personal Team provisioning profile expires 2026-10-27 at 14:32:40 UTC; renewing the build is required after that date.
- Pencil responsiveness and palm rejection require a physical device test.
