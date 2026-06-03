# Recommended Direction

**Date:** 2026-05-21  
**Project:** IOS CATALOG SETUP - P1-1  
**Status:** Draft planning spec - no implementation approved  
**Repos in scope:** `ops-ios`, `ops-software-bible`, `ops-design-system/project`  
**Hard stop:** UX and data workflow planning only. This spec does not apply migrations, edit production data, mark bugs fixed, or start implementation.

Build a guided, material-family-agnostic **Stock System Setup** workflow inside the existing iOS `CATALOG` tab. The workflow must support vinyl membrane as a proving case without hardcoding vinyl. The same model must also work for rail, flashing, fasteners, glue, boards, clips, boxes, tubes, pallets, leftover lengths, and other company-specific materials.

The current Supabase schema already supports the core catalog concepts: stock families, catalog attributes/options, option values, variants, variant option joins, products, product options, product option values, pricing modifiers, recipes, product bundles, and product-to-stock links. The current iOS app can view and lightly manage many of those records, but it does not provide a field-ready setup flow for building the system from nothing.

The main missing data concept is a generic physical stock-unit layer under `catalog_variants`. Variant-level quantity is not enough for roll materials because crews need to track full rolls and offcuts by actual width and remaining length.

## Confirmed Planning Decisions

- Vinyl membrane is stock, not a special app feature.
- Vinyl is only an example; no vinyl-specific code, table, enum, copy, or workflow should be hardcoded.
- Attributes can affect stock identity, price, recipe, or any combination.
- Stock setup needs to handle physical roll dimensions and offcuts.
- Default membrane roll length is 75 ft, but partial shop offcuts must be trackable.
- A "vinyl system" is a product bundle example. Rail systems, flashing kits, starter kits, and company-specific material systems should use the same mechanism.
- Add-ons should be suggested, not forced. Operators choose whether to add glue, flashing, clips, etc.

## Evidence Gathered

### Preflight

- `git worktree list` was run in `/Users/jacksonsweet/Projects/OPS/ops-ios`.
- `/Users/jacksonsweet/Projects/OPS` itself is not a git repo; the iOS repo is `/Users/jacksonsweet/Projects/OPS/ops-ios`.
- `pgrep -xfl xcodebuild` failed in sandbox process-list access, then returned no active `xcodebuild` process when rerun with read-only escalation.
- Root `AGENTS.md`, `ops-ios/CLAUDE.md`, `ops-ios/README.md`, the OPS design-system brief, and relevant Bible catalog/product sections were read.
- `ops-ios` has unrelated dirty files. They were inspected only where necessary and not modified.

### Current iOS Reality

Key code paths inspected:

- `OPS/Views/Catalog/CatalogView.swift`
- `OPS/Views/Catalog/Stock/AddFamilySheet.swift`
- `OPS/Views/Catalog/Stock/VariantFormSheet.swift`
- `OPS/Views/Catalog/Stock/VariantDetailView.swift`
- `OPS/Views/Catalog/Stock/StockView.swift`
- `OPS/Views/Catalog/Stock/StockTableView.swift`
- `OPS/Views/Catalog/Products/ProductKindPickerSheet.swift`
- `OPS/Views/Catalog/Products/CatalogProductsListView.swift`
- `OPS/Views/Catalog/Products/NewGoodSheet.swift`
- `OPS/Views/Catalog/Products/NewServiceSheet.swift`
- `OPS/Views/Catalog/Products/NewBundleSheet.swift`
- `OPS/Views/Catalog/Products/ProductDetailView.swift`
- `OPS/Views/Catalog/Products/AddProductMaterialSheet.swift`
- `OPS/Network/Supabase/Repositories/CatalogRepository.swift`
- `OPS/Network/Supabase/Repositories/ProductRichnessRepository.swift`

Observed gaps:

- `AddFamilySheet` creates a family and optional placeholder variant, but cannot author attribute axes or values.
- `VariantFormSheet` can choose existing option values, but cannot build the option/value matrix.
- `StockView` can list, filter, sort, and inspect existing variants, but empty-state setup is not a complete workflow.
- `NewGoodSheet` currently treats stock linkage as a discoverability hint, not a real setup path.
- `ProductDetailView` exposes options, modifiers, recipes, and bundle composition, but product options/modifiers remain read-only.
- `AddProductMaterialSheet` explicitly limits iOS authoring to variant-pinned recipe rows; family-pinned selector recipes and scaled-by-option rows are web-only today.

