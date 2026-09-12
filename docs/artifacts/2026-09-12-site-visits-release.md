# Site visits P19 — controlled production release

Verified 2026-09-12 UTC / September 11, 2026 local. Jackson approved the database/web rollout and compatible iPhone test build. **Database and web are live; site-visit write activation is disabled.**

## Production proof

`app.opsapp.co` serves READY deployment `dpl_4WmqWxpmkKnT7Sn2d6Ls1swrdzdj`, source `fd8591a9bccac366656223ba3a84454856821bba`, ready at `2026-09-12T00:46:09.963Z`. This release descends from the previous deployed `006b69a8a`; it contains the complete P19 source and reviewed MCP display titles, excluding unrelated unpublished local-main sidebar/search/Phase C changes. Existing deployed email, routes, dependencies and deployment configuration are preserved.

- Exact release: 115 workflow/read/form/approval/civil-time tests plus 606 protocol/runtime/rate/UI/metadata/OAuth tests passed, zero skips. Focused production and protocol TypeScript passed. Vercel's complete hosted production build passed.
- All six actual migration-ledger statements are byte-identical to the reviewed source files and their recorded SHA-256 hashes. Source and actual archive filenames are mapped in `migrations/README.md`; exact JSON evidence is beside this report.
- Independent post-install checks: 52 installed function bodies/signatures/security/execute permissions correct; 37 untouched dependencies and 33 preexisting RLS policies unchanged; canonical booking defaults/ACLs retained and public completion wrapper byte-identical; six nullable/no-default columns; 17 enabled triggers; ten postgres-only private RLS tables; four restrictive action policies.
- Immediately before and after each migration: the three stored customer-update/financial/catalog effect policies stayed unchanged, enabled unexpired financial/catalog trials stayed zero, and V22 clients/grants stayed zero. Existing seals were already stale and remain fail-closed. No reseal or trial enrollment was performed.
- New compatibility rows, effect-policy rows, proposals, corrections, phone receipts and discard receipts all read back zero. Revision triggers now maintain company-level bookkeeping but do not activate business workflows.
- After deployment, anonymous MCP access returned HTTP401 with `Cache-Control: no-store` and the unchanged 21-scope public catalogue. All three new site-visit scopes remain absent from public grant discovery. A real signed-in native Codex company-context read succeeded before and after release, retaining company source revision3. Its site-visit read correctly returned `INSUFFICIENT_SCOPE`; authority was not expanded or bypassed.

## Compatible iPhone test build

Exact source `3f5eaffebd3d81e22d9165140f3c002bc4d22edd` includes reviewed V28 and the independently verified suspension/input repairs. `xcodebuild` Release/generic iOS build exited0; the arm64 app passed `codesign --verify --deep --strict`. Signing team `X47H96M34K`, Apple Development identity, bundle `co.opsapp.ops.OPS`, version/build3.0.5. Evidence commit `3bd6611503db72f832a8bb9b0263e73b6256d199` is integrated locally.

Artifact: `/private/tmp/ops-site-visits-p19/DerivedData/Build/Products/Release-iphoneos/OPS.app`. Raw log: `/private/tmp/ops-site-visits-p19/signed-release-build-20260911.log`. iOS reproducibility/summary: `docs/artifacts/phase19/run-signed-release-build-20260911.sh` and `signed-release-build-20260911.json`. No device was overwritten, installed, archived, uploaded or App Store-released. The serial build slot was returned after completion.

## Remaining acceptance gates

1. Install/distribute the compatible phone under the appropriate device/distribution authority and verify signed-device offline, reconnect, pending-work, conflict and media recovery.
2. Separately authorize exact company compatibility/effect policy and host actor/company/client/grant enrollment. Public V22/V17 remains unselectable; deployment does not grant this authority.
3. Run each claimed native host's discovery/preparation → OPS review → exact save → independent readback/revocation canary with authorized test records. Existing company-read proof is not a site-visit write canary.

No business-record test write, provider message, customer send, subscription change or paid API fallback occurred. Production invocation costs were not measured. Preserve additive database receipt/outbox custody if application rollback is needed; do not drop these migrations or restore old booking bodies blindly. Synthetic tests do not prove universal multi-writer deadlock freedom or field-device performance.
