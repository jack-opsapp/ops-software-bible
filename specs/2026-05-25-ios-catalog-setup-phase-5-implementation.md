# IOS Catalog Setup Phase 5 Implementation Spec

**Date:** 2026-05-25
**Status:** Approved Phase 5 implementation contract saved to the Bible. P5-20 adds a draft-only ACL hardening migration reference; no app code, Supabase write, migration apply, runtime QA, build, or test is included in this task.
**Repos in scope for this spec:** `ops-ios`, `ops-software-bible`
**Target implementation surface:** iOS Catalog Setup save path, product option authoring, and the backing Supabase RPC contract.

## Goal

Phase 5 replaces iOS client-side multi-write catalog setup commits with one atomic Supabase RPC:

```sql
public.catalog_setup_save(
  p_company_id uuid,
  p_idempotency_key text,
  p_payload jsonb
) returns jsonb
```

The RPC is the single save boundary for Catalog Setup. It must validate the complete draft, write all approved catalog/product/bundle/stock-unit changes in one database transaction, return a structured response for iOS local reconciliation, and leave no partial data behind when validation fails.

## Approved Scope

- Add the proposed `public.catalog_setup_save(p_company_id uuid, p_idempotency_key text, p_payload jsonb) returns jsonb` RPC contract.
- Prefer `SECURITY INVOKER`.
- Grant execute to `authenticated`.
- Grant execute to `anon` while OPS iOS still authenticates with Firebase JWTs that PostgREST evaluates through the anon database role.
- Revoke execute from `public`; do not use anonymous access without the Firebase bridge RLS model below.
- Validate `p_company_id = private.get_user_company_id()` inside the RPC.
- Let existing table RLS enforce company scope for each table touched by the RPC.
- Use one RPC transaction for the entire save. iOS must not orchestrate family, axis, value, variant, stock-unit, product, option, pricing, bundle, and mapping writes as separate client-side writes.
- Add/propose `public.catalog_setup_save_requests` for idempotency.
- Add/propose `public.catalog_stock_unit_events` for stock-unit lifecycle audit.
- Include Product option authoring in Phase 5:
  - `product_options`
  - `product_option_values`
  - `product_pricing_modifiers`
  - mapping product option values to catalog option values through `catalog_product_option_mappings`
- Make Product option authoring available from `ProductDetailView`.
- Reuse the same Product option authoring surface from Catalog Setup `LINKS`.
- Keep suggested add-ons/accessories separate from required bundle components.
- Keep `suggested_addon_not_priced` warning-level, not blocking.
- Use explicit `deleted_ids` in edit mode. Do not soft-delete omitted rows by default.
- Reserve Maverick Projects dev-company writes for separately approved scoped write tests. No writes are part of this spec task.

## Non-Goals And Hard Stops

- Do not edit iOS app code in this task.
- Do not apply migrations in this task.
- Do not write to Supabase in this task.
- Do not run broad builds in this task.
- Do not mark `bug_reports` fixed in this task.
- Do not clean, revert, stage, or commit unrelated dirty files.
- Do not commit this Bible spec task.
- Do not make `catalog_setup_save` a client-side multi-call workflow.
- Do not use `SECURITY DEFINER` unless PM explicitly approves a security model change after review.
- Do not soft-delete rows because they are missing from an edit payload.
- Do not let suggested add-ons affect required bundle rollup pricing.
- Do not treat Maverick Projects write-test approval as permission to write during this task.

## Current Verified State

Preflight on 2026-05-25:

- `git worktree list` from `/Users/jacksonsweet/Projects/OPS/ops-ios` showed the main checkout on `feat/vinyl-auto-order` plus sibling worktrees for books mission deck, cashflow forecast, leads rebuild, and rendered delete local-only work.
- `pgrep -xfl xcodebuild` initially failed inside the sandbox with `sysmond service not found`; rerun with process-list escalation returned no rows, so no active `xcodebuild` process was reported by the required command.
- `/Users/jacksonsweet/Projects/OPS/AGENTS.md` was read.
- `/Users/jacksonsweet/Projects/OPS/ops-ios/CLAUDE.md` was read.
- `ops-ios` status showed substantial unrelated dirty app/schema/view/test work. This spec task did not touch it.
- `ops-software-bible` status showed unrelated dirty numbered chapters, scheduled-agent prompts, migration files, and the existing 2026-05-21 catalog setup spec. This spec task did not modify those files.

Bible and live metadata verification:

- The existing Bible spec `specs/2026-05-21-ios-catalog-inventory-setup-redesign.md` already defines the stock-system setup direction, current iOS gaps, product option mapping direction, and hard stop against unapproved implementation.
- `03_DATA_ARCHITECTURE.md` already documents Schema V8 catalog setup foundation, `CatalogStockUnit`, `CatalogProductOptionMapping`, `CatalogSetupFlowSheet`, `CatalogSchemaCapabilityGate`, and the current non-atomic repository write path.
- Read-only Supabase metadata against project `ijeekuhbatykdomumfjx` confirmed these public tables currently exist with RLS enabled:
  - `catalog_items`
  - `catalog_options`
  - `catalog_option_values`
  - `catalog_product_option_mappings`
  - `catalog_stock_units`
  - `catalog_variant_option_values`
  - `catalog_variants`
  - `product_bundle_items`
  - `product_materials`
  - `product_option_values`
  - `product_options`
  - `product_pricing_modifiers`
  - `products`