### Read-Only Supabase Schema Reality

Read-only schema inspection was run against Supabase project `ijeekuhbatykdomumfjx` (`ops-app`).

Verified relevant tables include:

- `catalog_items`
- `catalog_variants`
- `catalog_options`
- `catalog_option_values`
- `catalog_variant_option_values`
- `catalog_units`
- `catalog_categories`
- `catalog_tags`
- `catalog_item_tags`
- `catalog_orders`
- `catalog_order_items`
- `products`
- `product_options`
- `product_option_values`
- `product_pricing_modifiers`
- `product_materials`
- `product_bundle_items`
- `company_default_products`
- `line_items`
- `task_materials`
- `line_item_materials`
- `inventory_deductions`

Verified schema constraints:

- `products.kind` supports `service`, `material`, and `package`.
- `products.type` supports `LABOR`, `MATERIAL`, and `OTHER`.
- `products.pricing_unit` supports `each`, `flat_rate`, `linear_foot`, `sqft`, `hour`, and `day`.
- `products.linked_catalog_item_id` already links a product to a stock family.
- `product_options.kind` supports `select`, `integer`, and `boolean`.
- `product_materials` supports variant-pinned rows, family-pinned rows with `variant_selector`, and `scaled_by_option_id`.
- `product_bundle_items` supports package composition with child products and quantities.
- RLS uses the existing `private.get_user_company_id()` company-isolation pattern.

Verified current row counts:

- `catalog_items`: 58 active rows
- `catalog_variants`: 119 active rows
- `catalog_options`: 82 rows
- `catalog_option_values`: 136 rows
- `catalog_variant_option_values`: 173 rows
- `products`: 15 active rows
- `product_options`: 0 rows
- `product_option_values`: 0 rows
- `product_pricing_modifiers`: 0 rows
- `product_materials`: 0 rows
- `product_bundle_items`: 0 active rows
- `company_default_products`: 0 rows

## Possible Approaches

### Approach A - Guided iOS Setup On Current Schema Plus Generic Stock Units

Use existing catalog/product tables for families, attributes, values, variants, products, bundles, and recipes. Add only the missing generic physical-stock-unit layer for rolls/offcuts/lots under variants.

Tradeoffs:

- Best fit for the field workflow.
- Minimal schema expansion.
- Keeps vinyl, rail, and future materials in one generic model.
- Requires real iOS setup work: attribute builder, matrix builder, stock-unit editor, product linkage, and suggested add-ons.

Recommendation: **Choose this.**

### Approach B - Product-First Bundle Setup

Start from `PRODUCTS`, create a package/bundle, then prompt the user to create the stock families behind the bundle.

Tradeoffs:

- Good for estimating and sales setup.
- Bad for field users who think in physical stock first.
- Risks hiding roll/offcut inventory behind sellable product abstractions.

Recommendation: Useful as a secondary path, not the primary P1 setup.

### Approach C - Web-Only Advanced Setup, iOS Read-Only

Keep iOS to stock counts and light edits. Push attributes, recipes, product options, and bundles to ops-web.

Tradeoffs:

- Lowest iOS complexity.
- Fails the core problem: a field user cannot set up a real trade material system from the phone.
- Leaves `STOCK` and `PRODUCTS` disconnected in the place the user actually works.

Recommendation: Do not choose.

## Core Model

### Conceptual Layers

1. **Family** - the stock family or material family: `Vinyl membrane`, `Rail post`, `Glue`, `Drip flashing`, `Clip`.
2. **Attributes** - axes that describe stock, price, recipe, or compatibility: `Thickness`, `Color`, `Coating`, `Glue type`, `Width`, `Mount`, `Finish`.
3. **Values** - allowed values per attribute: `60 mil`, `68 mil`, `Black`, `PVC-coated`, `Uncoated`.
4. **Variants** - valid stockable combinations: `68 mil - Black - 6 ft roll`.
5. **Physical stock units** - concrete rolls/offcuts/lots/boxes under a variant: `Roll A - 6 ft x 75 ft`, `Offcut - 6 ft x 22 ft`.
6. **Products** - sellable templates: material goods, services, and packages.
7. **Bundles** - product packages with required and suggested child products.
8. **Recipes** - products consuming stock variants or families.

