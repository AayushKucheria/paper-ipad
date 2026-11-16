# Handoff — 21 October 2026

## Known issues / loose ends

- User plans to start reading and marking up now; local use is independent of Reader delivery verification. Sending remains a manual review/confirm flow.
- User prefers free personal-app installation over paid Developer Program membership. SideStore is the recommended candidate to investigate for on-device renewal; no migration or setup was authorized or performed. Preserve bundle/signing identity, Documents and Keychain access before attempting a switch. Existing safe update script remains available. Research links are in README.md.
- Analysis context and cost are documented in README.md: selected consecutive 1–6 page images plus original text, only on explicit analysis. Estimated US$1–$3 per 100 pages uses assumed token counts at current Sonnet 5.5 rates; actual API usage is not retained or displayed. No metering feature was requested or implemented.
- **Signing expires 28 October 2026 at 00:03:04 Helsinki** (27 October 22:03:04 UTC). Renew with `python3 scripts/update-ipad.py --renew-signing`; keep the same bundle ID and never uninstall. Paid membership is the longer-lived option.
- Real Reader passage matching, original PDF placement and downstream Readwise retrieval remain unverified. Controlled-service delivery, duplicate recovery and relaunch persistence pass. No native image/ink upload is promised.
- Older Files imports need a Reader document association before sending. Analysis and local drafts already work; six drafts are saved from the physical-device check.
- Palm marks remain unresolved; 17 PDFs previously lacked downloadable sources. Broader accessibility, interruption and performance coverage is listed in PLAN.md.

The approved library/review build is installed. All 34 unit tests and the simulator review/Markup flows pass. Real iPad Anthropic analysis and the final 717-PDF/690-cover refresh pass; screenshots inspected. Reader token and Anthropic key are in separate device Keychain services; `.env` remains ignored. Commands and key provisioning are in AGENTS.md.

Durable latest backup: `~/Documents/Paper Backups/<backup-timestamp>`, including `final/`. All 16 Library files, including the new review.json, retained their hashes after the final refresh. Private result bundles are listed in PLAN.md.

## Next logical step

Verify one user-confirmed Reader highlight and its downstream Readwise result, while keeping the 28 October signing deadline visible.