- The same read-only metadata query did not return `catalog_setup_save_requests` or `catalog_stock_unit_events`; those remain proposed Phase 5 additions.
- Read-only function metadata returned `catalog_import_validate` and `catalog_import_apply`; it did not return `catalog_setup_save`, so the Phase 5 save RPC remains proposed.
- Read-only policy metadata confirmed `catalog_stock_units` and `catalog_product_option_mappings` use `company_isolation` RLS policies.

## Atomic RPC Contract

Function signature:

```sql
create or replace function public.catalog_setup_save(
  p_company_id uuid,
  p_idempotency_key text,
  p_payload jsonb
) returns jsonb
language plpgsql
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $$
-- implementation belongs in the approved migration task, not this spec task
$$;
```

Execution permissions:

```sql
revoke all on function public.catalog_setup_save(uuid, text, jsonb) from public;
grant execute on function public.catalog_setup_save(uuid, text, jsonb) to anon;
grant execute on function public.catalog_setup_save(uuid, text, jsonb) to authenticated;
```

Required behavior:

- Validate authentication before any write by checking `p_company_id = private.get_user_company_id()`.
- Treat one RPC invocation as the only commit boundary for a Catalog Setup save.
- Perform validation before writes where possible, then execute writes in dependency order inside the same database transaction.
- Return validation blockers and warnings as JSON, not raw SQL errors, when the violation is a known draft-level issue.
- Raise an exception only for unexpected invariants, corrupt payload shape, or impossible internal state.
- Return created/updated/deleted row IDs needed by iOS to reconcile local draft IDs with server IDs.
- Let public-table RLS remain active. Do not bypass RLS through `SECURITY DEFINER`.

The RPC write order must be deterministic:

1. Idempotency request lock.
2. Company/auth validation.
3. Payload validation and ID resolution.
4. Catalog family.
5. Catalog options.
6. Catalog option values.
7. Catalog variants.
8. Catalog variant option joins.
9. Catalog stock units.
10. Product rows.
11. Product options.
12. Product option values.
13. Product pricing modifiers.
14. Product materials and catalog/product mappings.
15. Product bundle items.
16. Stock-unit lifecycle events.
17. Final response persistence into `catalog_setup_save_requests`.

## RPC Payload Shape

The payload is a single JSON object. iOS may use stable client IDs inside the draft; the RPC response maps each client ID to the persisted server ID.

```json
{
  "mode": "create",
  "draft_id": "ios-local-draft-001",
  "client_schema_version": 1,
  "family": {
    "id": null,
    "client_id": "family-001",
    "name": "Vinyl membrane",
    "category_id": null,
    "unit_id": null,
    "description": null,
    "metadata": {}
  },
  "catalog_options": [
    {
      "id": null,
      "client_id": "catalog-option-thickness",
      "name": "Thickness",
      "sort_order": 0,
      "affects_stock_identity": true,
      "affects_price": true,
      "affects_recipe": true,
      "shown_on_estimate": true,
      "values": [
        {
          "id": null,
          "client_id": "catalog-value-60-mil",
          "label": "60 mil",
          "sort_order": 0,
          "metadata": {}
        }
      ]
    }
  ],
  "variants": [
    {
      "id": null,
      "client_id": "variant-60-mil-black-6ft",
      "name": "60 mil - Black - 6 ft",
      "sku": null,
      "price": null,
      "quantity": 0,
      "option_value_client_ids": [
        "catalog-value-60-mil"
      ],
      "excluded": false
    }
  ],
  "stock_units": [
    {
      "id": null,
      "client_id": "stock-unit-roll-a",
      "variant_client_id": "variant-60-mil-black-6ft",
      "unit_kind": "roll",
      "label": "Roll A",
      "lot_code": null,
      "width_value": 6,
      "width_unit": "ft",
      "original_length_value": 75,
      "remaining_length_value": 75,
      "length_unit": "ft",
      "quantity_value": 1,
      "location": null,
      "status": "full",
      "notes": null
    }
  ],
  "stock_unit_events": [
    {
      "event_id": "event-receive-roll-a",
      "stock_unit_client_id": "stock-unit-roll-a",
      "catalog_stock_unit_id": null,
      "variant_client_id": "variant-60-mil-black-6ft",
      "catalog_variant_id": null,
      "related_catalog_stock_unit_client_id": null,
      "related_catalog_stock_unit_id": null,
      "event_type": "receive",
      "from_status": null,
      "to_status": "full",
      "quantity_delta": 1,
      "remaining_length_delta": 75,
      "payload": {
        "source": "ios_catalog_setup",
        "operator_action": "receive"
      },
      "marker": "ios_catalog_setup_lifecycle",
      "notes": "Starting stock count"
    }
  ],
  "products": [
    {
      "id": null,
      "client_id": "product-vinyl-good",
      "kind": "material",
      "type": "MATERIAL",
      "name": "Vinyl membrane",
      "pricing_unit": "sqft",
      "linked_catalog_item_client_id": "family-001",
      "options": [
        {
          "id": null,
          "client_id": "product-option-thickness",
          "name": "Thickness",
          "kind": "select",
          "required": true,
          "affects_price": true,
          "affects_recipe": true,
          "sort_order": 0,
          "values": [
            {
              "id": null,
              "client_id": "product-value-60-mil",
              "label": "60 mil",
              "sort_order": 0
            }
          ]
        }
      ],
      "pricing_modifiers": [
        {
          "id": null,
          "client_id": "price-modifier-60-mil",
          "option_client_id": "product-option-thickness",
          "option_value_client_id": "product-value-60-mil",
          "modifier_kind": "add_per_unit",
          "amount": 0
        }
      ],
      "catalog_option_mappings": [
        {
          "id": null,
          "client_id": "map-axis-thickness",
          "mapping_kind": "axis",
          "catalog_option_client_id": "catalog-option-thickness",
          "product_option_client_id": "product-option-thickness"
        },
        {
          "id": null,
          "client_id": "map-value-60-mil",
          "mapping_kind": "value",
          "catalog_option_client_id": "catalog-option-thickness",
          "catalog_option_value_client_id": "catalog-value-60-mil",
          "product_option_client_id": "product-option-thickness",
          "product_option_value_client_id": "product-value-60-mil"
        }
      ],
      "bundle_items": []
    }
  ],
  "deleted_ids": {
    "catalog_options": [],
    "catalog_option_values": [],
    "catalog_variants": [],
    "catalog_variant_option_values": [],
    "catalog_stock_units": [],
    "products": [],
    "product_options": [],
    "product_option_values": [],
    "product_pricing_modifiers": [],
    "product_materials": [],
    "product_bundle_items": [],
    "catalog_product_option_mappings": []
  },
  "client_metadata": {
    "source": "ios",
    "app_version": null
  }
}
```