### Attribute Behavior

Every attribute in the setup flow should expose behavior toggles:

- `Stock identity`: creates catalog option/value axes and affects variant identity.
- `Affects price`: creates or links a `product_options` row with `affects_price = true`.
- `Affects recipe`: creates or links a `product_options` row with `affects_recipe = true`.
- `Shown on estimate`: makes the selected value visible in `line_items.resolved_options_label`.

Examples:

- `Thickness` can affect stock identity and price.
- `Color` can affect stock identity, recipe, and estimate label.
- `Roll width` can affect stock identity, stock-unit dimensions, and recipe yield.
- `Mount surface` can affect price but not stock identity.
- `Corner count` can affect recipe scaling but is not a stock attribute.

## Proposed iOS Catalog IA

Keep the current top-level `CATALOG` tab with two segments:

```
CATALOG
  STOCK
  PRODUCTS
```

### STOCK Segment

Purpose: track what the company physically has and set up stock systems.

Primary actions:

- `BUILD STOCK SYSTEM`
- `NEW FAMILY`
- `NEW VARIANT`
- `IMPORT`

Views:

- `LIST`: field-first scan view.
- `GRID`: visual family cards.
- `TABLE`: audit matrix for families with option axes.
- `SYSTEMS`: optional future view if a generic system grouping table is approved.

Row hierarchy:

- Category
- Family
- Variant
- Physical stock units collapsed under variant

### PRODUCTS Segment

Purpose: manage sellable services, goods, and bundles.

Primary actions:

- `NEW SERVICE`
- `NEW GOOD`
- `NEW BUNDLE`

Filters:

- `ALL`
- `SERVICES`
- `GOODS`
- `BUNDLES`
- `WITH RECIPE`
- `LINKED TO STOCK`

### Setup Menu

Kebab menu sections:

- `STOCK`: Snapshots, Categories, Tags, Units, Thresholds.
- `ORDERS`: Suggested, Drafts, Sent.
- `SETUP`: Defaults, Import, Export, Product defaults, Bundle templates.

## Proposed iOS Screens And Flow

### 1. Stock Empty State

Shown when there are no active catalog variants.

Content:

- Title: `// NO STOCK YET`
- Primary button: `BUILD STOCK SYSTEM`
- Secondary menu: `IMPORT`

Data:

- Reads `catalog_items`, `catalog_variants`, local sync state.
- Writes nothing until user enters setup.

States:

- Loading: skeleton family rows.
- Error: `SYS :: CATALOG LOAD FAILED` with `RETRY`.
- Offline: cached rows visible; `BUILD STOCK SYSTEM` can start a local draft if draft persistence is implemented.

### 2. Build Stock System

Purpose: create a family, attributes, values, variants, and physical stock units from one guided flow.

Steps:

1. `FAMILY`
2. `ATTRIBUTES`
3. `VALUES`
4. `MATRIX`
5. `STOCK UNITS`
6. `LINK PRODUCTS`
7. `REVIEW`

Data:

- `catalog_items`
- `catalog_options`
- `catalog_option_values`
- `catalog_variants`
- `catalog_variant_option_values`
- proposed `catalog_stock_units`
- optional `products`
- optional `product_options`
- optional `product_option_values`
- optional `product_materials`
- optional `product_bundle_items`

### 3. Family Step

Fields:

- Family name
- Category
- Default unit
- Image
- Default thresholds
- Notes

Data:

- Writes `catalog_items`.
- Reads/writes `catalog_categories`, `catalog_units`, `catalog_tags`, `catalog_item_tags`.

### 4. Attributes Step

Fields per attribute:

- Name
- Behavior toggles: stock identity, affects price, affects recipe, shown on estimate.
- Sort order.

Data:

- Stock identity writes `catalog_options`.
- Price/recipe/estimate toggles stage eventual `product_options` only if the user links this family to a product.

### 5. Values Step

Fields:

