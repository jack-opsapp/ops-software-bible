# Site-visit MCP / phone-choice coexistence — 2026-09-12

The MCP compatibility repair is locally integrated and independently reviewed. **The new phone choice and MCP coexistence migrations remain unapplied; site-visit write activation remains disabled.**

## Local repair and proof

OPS-Web commit `babe8ec1da3a15b417399eb872f979057278d755` contains the new additive `20260912203552_site_visit_mcp_choice_coexistence.sql`, frozen-input compatibility guards, reproducible SQL tests and curated red/green logs. It was fast-forwarded onto local main, preserving unrelated work; nothing was pushed or deployed by this task. Migration bytes and prerequisites are archived in [the pending migration index](../../migrations/README.md#p19-mcp-choice-coexistence--unapplied-local-candidate-2026-09-12).

An existing captured choice answer may be set only to its exact immutable option label or explicitly cleared. Invalid labels fail before approval. An ordinary checklist can replace a choice-bearing default without removing its options, both when creating a new checklist and editing an existing one. Choice-bearing collateral rows may only change `is_default: true -> false`; actual saved rows are compared under the existing company advisory lock followed by sorted row locks. Revisions, current actor/company authorization, exact proposal recompilation, one-transaction writes/receipts and same-key replay remain in force.

The two existing private function signatures/security/ACLs are preserved; prerequisite checks prevent accidentally creating missing functions with default grants. No new public tool schema, scope, exposure/consent pin or ninth field kind. Frozen MCP inputs still cannot author or select choice-bearing templates; unsupported edits now reject before approval. Human-led sessions and durable agents continue using the same business capability and review path.

Fresh verification:

- Baseline reproduced 11 coexistence assertion failures. The first repair then failed two independent-review forgery checks; the final actual-record guard resolves both.
- All **31 new local PostgreSQL coexistence assertions** pass, alongside the existing workflow compiler/boundary/timezone/discovery and lock-contention checks.
- All **262 existing phone/protocol/choice assertions** pass.
- All **115 workflow/read/form/approval/civil-time tests** pass, focused production TypeScript exits 0, and the same 115 tests pass again on locally integrated main.
- Independent Astra review of exact migration SHA-256 `bdeb62a50eb1b5ccf9a3a166a43d34a6c534b664dc5c896082bdcdfa203d8fc9` found no remaining scoped P1/P2 findings.

Web evidence: `docs/artifacts/phase19/choice-coexistence-verification-20260912.md`, curated raw red/green logs and `tests/sql/site-visit-mcp-choice-coexistence-run.sh`. Raw logs retain their original PostgreSQL formatting. Synthetic local clusters use Unix sockets only and no production credentials. These are bounded vertical tests, not a new repository-wide build or universal deadlock/performance proof.

## Live state is separate

Fresh read-only production proof at `2026-09-12T20:48:59Z`: no `choice_snapshot` column or v2 apply endpoint; compatibility and effect-policy rows remain zero. The installed private compiler/apply bodies and postgres-only ACLs remain unchanged. Exact JSON is [beside this report](2026-09-12-site-visit-choice-coexistence.json).

A separate Phase C rollout has since moved `app.opsapp.co` from the earlier P19 source to READY deployment `dpl_Daz1JAzsz53Rh1d493SUy4U2bNDc`, source `0334a00d80ff062ca809faaf46fba8e7c0903f34`. This task did not make that deployment. A future release must preserve this live baseline and exclude unrelated unpublished local-main changes.

## Phone custody and remaining gates

The previously signed `3f5eaffe` app is preserved but must not be installed over choice-used local data. Old Codable readers may discard choice metadata and old queue decoders reject v2 commands; an unchanged SwiftData V28 fingerprint does not establish compatibility. New source `2e46d7285170b7520ee73a7a12be0751b0713c9e` contains the reviewed choice-compatible phone implementation. Its isolated signed build is tracked in the iOS `docs/artifacts/phase19/` evidence, separate from installation or physical-device acceptance.

Device inventory readback identified a paired jPhone with OPS 3.0.5 installed. That version alone does not establish source history, pending-work custody or choice usage. No app was installed/launched and no local store was copied or altered.

Remaining explicit gates: ordered release of the phone choice migration then this compatibility repair; compatible phone installation/distribution and signed-device offline/reconnect/conflict/media acceptance; separately authorized exact company compatibility/effect and native-host actor/client/grant activation; each claimed host's prepare → OPS review → exact save → independent readback/revocation canary. A schema change invalidates effect fingerprints; do not reseal other phases or enroll broadly. Expense repairs are separately owned and excluded. No customer message, provider write, subscription change or paid API fallback occurred.