Required response shape:

```json
{
  "ok": true,
  "mode": "create",
  "company_id": "00000000-0000-0000-0000-000000000000",
  "idempotency_key": "ios-generated-key",
  "warnings": [],
  "blockers": [],
  "id_map": {
    "family-001": "00000000-0000-0000-0000-000000000001",
    "catalog-option-thickness": "00000000-0000-0000-0000-000000000002",
    "catalog-value-60-mil": "00000000-0000-0000-0000-000000000003",
    "variant-60-mil-black-6ft": "00000000-0000-0000-0000-000000000004",
    "stock-unit-roll-a": "00000000-0000-0000-0000-000000000005",
    "product-vinyl-good": "00000000-0000-0000-0000-000000000006"
  },
  "saved_at": "2026-05-25T00:00:00Z"
}
```

Validation failure response:

```json
{
  "ok": false,
  "warnings": [
    {
      "code": "suggested_addon_not_priced",
      "path": "products[0].bundle_items[2]",
      "message": "Suggested add-on has no pricing modifier."
    }
  ],
  "blockers": [
    {
      "code": "matrix_signature_conflict",
      "path": "variants[1].option_value_client_ids",
      "message": "Variant matrix signature already exists for this family."
    }
  ]
}
```

## RPC Validation Rules

Global validation:

- `p_company_id` must be non-null.
- `p_idempotency_key` must be non-empty after trimming and must be stable for a single save attempt.
- `p_payload` must be a JSON object.
- `mode` must be `create` or `edit`.
- Every supplied server ID must belong to `p_company_id` and must be visible through RLS.
- Every client ID within the payload must be unique across the payload.
- Every reference must resolve to either an existing server ID or a payload client ID.
- Empty strings must be normalized consistently before validation.
- Known validation outcomes must be returned in `warnings` and `blockers`.
- If any blocker exists, no catalog/product/stock rows are written.

Catalog validation:

- Family name is required.
- Catalog option names are required and unique within the family draft after normalization.
- Catalog option values are required and unique within their parent option after normalization.
- Variant option-value selections must use values from the declared family axes.
- Excluded matrix rows must not create active `catalog_variants`.
- Active matrix signatures must be unique per family.
- Matrix-signature conflicts are blocking.
- Duplicate SKU detection remains warning-level during draft review, but the RPC must not attempt a write that violates the existing active SKU database guard. If the submitted SKU cannot be persisted, return a structured validation result instead of a raw database error.

Stock-unit validation:

- `unit_kind` must be one of `roll`, `offcut`, `box`, `each`, `lot`, `pallet`, or `length`.
- `status` must be one of `full`, `partial`, `reserved`, `consumed`, or `scrapped`.
- Width, original length, remaining length, and quantity must be non-negative when present.
- Remaining length cannot exceed original length.
- Stock units must reference a valid active variant in the save payload or an existing visible variant.
- Available stock-unit statuses are `full` and `partial`.
- Reserved, consumed, and scrapped stock units must not inflate available variant quantity.
- Dimensional stock units must use compatible length/width units before the RPC mirrors area into variant availability.