- Values per attribute.
- Optional default value.
- Optional per-value price impact if `affects price` is enabled.

Data:

- Writes `catalog_option_values`.
- May stage `product_option_values` and `product_pricing_modifiers` when linked to products.

### 6. Variant Matrix Step

Purpose: create only the real valid combinations.

Behavior:

- Generate matrix from stock-identity attributes.
- User enables/disables cells or rows.
- User fills SKU, warning threshold, critical threshold, default unit, and initial quantity.
- Exact duplicate combination should be blocked in iOS.
- Global duplicate SKU should warn, not hard-block, until business policy is confirmed.

Data:

- Writes `catalog_variants`.
- Writes `catalog_variant_option_values`.

Default rule for invalid combinations:

- If a combination is invalid, do not create a variant row.
- Do not add hard DB-level dependency rules until the business rule model is clearer.

### 7. Stock Units Step

Purpose: track concrete rolls/offcuts/lots under a variant.

For roll-like stock:

- Unit kind: `roll`, `offcut`, `box`, `each`, `lot`, `pallet`, `length`
- Width
- Original length
- Remaining length
- Count shortcut for identical full units
- Location
- Status
- Lot/code label
- Notes

Data:

- Proposed table: `catalog_stock_units`.
- Variant quantity can be derived or mirrored from active stock units depending on final schema decision.

States:

- Empty variant units: `// NO ROLLS LOGGED`
- Partial unit: show remaining length and status.
- Offline: allow local draft entry; queue server write.

### 8. Link Products Step

Purpose: connect stock setup to sellable products without forcing product setup.

Options:

- `NO PRODUCT LINK`
- `LINK EXISTING GOOD`
- `CREATE GOOD`
- `ADD TO BUNDLE`

Data:

- `products.linked_catalog_item_id`
- `products.kind = material` for goods.
- `product_materials` for recipe links.
- `product_bundle_items` for bundle composition.

### 9. Product Bundle Setup

Purpose: create company-specific packages from any products.

Bundle child types:

- Required children
- Suggested children

Suggested children are shown during estimate/order setup but are not forced.

Data:

- Existing table: `product_bundle_items`.
- Schema decision needed: current table has child rows and quantities, but does not distinguish `required` from `suggested`. Additive column likely needed:
  - `relationship_kind text check in ('required','suggested') default 'required'`
  - optional `suggestion_reason text`
  - optional `compatibility_selector jsonb`

### 10. Product Detail

Purpose: inspect and edit product linkage, options, recipes, and bundle composition.

Needed changes:

- Goods show `LINKED STOCK FAMILY`.
- Bundles show `REQUIRED` and `SUGGESTED` sections separately.
- Options can be authored on iOS for common cases.
- Recipe rows can use family-pinned selectors for common option mappings, not only variant-pinned rows.

Data:

- `products`
- `product_options`
- `product_option_values`
- `product_pricing_modifiers`
- `product_materials`
- `product_bundle_items`

## Vinyl Setup Walkthrough

This is a generic workflow using vinyl as the sample material.

### From Empty Catalog To Finished Stock System

1. Open `CATALOG`.
2. Empty state shows `// NO STOCK YET`.
3. Tap `BUILD STOCK SYSTEM`.
4. Family step:
   - Name: `Vinyl membrane`
   - Category: `Decking`
   - Default unit: `roll`
   - Default warning threshold: company-defined
5. Attributes step:
   - `Thickness`: stock identity, affects price, shown on estimate.
   - `Color`: stock identity, affects recipe, shown on estimate.
   - `Roll width`: stock identity, affects recipe.
6. Values step:
   - Thickness: `60 mil`, `68 mil`
   - Color: company supplier colors
   - Roll width: `6 ft`, or other company values
7. Matrix step:
   - Enable only valid combinations.
   - If a color only exists in `68 mil`, leave the `60 mil` combination disabled.
   - Enter SKUs for valid variants.
8. Stock units step:
   - Add `Black - 68 mil - 6 ft` full roll: width `6 ft`, original length `75 ft`, remaining length `75 ft`, status `full`.
   - Add shop offcut: width `6 ft`, original length `22 ft`, remaining length `22 ft`, status `partial`.
