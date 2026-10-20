# Paper

A small native iPad PDF reader using Apple's built-in PDF preview and Markup. Reader downloads are deferred until the reading experience is proven.

## Use

1. Choose a PDF from Files, or try the included sample.
2. Tap **Markup** in the preview to write with your Pencil and use Apple's drawing tools.
3. Finish Markup and close the preview to save edits.
4. Close the preview to return to your local library. The last document opens again when you relaunch.

The app keeps two files per imported document under Documents/Library:

| File | Purpose |
| --- | --- |
| `source.pdf` | Untouched original |
| `reading.pdf` | Your PDF with saved Markup |
| `document.json` | Local ID and title |

The file you imported from Files is preserved. Your working PDF contains the saved annotations; edits stay on this iPad. Keep the app installed to retain its local library. Use the native preview's Share action to export a copy. Reader write-back is future work.

## Build

Open `Paper.xcodeproj` in Xcode, select your signing team under the Paper target's Signing & Capabilities, and run on an iPad with Developer Mode enabled. The project targets iPadOS 18 or later.

The app is installed on the user's iPad. The last verified launch was blocked by developer-profile trust. On first launch, trust the Apple Development profile under Settings → General → VPN & Device Management. Developer Mode is already enabled.

The current Personal Team build's provisioning profile expires on **27 October 2026**. Rebuild and reinstall using the same bundle ID to renew it and preserve the app's local library; do not uninstall to renew.

To rebuild and install from this Mac:

```sh
xcodebuild build -project Paper.xcodeproj -scheme Paper \
  -destination 'id=<your-device-udid>' -derivedDataPath build-device \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration
xcrun devicectl device install app --device <your-device-udid> \
  build-device/Build/Products/Debug-iphoneos/Paper.app
xcrun devicectl device process launch --device <your-device-udid> \
  com.aayush.paper.reader
```

`project.yml` is the project definition. After changing target configuration, run `xcodegen generate` (requires XcodeGen).

```sh
xcodebuild test -project Paper.xcodeproj -scheme Paper \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO
```

Persistence tests protect the source file and verify saved edits and failure handling. The UI test opens native Markup, draws, saves, and checks visible ink after relaunch. A physical iPad and Pencil are needed to assess drawing feel and palm rejection.

## References

- [Apple: PDF preview editing and save callbacks](https://developer.apple.com/documentation/quicklook/qlpreviewcontrollerdelegate/previewcontroller%28_%3Aeditingmodefor%3A%29)
- [Apple: File management and Quick Look](https://developer.apple.com/videos/play/wwdc2019/719/)
- [Apple: PDFKit page overlays](https://developer.apple.com/videos/play/wwdc2022/10089/)
- [Apple: PencilKit tool picker](https://developer.apple.com/videos/play/wwdc2024/10214/)