Product validation:

- Product option authoring is in Phase 5 scope.
- `product_options.kind` must use the existing product option kind set: `select`, `integer`, or `boolean`.
- Select options must include valid `product_option_values`.
- `product_pricing_modifiers` writes must use the schema-aligned `modifier_kind` field.
- `product_pricing_modifiers.modifier_kind` must be one of the live enum values: `add_per_unit`, `add_flat`, `add_per_count`, or `multiply_unit_price`.
- `product_pricing_modifiers` must reference a valid product option and, when value-specific, a value belonging to that option.
- Required product options must have either an explicit default or a line-item-time selection path.
- Product materials must reference valid product, catalog item, catalog variant, and product option rows according to their existing shape constraints.

Catalog/product mapping validation:

- `axis` mappings must include catalog option and product option references and must not include catalog option value or product option value references.
- `value` mappings must include catalog option, catalog option value, product option, and product option value references.
- A `value` mapping is valid only when its axis mapping exists in the same save or already exists as an active visible row.
- Catalog option values must belong to their referenced catalog option.
- Product option values must belong to their referenced product option.
- Mapping rows must be unique according to the active axis/value uniqueness rules on `catalog_product_option_mappings`.

Bundle validation:

- Bundle child rows must use `relationship_kind = 'required'` or `relationship_kind = 'suggested'`.
- Required bundle rows participate in required package composition and required rollup pricing.
- Suggested rows are recommendations only and do not affect required rollup pricing.
- `suggested_addon_not_priced` is warning-level only.
- Suggested rows may include `suggestion_reason` and `compatibility_selector`.
- Suggested rows must not be transformed into required rows during RPC normalization.

Edit validation:

- Edit mode must load and validate the existing visible family/product graph before writing.
- Omitted rows remain untouched.
- Deletes are allowed only through explicit `deleted_ids`.
- `deleted_ids` can contain only rows owned by `p_company_id`, visible through RLS, and connected to the edited graph.
- The RPC must reject deletion of a parent row when active child rows would be orphaned unless those children are also explicitly listed in `deleted_ids` or are reassigned in the same payload.

## RPC Idempotency

Phase 5 proposes `public.catalog_setup_save_requests` as the idempotency ledger.

Minimum table contract:

```sql
create table public.catalog_setup_save_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  idempotency_key text not null,
  request_hash text not null,
  status text not null,
  response jsonb,
  error jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint catalog_setup_save_requests_status_check
    check (status in ('processing', 'succeeded', 'failed')),
  constraint catalog_setup_save_requests_company_key_unique
    unique (company_id, idempotency_key)
);
```

Idempotency behavior:

- Compute `request_hash` from a canonical representation of `p_payload`.
- Lock the `(company_id, idempotency_key)` row before writes.
- If the same key and same request hash already succeeded, return the stored response without writing again.
- If the same key exists with a different request hash, return a blocking idempotency conflict.
- If a prior attempt failed before any catalog/product writes, allow the same key and same hash to retry from the locked request row.
- Persist the final success response before transaction completion.
- Persist structured failure state only when no partial domain writes occurred.

RLS for the idempotency table:

- Enable RLS.
- Use the existing company isolation pattern.
- Grant only the access needed by the RPC and authenticated clients.
- Do not expose another company's keys, payload hashes, responses, or errors.

## RPC Security And RLS Model

Preferred function model:

- `SECURITY INVOKER`.
- `search_path` pinned to known schemas.
- `EXECUTE` granted to `authenticated`.
- `EXECUTE` granted to `anon` only for the Firebase-bridged iOS runtime path while PostgREST evaluates Firebase JWT requests under the anon database role.
- `EXECUTE` revoked from `public`.
- No service-role key in iOS.
- No client-supplied `company_id` trust without `private.get_user_company_id()` equality.
- No RLS bypass for public table writes.

Required auth gate:

```sql
if p_company_id is distinct from private.get_user_company_id() then
  return jsonb_build_object(
    'ok', false,
    'warnings', '[]'::jsonb,
    'blockers', jsonb_build_array(
      jsonb_build_object(
        'code', 'company_scope_mismatch',
        'path', 'p_company_id',
        'message', 'Company scope does not match authenticated user.'
      )
    )
  );
end if;
```

RLS model:

- The RPC writes through existing public tables as the caller database role: `authenticated` for Supabase-authenticated clients and `anon` for Firebase-bridged iOS requests.
- Company isolation policies on catalog and product tables remain the enforcement layer.
- If a row is not visible to the resolved OPS user through RLS, the RPC treats it as missing or out of scope.
- Proposed `catalog_setup_save_requests` and `catalog_stock_unit_events` must enable RLS and use the same `company_id = private.get_user_company_id()` pattern.
- The implementation must not widen grants on existing tables as a workaround for failing RLS. If a table lacks the required authenticated access, the implementation task must update grants and RLS explicitly through an approved migration.