9. Link products step:
   - Create or link a `Vinyl membrane` good.
   - Set `linked_catalog_item_id` to the stock family.
10. Bundle step:
   - Create package example `Vinyl install system`.
   - Add membrane good as required or primary child.
   - Add glue, wall flashing, drip flashing, and clips as suggested children.
11. Review step:
   - Confirm family count, variant count, full rolls, partial rolls, linked product, suggested add-ons, and missing SKU warnings.
12. Commit.

### What Gets Created

- `catalog_items`: `Vinyl membrane`
- `catalog_options`: `Thickness`, `Color`, `Roll width`
- `catalog_option_values`: `60 mil`, `68 mil`, supplier colors, widths
- `catalog_variants`: valid combinations only
- `catalog_variant_option_values`: option joins per variant
- proposed `catalog_stock_units`: full rolls and offcuts with dimensions
- `products`: optional good and optional package
- `product_bundle_items`: required/suggested child products
- `product_materials`: optional recipe rows

## Data Mapping By Screen And Action

| Screen or action | Reads | Writes |
|---|---|---|
| Catalog stock list | `catalog_items`, `catalog_variants`, `catalog_options`, `catalog_option_values`, `catalog_variant_option_values`, `catalog_units`, `catalog_categories`, `catalog_tags` | none |
| Build family | `catalog_categories`, `catalog_units`, `catalog_tags` | `catalog_items`, `catalog_item_tags` |
| Add attributes | `catalog_items` | `catalog_options` |
| Add values | `catalog_options` | `catalog_option_values` |
| Matrix create | `catalog_items`, `catalog_options`, `catalog_option_values` | `catalog_variants`, `catalog_variant_option_values` |
| Edit SKU/threshold/count | `catalog_variants` | `catalog_variants` |
| Add physical roll/offcut | `catalog_variants` | proposed `catalog_stock_units` |
| Link stock to good | `catalog_items`, `products` | `products.linked_catalog_item_id` |
| Create good | `catalog_units`, `catalog_categories` | `products` |
| Create product option from attribute | `catalog_options`, `catalog_option_values`, `products` | `product_options`, `product_option_values` |
| Add price effect | `product_options`, `product_option_values` | `product_pricing_modifiers` |
| Add recipe row | `products`, `catalog_items`, `catalog_variants`, `product_options` | `product_materials` |
| Create bundle | `products` | `products.kind = package`, `product_bundle_items` |
| Mark add-on as suggested | `product_bundle_items` | schema decision: add `relationship_kind` |
| Estimate line created | `products`, `product_options`, `product_option_values`, `product_pricing_modifiers` | `line_items.configured_options`, `line_items.resolved_unit_price`, `line_items.resolved_options_label` |
| Install cut list | `line_items`, `product_materials`, `catalog_variants`, proposed `catalog_stock_units` | `task_materials`, later `inventory_deductions` |

## Schema Decisions Needed

No schema should be applied in this planning task. These are decisions for the implementation plan.

### Decision 1 - Generic Physical Stock Units

Current schema tracks variant-level `quantity`, but roll materials need physical units and offcuts.

Proposed concept: `catalog_stock_units`

Fields:

- `id`
- `company_id`
- `catalog_variant_id`
- `unit_kind`: `roll`, `offcut`, `box`, `each`, `lot`, `pallet`, `length`
- `label`
- `lot_code`
- `width_value`
- `width_unit`
- `original_length_value`
- `remaining_length_value`
- `length_unit`
- `quantity_value`
- `location`
- `status`: `full`, `partial`, `reserved`, `consumed`, `scrapped`
- `source_order_item_id`
- `notes`
- timestamps and `deleted_at`

Open policy:

- Decide whether `catalog_variants.quantity` is manually maintained, derived from active stock units, or mirrored by triggers.
- For P1, prefer additive table plus iOS read/write, with a compatibility strategy that does not break current quantity UI.

Phase 4 implementation decision (2026-05-23):

- iOS keeps `catalog_variants.quantity` as the mirrored operational scalar so existing stock/order screens continue to work.
- Roll/offcut rows mirror available area when remaining length and width share a unit. The UI shows the basis (for example, `sq ft`) instead of presenting the scalar as a roll count.
- If area cannot be computed safely, iOS mirrors one length unit when all available rows share it; otherwise it falls back to `quantity_value` count.
- No DB trigger was added in Phase 4; the setup commit path mirrors before write and blocks upfront when `catalog_stock_units` is not available.

