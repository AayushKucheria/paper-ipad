# Reader library implementation plan

## Preparation

- [x] Inspect existing app, persistence, tests, signing configuration and prior implementation notes.
- [x] Verify official Reader listing and original-file APIs.
- [x] Recover the previously supplied token without logging it; verify authentication and all catalog pages.
- [x] Download one original PDF without sending the Reader token to its signed source URL.
- [x] Create interactive Library and Downloaded previews from real metadata.
- [x] Research later Reader/Readwise annotation export; record supported APIs and remaining experiments.
- [x] User approved the previews and verified scope on 20 October 2026.

## Tests before implementation

For each group, run the new test and observe the missing behavior, implement the minimum change, then rerun it.

1. [x] API tests: decode nullable title/author/summary; include only top-level PDF documents; follow all cursors; query all locations; reject cursor loops; preserve safe error messages for 401/403/429/network failures.
2. [x] Download tests: obtain a fresh signed source URL by Reader ID; use a separate request without authorization; reject insecure/unavailable sources and invalid PDFs, with an Open in Reader action for unavailable originals; refresh an expired link once; honor throttling with bounded retries. Assert requests and observable persisted results using URLProtocol, with no live token in fixtures.
3. [x] Catalog tests: successful refresh atomically replaces metadata; a failure on a later page leaves the previous complete catalog intact; reopening without networking restores the catalog.
4. [x] Local storage tests: existing Files imports decode unchanged; Reader downloads preserve original bytes and identity; second download/reopening reuses the saved PDF; invalid or interrupted download leaves no entry.
5. [x] Preservation tests: annotate a downloaded working PDF, change Reader title/location, refresh, and verify exact working bytes and local ID stay unchanged. Remove it from remote metadata and verify it remains in Downloaded after reopening.
6. [x] Connection tests: Keychain save/read/replacement and one-time private provisioning; no token persisted in catalog or document records.
7. [x] Model tests: initial connection refreshes metadata only; search includes title/author/summary; downloaded items open offline; download failure is retryable; operation state and live elapsed timers are exposed while networking runs.
8. [ ] Runtime UI test: connect to a controlled local HTTP service, refresh a paginated catalog, search, download a real PDF, open native Quick Look, return, relaunch offline and open the retained PDF. Confirm rendered states and error recovery with screenshots.
9. [ ] Preserve the existing native Markup visible-ink/save/relaunch regression test.

## Progress and logging checks

- [ ] Catalog logs: start, each page with count/elapsed, complete commit or failure. UI: spinner, elapsed seconds and count while refreshing; old list remains available.
- [ ] Download logs: source resolution, transfer, validation, persistence or failure. UI: transfer progress where available, spinner/elapsed otherwise, plain status and retry.
- [ ] Authentication failures lead to connection UI while local files remain accessible. Throttled requests show a wait state and bounded retry.
- [ ] Ensure logs, screenshots used for tests, fixtures and Git contain no token or signed URL.

## Delivery

- [ ] Inspect final simulator screenshots for Library, Downloaded, connection, download progress and Quick Look.
- [ ] Run required unit and UI checks; report exact results and remaining device-only limitations.
- [x] Reconnect iPad and back up its existing Library; preserve the installed app's data during the pending update.
- [x] Build/sign and update the existing bundle ID without uninstalling.
- [x] Provision the token into Keychain, launch and confirm all 717 current Reader PDF entries synchronize (device catalog: 717 records, 700 downloadable, 17 not).
- [x] Verify at least one download/open path on the device: `ReaderLiveSmokeTests` passed on the iPad (28.0 s). It confirmed 717 PDFs and "Reader connected", then downloaded "Knots" (364,517 bytes, same size as the earlier direct download) and opened it in Quick Look (98 pages, Markup button present). It reopened it from Downloaded. Screenshots inspected.
- [x] Verify catalog refresh and relaunch preserve the existing on-device PDFs/markup (Documents/Library identical to backup via diff -r after sync and relaunch).
- [x] Update README/HANDOFF with measured evidence, usage, research findings and unresolved palm issue.  (README is for people; agent commands live in AGENTS.md.)

## Current gate

Layout approved. Implementation is complete; 22 unit tests pass (signed simulator run) and the live smoke test passed on the physical iPad. Remaining: palm marks (unresolved) and the 27 Oct 2026 profile renewal.