### Firebase-Bridged iOS Runtime Access Reconciliation

P5-19 authenticated runtime QA proved the iOS app still presents Firebase JWTs to Supabase while PostgREST evaluates those requests through the `anon` database role. The app does not use the service role key, does not bypass auth locally, and still depends on OPS user resolution through `private.get_current_user_id()` and `private.get_user_company_id()`.

Source-of-truth reconciliation lives in `migrations/2026-05-26-04-catalog-setup-firebase-runtime-access.sql`. That draft mirrors the live runtime repair and must not be applied until PM approves it.

Required runtime access model while Firebase bridge remains active:

- `public.catalog_setup_save(uuid,text,jsonb)` remains `SECURITY INVOKER`, keeps `search_path = public, private, pg_temp`, and grants `EXECUTE` to both `authenticated` and `anon`.
- `catalog_setup_save` still rejects company mismatch by comparing `p_company_id` to `private.get_user_company_id()` before writes.
- `public.catalog_setup_save_requests` has RLS enabled. `anon` has `SELECT`, `INSERT`, and `UPDATE`, but the `trg_catalog_setup_save_requests_00_write_guard` trigger blocks direct table changes unless the session-local `ops.catalog_setup_save_rpc` flag is `on`.
- `public.catalog_stock_unit_events` has RLS enabled. `anon` has `SELECT` and `INSERT`; insert policy and `catalog_stock_unit_events_company_guard()` both require the event company, stock unit, variant, and related stock unit to belong to the same company.
- `public.catalog_stock_unit_events.created_by` defaults to `private.get_current_user_id()`, not `auth.uid()`, because Firebase subjects are not UUIDs and fail `uuid` casts.
- Permission bootstrap tables `user_roles`, `role_permissions`, `feature_flags`, and `feature_flag_overrides` expose `SELECT` to `anon` only. Their Firebase bridge policies resolve the current OPS user through `private.get_current_user_id()` and restrict rows to the current user's role/overrides or to feature flags visible to a resolved OPS user.
- `private` schema `USAGE` is granted to `anon` so those RLS policies and the invoker RPC can call private identity helpers. This is broader than ideal because several private functions still have default/public `EXECUTE`; PM should review private-function EXECUTE hardening separately instead of treating this migration as full hardening.

### P5-20 Private-Function ACL Hardening Draft

Source-of-truth hardening draft lives in `migrations/2026-05-26-05-catalog-setup-private-function-acl-hardening.sql`. It is draft-only and must not be applied without explicit PM approval.

Live read-only audit against `ops-app` / `ijeekuhbatykdomumfjx` confirmed:

- `private` schema `USAGE` is explicit for `anon`, `authenticated`, and `service_role`; `CREATE` is not available to those roles.
- `private.project_table_view_clean_name(text)`, `private.project_table_view_default_definition(public.project_views)`, and `private.project_table_view_sanitize_definition(jsonb)` are already owner-only.
- Every other current `private` function has direct `PUBLIC:EXECUTE` except for owner grants; some also have stale direct `anon`/`authenticated`/`service_role` grants. Because `PUBLIC` is inherited by every role, revoking `PUBLIC` removes effective `EXECUTE` from `anon`, `authenticated`, and `service_role` unless the migration grants those roles back explicitly.
- `public.catalog_setup_save(uuid,text,jsonb)` is `SECURITY INVOKER`, has `EXECUTE` for `anon`, `authenticated`, and `service_role`, and calls only `private.get_user_company_id()` directly.
- `public.catalog_stock_unit_events.created_by` defaults to `private.get_current_user_id()`.
- The P5 Firebase bridge policies on `catalog_setup_save_requests`, `catalog_stock_unit_events`, `user_roles`, `role_permissions`, `feature_flags`, and `feature_flag_overrides` directly require only `private.get_user_company_id()` and `private.get_current_user_id()`.
- Existing anon/PUBLIC RLS policies outside Catalog Setup still directly reference `private.current_user_can_edit_project(uuid)`, `private.current_user_can_view_project(uuid)`, `private.current_user_has_permission(text,text)`, `private.current_user_in_project(uuid)`, `private.current_user_is_admin()`, `private.current_user_scope_for(text)`, `private.project_table_project_id_from_text(text)`, `private.resolve_uid()`, and `private.is_spec_operator()`. Those helpers remain executable by `anon` while Firebase JWT requests continue to evaluate under the anon DB role.
- `private.is_ops_admin()` is used by authenticated-only admin policies and must not remain executable by `anon`.
- `private.refresh_spec_board_snapshot()` is the only private helper with a live direct `service_role` grant that is not part of the P5 runtime identity path.

Minimum private-function exposure while the Firebase bridge remains active:

| Function | Final direct role grants | Reason |
| --- | --- | --- |
| `private.get_user_company_id()` | `anon`, `authenticated`, `service_role` | P5 RPC company gate, company-scoped RLS, service-role callable RPC path |
| `private.get_current_user_id()` | `anon`, `authenticated`, `service_role` | Firebase bootstrap policies, stock-event `created_by` default, service-role callable RPC path |
| `private.current_user_can_edit_project(uuid)` | `anon`, `authenticated` | Existing anon/PUBLIC project and storage RLS policies |
| `private.current_user_can_view_project(uuid)` | `anon`, `authenticated` | Existing anon/PUBLIC project RLS policies |
| `private.current_user_has_permission(text,text)` | `anon`, `authenticated` | Existing anon/PUBLIC role-scope RLS policies |
| `private.current_user_in_project(uuid)` | `anon`, `authenticated` | Existing anon/PUBLIC project-scoped RLS policies |
| `private.current_user_is_admin()` | `anon`, `authenticated` | Existing anon/PUBLIC role-scope RLS policies |
| `private.current_user_scope_for(text)` | `anon`, `authenticated` | Existing anon/PUBLIC role-scope RLS policies |
| `private.project_table_project_id_from_text(text)` | `anon`, `authenticated` | Existing anon/PUBLIC project-photo and storage policies |
| `private.resolve_uid()` | `anon`, `authenticated` | Existing anon/PUBLIC Firebase user-resolution policies |
| `private.is_spec_operator()` | `anon`, `authenticated` | Existing anon/PUBLIC SPEC operator policies |
| `private.is_ops_admin()` | `authenticated` | Authenticated-only admin policies |
| `private.refresh_spec_board_snapshot()` | `service_role` | Server-side SPEC board snapshot maintenance |

All other current private functions should be owner-only after P5-20:

- `private.catalog_categories_no_cycle()`
- `private.current_user_can_assign_team_on_project(uuid)`
- `private.iv_inventory_item_tags_delete()`
- `private.iv_inventory_item_tags_insert()`
- `private.iv_inventory_items_delete()`
- `private.iv_inventory_items_insert()`
- `private.iv_inventory_items_update()`
- `private.iv_inventory_tags_delete()`
- `private.iv_inventory_tags_insert()`
- `private.iv_inventory_tags_update()`
- `private.iv_inventory_units_delete()`
- `private.iv_inventory_units_insert()`
- `private.iv_inventory_units_update()`
- `private.products_mirror_price()`
- `private.project_table_view_clean_name(text)`
- `private.project_table_view_default_definition(public.project_views)`
- `private.project_table_view_sanitize_definition(jsonb)`
- `private.recompute_project_team_member_ids(uuid)`
- `private.seed_default_project_views_for_company()`
- `private.sync_project_team_member_ids_from_tasks()`

RLS verification from the P5-20 audit:

- RLS remains enabled on `catalog_setup_save_requests`, `catalog_stock_unit_events`, `user_roles`, `role_permissions`, `feature_flags`, and `feature_flag_overrides`.
- `catalog_setup_save_requests` keeps the RPC-local write guard and anon company-isolation policy.
- `catalog_stock_unit_events` keeps select/insert anon policies, same-company stock unit and variant checks, and the company-guard trigger.
- Revoking `PUBLIC EXECUTE` is safe only with explicit grant-back statements. Without them, `authenticated` and `service_role` lose any function access they currently inherit solely through `PUBLIC`.

## Product Option Authoring

Phase 5 includes real product option authoring. It is not read-only and not web-only in the approved contract.

Authoring coverage:

- Create, edit, reorder, and delete `product_options`.
- Create, edit, reorder, and delete `product_option_values` for select options.
- Create, edit, and delete `product_pricing_modifiers`.
- Toggle or persist option semantics already supported by the schema, including `required`, `affects_price`, and `affects_recipe`.
- Map catalog axes to product options through `catalog_product_option_mappings` axis rows.
- Map catalog option values to product option values through `catalog_product_option_mappings` value rows.

Required iOS entry points for implementation:

- `ProductDetailView` must expose Product option authoring for an existing product.
- Catalog Setup `LINKS` must reuse the same authoring surface when a family is linked to a product or when a new sellable product is created from setup.

Required reuse rule:

- Product option authoring must be one domain workflow reused from both entry points. Do not create separate divergent option editors for Product detail and Catalog Setup.

## Catalog/Product Mapping Rules

`catalog_product_option_mappings` is the bridge between physical stock identity and sellable product configuration.

Axis mapping:

- One catalog axis maps to one product option.
- Both value IDs are null.
- Example: catalog `Thickness` axis maps to product `Thickness` option.

Value mapping:

- One catalog option value maps to one product option value under an existing axis mapping.
- Both value IDs are required.
- Example: catalog `60 mil` maps to product `60 mil`.

Rules:

- Mapping creation is required when a product option is derived from or synchronized with a catalog stock axis.
- A product option may exist without a catalog mapping when it is a sellable-only option such as `Corner count`.
- A catalog option may exist without a product mapping when it affects only stock identity.
- Value mappings cannot exist without a valid axis mapping.
- Mapping rows are soft-deleted only through explicit `deleted_ids`.
- Edit mode must preserve active mappings omitted from the payload.

## Bundle Required Vs Suggested Behavior

Bundle rows use `product_bundle_items.relationship_kind`.

Required behavior:

- `required` is the default legacy meaning.
- Required child products are part of the package composition.
- Required child products participate in required rollup pricing.
- Required child products are included whenever the package is selected unless the package editor explicitly removes them.

Suggested behavior:

- `suggested` rows are add-ons/accessories.
- Suggested rows can drive recommendations, prompts, or attachable line items.
- Suggested rows do not affect required rollup pricing.
- Suggested rows do not block a package from being valid when the suggested add-on has no price.
- Suggested rows may carry `suggestion_reason`.
- Suggested rows may carry `compatibility_selector` for option-aware recommendations.

Validation code:

- `suggested_addon_not_priced` must be warning-level.
- There is no blocking validation solely because a suggested add-on has no pricing modifier.

## Stock Unit Lifecycle Audit

Phase 5 proposes `public.catalog_stock_unit_events` for lifecycle audit. The current `catalog_stock_units` table stores the latest unit state; the event table records why the state changed.

Minimum event table contract:

```sql
create table public.catalog_stock_unit_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  catalog_stock_unit_id uuid not null references public.catalog_stock_units(id) on delete cascade,
  event_type text not null,
  related_catalog_stock_unit_id uuid references public.catalog_stock_units(id) on delete set null,
  from_status text,
  to_status text,
  quantity_delta numeric,
  remaining_length_delta numeric,
  payload jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  constraint catalog_stock_unit_events_type_check
    check (event_type in ('receive', 'consume', 'scrap', 'offcut_create', 'adjust', 'reserve', 'release', 'restore', 'delete'))
);
```

Audit behavior:

- Phase 5 uses canonical operator-action event types, not alias values. Do not emit `created`, `adjusted`, `reserved`, `released`, `consumed`, `scrapped`, or `deleted`.
- iOS may submit explicit `stock_unit_events` in the same payload as `stock_units` so operator actions retain notes, metadata, deltas, and source/offcut links while still saving through one RPC.
- `stock_unit_events.stock_unit_client_id` resolves through the same `id_map` as new received units and new offcuts. Existing units may also include `catalog_stock_unit_id`.
- `related_catalog_stock_unit_client_id` and `related_catalog_stock_unit_id` link an `offcut_create` event to the source roll/length unit when known.
- Event notes map to `catalog_stock_unit_events.notes`; event metadata maps to `catalog_stock_unit_events.payload`; `marker` maps to `catalog_stock_unit_events.marker`.
- Receiving purchased, returned, imported, or starting stock writes a `receive` event. This is the creation path for stock that enters available inventory.
- Consuming stock on a job writes a `consume` event with the quantity or remaining-length delta.
- Scrapping unusable stock writes a `scrap` event.
- Creating an offcut writes an `offcut_create` event on the new offcut row, with `related_catalog_stock_unit_id` pointing to the source roll/length where known. The source unit also receives an `adjust` or `consume` event for the removed length/quantity in the same transaction.
- Manual correction of quantity, length, location-relevant metadata, or status not covered by a more specific action writes an `adjust` event.
- Reserving stock writes a `reserve` event.
- Releasing a reservation writes a `release` event.
- Restoring previously consumed or scrapped stock writes a `restore` event.
- Soft-deleting a stock unit writes a `delete` event.
- Changing status writes an event that captures `from_status` and `to_status`.
- Events are append-only after creation.
- Events use the same company isolation model as `catalog_stock_units`.
- The save RPC writes stock-unit events inside the same transaction as the stock-unit state change.

## Local Draft Resume And Recovery

iOS must treat the RPC as the source of truth for committed saves while keeping local draft recovery intact.

Required local behavior for implementation:

- Local draft IDs stay stable until the RPC returns.
- iOS sends one idempotency key per save attempt and reuses it for retry of the same payload.
- If network loss occurs before a response, iOS retries the same payload with the same key.
- If the RPC returns a stored idempotent success response, iOS reconciles local IDs using `id_map` and marks the draft saved.
- If the RPC returns blockers, iOS keeps the draft editable and highlights paths from the response.
- If the RPC returns warnings only and `ok = true`, iOS saves and keeps warnings visible in post-save review.
- If the RPC reports idempotency conflict, iOS must not guess which payload won. It keeps the local draft unsaved and asks the operator to reload or resubmit with a new key.
- Local draft resume must not duplicate rows after retry.

## Edit Existing Family Behavior

Edit mode must be explicit and conservative.

Rules:

- `mode = 'edit'` requires the edited family or product server ID.
- The RPC loads the existing graph visible to the authenticated company.
- Rows omitted from the payload are preserved.
- Rows listed in `deleted_ids` are soft-deleted if they pass scope and dependency validation.
- Deleting a catalog option requires explicit deletion of dependent option values, variant joins, mappings, and affected variant rows or a valid replacement in the same payload.
- Deleting a product option requires explicit deletion of dependent option values, pricing modifiers, materials, and mappings or a valid replacement in the same payload.
- Reordering rows updates order fields only for rows present in the relevant ordered collection.
- The RPC must return which explicit deletions were applied.

Non-rule:

- Absence from the payload is not a delete signal.

## Maverick Projects Write-Test Protocol

Maverick Projects dev company is approved for scoped write tests only after the implementation task is approved. This Task 2 spec does not run those tests and does not write to Supabase.

Required protocol for the approved write-test task:

- Use only the approved Maverick Projects dev company.
- Verify the authenticated user company resolves to Maverick Projects before any write.
- Use a unique test namespace in names, SKUs, labels, notes, and idempotency keys.
- Run exactly one create-path write test for the approved payload shape.
- Run exactly one retry with the same idempotency key and identical payload to prove idempotent replay.
- Run exactly one same-key/different-payload conflict check.
- Run exactly one edit-path test that uses explicit `deleted_ids`.
- Verify required and suggested bundle pricing behavior.
- Verify `suggested_addon_not_priced` returns a warning, not a blocker.
- Verify stock-unit events are created for receive, consume, scrap, offcut creation, adjust, reserve, and release lifecycle transitions.
- Clean up only the rows created by the scoped test if PM approves cleanup in that task.
- Do not write against production/live company data outside the approved dev-company scope.

## Implementation Task Breakdown

The approved implementation should proceed in this order:

1. Add migration SQL for `catalog_setup_save_requests`, `catalog_stock_unit_events`, and `catalog_setup_save`.
2. Add RLS policies and grants for the two proposed tables.
3. Add `SECURITY INVOKER` RPC permissions: grant `authenticated`, grant Firebase-bridged `anon`, revoke `public`.
4. Implement the RPC validation layer with blocker/warning response shape.
5. Implement idempotency locking and stored-response replay.
6. Implement create-mode writes for catalog family, axes, values, variants, variant joins, stock units, products, product options, product option values, pricing modifiers, materials, mappings, and bundle items.
7. Implement edit-mode writes with explicit `deleted_ids`.
8. Implement stock-unit lifecycle event writes.
9. Add iOS repository method for the RPC call.
10. Replace Catalog Setup client-side multi-write save with the RPC commit boundary.
11. Add reusable Product option authoring for `ProductDetailView` and Catalog Setup `LINKS`.
12. Add draft resume/retry handling around idempotency keys and `id_map` reconciliation.
13. Add focused tests for RPC payload building, validation response handling, idempotent retry, explicit deletion behavior, required-vs-suggested bundle behavior, and stock-unit event handling.
14. Run the approved Maverick Projects write-test protocol only after PM approves that implementation/testing task.

## Acceptance Criteria

Phase 5 implementation is accepted only when all of these are true:

- `public.catalog_setup_save(p_company_id uuid, p_idempotency_key text, p_payload jsonb) returns jsonb` exists.
- The function is `SECURITY INVOKER`.
- `authenticated` can execute the function.
- While Firebase-bridged iOS remains active, `anon` can execute the function only through the same RLS/company-scope model; after iOS moves to Supabase Auth, PM should approve revoking `anon` execute.
- The RPC validates `p_company_id = private.get_user_company_id()`.
- RLS remains active and authoritative for company-scoped table access.
- iOS Catalog Setup save uses one RPC call, not client-side multi-write orchestration.
- `catalog_setup_save_requests` prevents duplicate creates on retry.
- Same key and same payload returns the original success response.
- Same key and different payload returns an idempotency conflict.
- Product option authoring works from `ProductDetailView`.
- The same Product option authoring workflow is reused from Catalog Setup `LINKS`.
- Product option values can be mapped to catalog option values.
- Required bundle rows drive required rollup pricing.
- Suggested add-ons/accessories stay separate from required bundle rows.
- Suggested add-ons do not affect required rollup pricing.
- `suggested_addon_not_priced` is warning-level and does not block save.
- Stock-unit receive, consume, scrap, offcut creation, adjust, reserve, and release lifecycle writes are captured in `catalog_stock_unit_events`.
- Edit mode preserves omitted rows.
- Edit mode deletes only rows listed in explicit `deleted_ids`.
- Maverick Projects scoped write tests pass when separately approved.
- No production/live company data outside the approved dev-company test scope is written by tests.

## Open PM Decisions

The original Phase 5 RPC/spec contract remains implemented, but P5-19R adds runtime-access reconciliation decisions before the Bible draft can be applied:

- This Task 2 Bible update is docs/spec only.
- Implementation requires a separate approved task.
- Migration application requires a separate approved task.
- Maverick Projects write tests require a separate approved scoped write-test task.
- Any change from `SECURITY INVOKER` to `SECURITY DEFINER` requires explicit PM approval.
- PM must decide whether to apply `migrations/2026-05-26-04-catalog-setup-firebase-runtime-access.sql`.
- PM should decide whether Mike Metcalf's P5-19 Maverick Projects user-specific catalog overrides remain runtime QA account data or become a source-controlled seed/role policy.
- PM must decide whether to apply `migrations/2026-05-26-05-catalog-setup-private-function-acl-hardening.sql`. Approval phrase: `APPROVE APPLY P5-20 PRIVATE FUNCTION ACL HARDENING`.