### Decision 2 - Suggested Bundle Children

Current `product_bundle_items` does not appear to distinguish required from suggested children.

Proposed additive fields:

- `relationship_kind`: `required` or `suggested`
- `suggestion_reason`
- `compatibility_selector jsonb`

Default existing rows to `required`.

### Decision 3 - Attribute To Product Option Mapping

Catalog attributes and product options are separate tables today. The workflow needs a clean bridge when a stock attribute also affects price or recipe.

Possible options:

1. Duplicate rows into `product_options` and `product_option_values` at product-link time.
2. Add mapping table from `catalog_options` to `product_options`.
3. Keep them separate but write `option_default_source` and `variant_selector` consistently.

Recommendation for P1:

- Use explicit product options for pricing/recipe behavior.
- Store enough provenance in the UI layer to show that a product option originated from a stock attribute.
- Add a mapping table only if repeated drift becomes a real problem.

### Decision 4 - Invalid Combination Rules

Current schema represents valid combinations by creating variants only for valid combinations.

For P1:

- Invalid combinations are absent variants.
- iOS blocks exact duplicate combinations within a family.
- No hard DB-level dependency rules yet.

Future schema if needed:

- `catalog_option_value_rules`
- `product_option_value_rules`
- or a matrix table for allowed combinations.

### Decision 5 - Duplicate SKU And Duplicate Combination Policy

Recommended P1 behavior:

- Warn on duplicate SKU in the same company.
- Block duplicate variant option combinations inside the same family in iOS.
- Do not globally block duplicate SKU until supplier/company rules are confirmed.

Future schema if needed:

- partial unique index for normalized SKU per company.
- canonical combination hash per variant family.

## UX-Only Fixes

- Rename setup entry from generic `NEW FAMILY` to `BUILD STOCK SYSTEM` in empty and guided contexts.
- Add a real setup path from the stock empty state.
- Explain family, attribute, variant, and physical unit through the flow, not with long help text.
- Keep copy tactical: `// FAMILY`, `// ATTRIBUTES`, `// MATRIX`, `// STOCK UNITS`, `// REVIEW`.
- Show invalid/missing cells as inactive, not error-heavy.
- Keep suggested add-ons visibly optional.

## Code-Flow Changes Needed

- Add iOS CRUD for `catalog_options` and `catalog_option_values`.
- Add a matrix builder that stages and commits variants and joins safely.
- Add physical stock-unit repository, DTO, SwiftData model, sync, and UI.
- Replace `NewGoodSheet` stock hint with a real `TRACK IN STOCK` path.
- Let Product detail author common options/modifiers, not just read them.
- Add product bundle required/suggested child support if schema is approved.
- Add recipe setup that can handle common family-pinned selector rows.
- Add offline setup draft persistence or explicitly block commit while offline with clear state.

## Schema/Model Changes Needed

- Add generic `catalog_stock_units` or equivalent.
- Add required/suggested metadata to `product_bundle_items`, if suggested add-ons are first-class in P1.
- Consider mapping between catalog attributes and product options after implementation proves whether duplication causes drift.
- Consider duplicate-combination enforcement after business rules are decided.

## States

### Loading

- Show the catalog shell immediately.
- Show skeleton family rows and disabled commit buttons until required local data is loaded.
- Do not block already cached stock browsing while optional setup metadata loads.

### Empty

- No stock: `// NO STOCK YET`, primary action `BUILD STOCK SYSTEM`.
- No products: `// NO PRODUCTS YET`, primary action `NEW GOOD` or kind picker.
- No physical units under a variant: `// NO ROLLS LOGGED` or generic `// NO UNITS LOGGED`, depending on unit kind.

### Error

- Use specific error copy:
  - `SYS :: CATALOG LOAD FAILED`
  - `SYS :: VARIANT MATRIX FAILED`
  - `SYS :: ROLL SAVE FAILED`
- Include `RETRY` where the operation is safe to rerun.
- Keep partial setup drafts open after failure.

### Offline

- Browsing uses cached data.
- Draft setup can continue locally only if implementation includes queued writes for all affected tables.
- If not, setup remains read-only offline and commit is disabled with `SYS :: OFFLINE - SAVE BLOCKED`.
- Image uploads are blocked or queued separately.

### Partial Failure

- If family creates but variants fail, keep the setup draft open and show the failed step.
- If product creates but suggested add-ons fail, keep the product row and retry child rows.
- Avoid destructive rollback unless the write is guaranteed atomic.

## Implementation Phases

### Phase 1 - Spec And Schema Design

Acceptance criteria:

- Final spec approved.
- Physical stock-unit schema is decided.
- Suggested add-on representation is decided.
- No implementation begins before approval.

### Phase 2 - Data Foundation

Acceptance criteria:

- Additive schema migration prepared, reviewed, and not applied until separately approved.
- DTOs, SwiftData models, repositories, and sync plan are specified.
- RLS uses the existing `private.get_user_company_id()` company-isolation pattern.
- Backward compatibility with current variant quantity UI is defined.

### Phase 3 - Stock System Setup Shell

Acceptance criteria:

- Stock empty state opens `BUILD STOCK SYSTEM`.
- Flow contains `FAMILY`, `ATTRIBUTES`, `VALUES`, `MATRIX`, `STOCK UNITS`, `LINK PRODUCTS`, and `REVIEW`.
- Draft state survives navigation within the flow.
- No dead controls.

### Phase 4 - Attributes, Values, And Matrix

Acceptance criteria:

- User can create stock attributes and values from iOS.
- User can enable only valid combinations.
- User can create variants and joins in one review commit.
- Duplicate combinations are blocked in iOS.
- Duplicate SKUs warn clearly.

### Phase 5 - Physical Stock Units

Acceptance criteria:

- User can record full rolls and partial offcuts with width and length.
- User can edit remaining length and status.
- Variant list surfaces aggregate quantity and physical-unit summary.
- Existing quantity-only variants still work.

### Phase 6 - Product Linkage And Bundles

Acceptance criteria:

- Goods can link to a stock family during create/edit.
- Bundles can include required and suggested children if schema is approved.
- Product detail shows stock usage and suggested add-ons.
- Variant detail still shows reverse product usage.

### Phase 7 - Recipe And Estimate Integration

Acceptance criteria:

- Attribute values can become product options when they affect price/recipe.
- Common pricing modifiers can be authored from iOS.
- Recipe rows can be variant-pinned or common family-selector rows.
- Estimate line item snapshots use `configured_options`, `resolved_unit_price`, and `resolved_options_label`.

### Phase 8 - Verification And Bible Update

Acceptance criteria:

- Focused tests cover matrix generation, duplicate validation, stock-unit aggregation, product linkage, and suggested add-ons.
- Browser/build verification is run only in an implementation task, not this planning task.
- Bible canonical sections are updated after implementation, not before.
- No bug report is marked fixed without implementation and verification evidence.

## Open Questions

1. Should variant-level `quantity` remain manually editable after physical stock units exist, or should physical units become the source of truth?
2. Resolved for Phase 4: partial rolls/offcuts mirror area when length and width share a unit; the UI still exposes original length, remaining length, width, unit, lot/code, and notes so the scalar is not mistaken for roll count.
3. What unit dimensions are required beyond length and width: thickness, area, weight, volume, count per box?
4. Should location be free text in P1, or should it use a warehouse/truck/location table?
5. Should suggested add-ons be stored directly on `product_bundle_items`, or should there be a separate recommendation table?
6. Should add-on suggestions be driven only by bundle composition, or also by option compatibility rules?
7. Should iOS author family-pinned recipe selectors in P1, or keep selector authoring on web and only display them on iOS?
8. Should SKU duplicates be allowed inside one company when suppliers overlap?
9. Should duplicate variant combinations be enforced in the database or only in iOS first?
10. Should stock-unit dimensions support metric and imperial per row, or normalize to canonical numeric units and render per user setting?

## Non-Goals

- No vinyl-specific feature implementation.
- No production data cleanup.
- No Supabase writes.
- No migration application.
- No build or test run.
- No bug report status changes.
- No implementation after this plan without explicit approval.
