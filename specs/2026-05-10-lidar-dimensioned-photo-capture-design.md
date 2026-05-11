# LiDAR Dimensioned Photo Capture — Design Spec

**Date:** 2026-05-10
**Owner:** iOS team
**Status:** Draft — pending implementation
**Related bug:** `8b5e7894-33e7-4529-a491-458360902d8d` ("Add lidar enabled dimensioned markup to photos")
**Bible sections impacted:** 03_DATA_ARCHITECTURE, 04_API_AND_INTEGRATION, 07_SPECIALIZED_FEATURES (new section), 10_JOB_LIFECYCLE

---

## 1. Problem & job-to-be-done

A trades business owner standing in front of a window/door/wall section needs a **quote-ready dimensioned photo** in seconds. Today they snap a photo, then back at their truck or office they re-measure with a tape, type dimensions into a quote, and hope they got it right. Every other LiDAR measurement app in market either:

- Requires a full room scan (Magicplan, Polycam, RoomPlan) — overkill for one window
- Requires manual line-drawing for every dimension on the still (CompanyCam) — slow, crowds at 3+ dims
- Sends 8–12 guided photos to a cloud pipeline (Hover) — minutes, not seconds

**The wedge:** snap one still → on-device AI auto-detects the rectangular opening → renders 4 dimensions (W, H, sill height, opening depth) on Hover-style external leader labels → outputs a quote-ready PNG/PDF in 5 seconds. Optional reference-object pass for sub-cm contract-grade accuracy.

## 2. Drift fixed by this spec

| Drift source | Reality |
|---|---|
| Bug ticket says "Screen: Home (photo markup)" | Home tab has no photo markup. Real entry: `CameraBatchView` from `ProjectActionBar` / `ProjectDetailsView:89` / `ProjectFormSheet`; markup via `PhotoCommentViewer` in `ProjectDetailsView:710` and `:786`. |
| Bible Section 10 says `project_photos` is a "future table" | Table exists in prod with full schema (id, project_id, company_id, url, thumbnail_url, source enum [`site_visit`, `in_progress`, `completion`, `other`], site_visit_id, uploaded_by, taken_at, caption, is_client_visible, created_at, deleted_at). Bible to be updated. |
| Bible has no AR/LiDAR section | DeckBuilder ships 3 working AR views (`ARPerimeterView`, `ARVisualizationView`, `ARHeightMeasureView`) using `ARWorldTrackingConfiguration`. Bible to be updated. |
| Spec assumed `project_photo_annotations` had `company_id`-scoped RLS | **Live RLS is wide open** — all three policies (`Users can create/read/update annotations`) evaluate to `true` with no `company_id` or `project_id` check. Adding the `dimensions` column inherits this same wide-open access. **This is a pre-existing security gap, NOT introduced by this spec, but flagged for separate remediation.** Logged as a follow-up concern in §13. |
| Spec assumed `notifications.type` is an enum | **`notifications.type` is `text`**, not an enum. New notification types are added by writing a new string literal, no migration needed. Section 6 corrected. |
| Spec implied "pure black" canvas | iOS `Background.colorset` is `#0A0A0A` (near-black, not pure `#000000`). OPS-Web uses pure black; iOS diverges. Verified live against `Assets.xcassets/Colors/Background.colorset/Contents.json`. All canvas references in §5 below use `OPSStyle.Colors.background` (#0A0A0A), not literal `Color.black`. |
| Bible §05 typography section is stale | Bible §05 still references Kosugi and Bebas Neue. Both were deprecated 2026-04-17 per `OPSStyle.swift` spec v2 header. Actual iOS code uses Cake Mono Light (display), JetBrains Mono (data/numbers), Mohave (body). Spec uses the current (spec v2) typography correctly. Logged as a §13 follow-up for bible cleanup. |

## 3. Architecture

### 3.1 New entry point

A new **"Measure" action** is added to `ProjectActionBar` (active project context) and to `ProjectDetailsView`'s photo gallery toolbar. Tapping it opens `DimensionedCaptureView` — a dedicated capture flow separate from `CameraBatchView` because the capture pipeline is fundamentally different (AVFoundation+LiDAR synchronized capture, not a standard `AVCapturePhotoOutput`).

**Reconciling the bug ticket's "Home" claim:** `ProjectActionBar` is rendered by `HomeContentView` whenever the user has an active project selected on the Home map. Adding the Measure button to `ProjectActionBar` therefore *does* make this feature accessible from the Home tab — just only in the active-project context that the bug filer was almost certainly in when they wrote the ticket. The ticket's "Home (photo markup)" was a folk reference, not a literal screen path.

### 3.2 Capture pipeline

**Live aim phase** — `ARWorldTrackingConfiguration` with:
- `frameSemantics = .smoothedSceneDepth`
- `sceneReconstruction = .meshWithClassification` (when supported)
- `planeDetection = [.horizontal, .vertical]`

The user sees a faint mesh overlay on detected surfaces (confidence cue, not decorative — uses a 1px hairline at 8% alpha, OPS steel-blue accent). When the live mesh classifies a vertical wall + a sub-rectangle (window/door classification), an animated reticle pulses on the candidate opening.

**Shutter phase — session-handoff mechanism (explicit):**

ARKit and AVCaptureSession both want exclusive access to the camera. The handoff sequence at shutter is:

1. **Capture ARKit state snapshot first** (while ARKit is still running): copy current `ARFrame.anchors` (mesh anchors with classification labels), `ARFrame.camera.intrinsics`, and current device pose into in-memory holding structs. This is a non-blocking read, ~5 ms.
2. **Pause ARKit:** `arSession.pause()` — releases the camera.
3. **Activate pre-warmed AVCaptureSession** with `builtInLiDARDepthCamera` and synchronized outputs (photo + depth + calibration). The session was pre-configured during the "warm-up" phase (§5.1 `// INITIALIZING …`) so this is a fast `startRunning()`, ~200 ms.
4. **Capture frame** via `AVCapturePhotoOutput.capturePhoto(with:delegate:)` paired with `AVCaptureDepthDataOutput`, joined via `AVCaptureSynchronizedDataCollection`.
5. **Tear down AVCaptureSession** and dismiss `DimensionedCaptureView` to `§5.2`. ARKit is NOT resumed (the next capture re-initializes a new ARKit session).

Returned synchronized assets:
- 48 MP photo (`AVCapturePhotoOutput`)
- 768×576 depth map (`AVCaptureDepthDataOutput`, FP32 `Disparity` via `AVDepthData.depthDataMap` after conversion to `kCVPixelFormatType_DisparityFloat32`)
- `AVCameraCalibrationData` (intrinsic matrix + lens distortion lookup)
- The ARKit snapshot from step 1 (mesh anchors, classification labels, device pose) — paired with the new frame via timestamp matching

This is **3× the linear depth resolution** of ARKit's built-in 256×192 frame (~9× area) and uses the full 48 MP wide camera. Reference implementation: Apple's "Capturing depth using the LiDAR camera" sample (research-sourced — implementation must locate and validate against current sample code at `developer.apple.com`).

**Total shutter latency budget:** 250 ms (step 2 + 3 + 4). User sees the `// CAPTURED · 0.07s` flash from §5.1 once step 4 completes.

**Persistence at moment of capture:**
- HEIC file with embedded `Disparity` channel (`kCGImageAuxiliaryDataTypeDisparity`) → uploaded as `project_photos.url` with `source = 'measurement'` (new enum value)
- Sidecar JSON (mesh anchors + classification labels + intrinsics + capture metadata) → stored in S3 alongside HEIC
- Annotation row created in `project_photo_annotations` with the new `dimensions jsonb` column populated

### 3.3 Measurement on the still

After capture, the photo opens in `DimensionedAnnotationView` (sibling to existing `PhotoAnnotationView`). Tools available:

**Manual two-tap measure:**
- Tap point A → ARKit raycasts that pixel through the stored depth map + intrinsics → world point
- 2× zoom on second tap (Apple Measure pattern), haptic tick on point-drop
- Auto-snap to detected straight edges via `VNDetectContoursRequest` on the still
- Tap point B → distance line + label rendered as an overlay

**Auto-measure (LiDAR + classification only):**
- If shutter classified a window/door rectangle, "Auto-measure" button drops up to 4 dimensions automatically: width (W), height (H), sill height (distance from floor mesh to bottom of opening), opening depth (recess from wall plane)
- **Sill height fallback when floor mesh is missing:** if no horizontal mesh is detected within 0.5 m below the opening (e.g. user shot from a stepladder, exterior shot, basement well), skip the sill-height dimension entirely. Do NOT fall back to ARKit's gravity-aligned plane — that produces a `height-from-camera` measurement which is misleading. Show 3 dimensions instead of 4 and note `// SILL — NO FLOOR REFERENCE` as an inline hint near where sill would have been.
- Each dimension is editable (drag endpoints, app re-raycasts)

**Reference-object precision mode (opt-in):**
- Toggle "Calibrate" → user places a credit card or printed OPS marker in frame and re-shoots
- `VNDetectRectanglesRequest` with tight aspect ratio bounds (1.55–1.62 for credit card — credit card is 85.60 × 53.98 mm = 1.586 aspect, bounds give ±2.5% tolerance) detects the rectangle in the photo
- **PnP solver implementation:** Apple does not ship a PnP solver in Vision or Accelerate. Two acceptable paths:
  - **Preferred:** Direct Linear Transform (DLT) implementation in pure Swift using `simd_float4x4` and `simd_inverse` — ~80 lines of matrix math, no dependency. Reference: Hartley & Zisserman "Multiple View Geometry" Algorithm 7.1.
  - **Alternative:** Add `OpenCV-iOS` SPM dependency and use `cv::solvePnP` with `SOLVEPNP_IPPE_SQUARE` flag (designed for planar markers). Adds ~6 MB to binary. Use only if DLT implementation is unstable in field testing.
- Output: 4×4 scale-correction matrix applied to all subsequent world-point measurements on this photo
- Accuracy badge upgrades from `±1″ LIDAR` → `±5 mm CALIBRATED`

### 3.4 PencilKit annotations

The existing PencilKit drawing layer remains available as a separate tool. Measurements and PencilKit drawings co-exist on the same photo. PencilKit data continues to live in `project_photo_annotations.annotation_url` (rendered PNG) + `localDrawingData` (binary `PKDrawing`).

### 3.5 Label rendering

Dimension labels follow the **Hover external-leader pattern**:
- Leader line: 1.5 px solid white with 1 px black outer stroke (visible on any background)
- Label chip: dark background (#0A0A0Acc, 80% opaque), 4 px horizontal padding, 2 px vertical, 4 px radius
- Text: JetBrains Mono, 14 pt, white, **always horizontal** regardless of leader angle
- Format: dual-unit `14′ 6½″ / 4.43 m` (per OPS design system: tabular-lining numerals, slashed zero)
- Empty / unknown state: `—` not "N/A"
- Unit toggle: Imperial fractions ↔ Decimal feet ↔ Metric (per-user setting, defaults to imperial fractions in US, metric elsewhere)

Labels auto-route to avoid overlap (a simple greedy placement: try N/E/S/W of the line midpoint, pick first non-colliding slot at increasing leader length).

### 3.6 Accuracy badge

Always shown on output (corner overlay on PNG, header row on PDF). No emoji per OPS brand rules — semantic color comes from OPSStyle chip backgrounds:

| State | Text | Chip color (OPSStyle token) | Trigger |
|---|---|---|---|
| Calibrated | `±5 MM · CALIBRATED` | `olive` (#9DB582) | Reference object pass completed |
| LiDAR uncalibrated | `±1″ · LIDAR` | `text` neutral (#EDEDED) on `glass-dense` | LiDAR device, no calibration |
| Visual SLAM | `±2″ · VISUAL` | `tan` (#C4A868) | Non-LiDAR ARKit, in-plane only — pair with `COPLANAR ONLY` chip |
| No depth | `NO DEPTH · ESTIMATE` | `textMute` (#6A6A6A) | Manual scale tool only |

Format: Cake Mono Light, UPPERCASE, JetBrains Mono for the numeric portion (tabular-lining, slashed zero per OPS spec). `·` interpunct separator, never em-dash on chips.

### 3.7 Output / deliverable

**Field-to-field PNG** (default): photo with dimension overlays burned in, accuracy badge bottom-right, OPS watermark bottom-left. **Rendered at 2048 pt long-edge** (not native 48 MP). Native 48 MP burn would produce 12–18 MB PNGs and take 3–5 s on iPhone 13 Pro; 2048 long-edge produces ~1.5–2.5 MB PNGs in <500 ms. The full-resolution HEIC remains the source of truth in `project_photos.url`; the rendered PNG is the share-friendly deliverable. Uploaded as a derived asset (`project_photos.thumbnail_url` is a wrong field for this — use a new column or a sibling row with `source = 'measurement_rendered'`; pick one and document). Appears in the project gallery with a small dimension icon badge.

**Resolution decision needed:** field test against trade users — do they want the full 48 MP burn (e.g. for blueprint scanning) or is 2048 long-edge enough? Default to 2048 unless real users push back.

**Office-handoff PDF** (on request): single-page A4/Letter PDF with the photo, a structured dimension table (W: 36″, H: 60″, etc.), accuracy badge, project metadata header (project name, address, date, captured by), and a small "Generated by OPS" footer. Generated on-device via `PDFKit`.

**Editable JSON** (always persisted): structured `dimensions` jsonb column on `project_photo_annotations` enables future re-render, unit conversion, office-side editing on the web app.

### 3.8 Device fallback ladder

| Device tier | Capture | Accuracy | UX |
|---|---|---|---|
| LiDAR (iPhone 12 Pro+, iPad Pro 2020+) | `builtInLiDARDepthCamera` | ±1″ uncalibrated, ±5 mm calibrated (full 3D — works on any plane) | Full pipeline + auto-detect + reference-object option |
| Non-LiDAR with ARKit (iPhone SE, base iPhone 12+, etc.) | ARKit visual SLAM + photo | ±2″ in-plane only — see note below | Manual measurement only (no auto-detect — needs mesh classification) + in-plane reference-object option |
| No AR support (very old) | Standard photo only | Estimate only | Manual scale tool: user marks a known length on the photo, app proportions everything else |

**Honest limitation on non-LiDAR + reference-object calibration:** The Vision rectangle + PnP solve recovers a *single-plane* scale factor. That scale is only valid for points lying on (or very near) the same plane as the reference object. Measure a window in the same plane as a credit card taped to the wall: ±5 mm. Measure the window's recess depth (out-of-plane): scale is wrong, accuracy degrades to visual SLAM (±2″). The UI must enforce this — when calibrated on non-LiDAR, only allow in-plane measurements (no recess depth, no auto-detected sill height) and show a `COPLANAR ONLY` chip next to the accuracy badge.

Resolution to the §3.6 / §3.8 inconsistency: non-LiDAR baseline is **`±2″`** (single number, no range). The "±2–4″" range from earlier draft conflated near-target vs far-target SLAM error and is dropped in favor of the conservative figure.

Device capability check at `DimensionedCaptureView` open:
```swift
let lidarSupported = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) != nil
let arSupported = ARWorldTrackingConfiguration.isSupported
let meshSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
```

**Capability → chip state mapping (explicit truth table):**

| `lidarSupported` | `arSupported` | `meshSupported` | Chip shown | Tools enabled |
|---|---|---|---|---|
| true | true | true | `LIDAR` (olive) | All: MEASURE + AUTO + CALIBRATE + MARK + NOTE + EXPORT |
| true | true | false | `LIDAR` (olive) | All EXCEPT `AUTO` (auto-detect needs mesh classification) |
| false | true | — | `VISUAL` (tan) | MEASURE + CALIBRATE (in-plane only) + MARK + NOTE + EXPORT. No `AUTO`. |
| false | false | — | `NO DEPTH` (textMute) | Manual-scale MEASURE + MARK + NOTE + EXPORT. No `AUTO`, no `CALIBRATE`. |

The combination "`lidarSupported = false` and `arSupported = false`" should be rare on iOS 17.6+ — most devices support at least visual SLAM. If it occurs, the user gets the manual-scale fallback.

## 4. Data model changes

### 4.1 Supabase schema (additive only — safe per iOS sync constraint)

**Migration: add `dimensions` jsonb to `project_photo_annotations`**

```sql
ALTER TABLE project_photo_annotations
  ADD COLUMN dimensions jsonb;

COMMENT ON COLUMN project_photo_annotations.dimensions IS
  'Structured measurement annotations from LiDAR/AR capture. NULL for legacy PencilKit-only annotations.';
```

**Migration: add `measurement` to `photo_source` enum**

```sql
ALTER TYPE photo_source ADD VALUE IF NOT EXISTS 'measurement';
```

**`dimensions` JSONB shape:**

```json
{
  "schemaVersion": 1,
  "captureMode": "lidar" | "visual" | "manual_scale",
  "calibration": {
    "method": "lidar" | "reference_object" | "none",
    "referenceObject": "credit_card" | "ops_marker" | null,
    "scaleFactor": 1.0,
    "estimatedAccuracyMeters": 0.025
  },
  "intrinsics": {
    "fx": 1593.4, "fy": 1593.4, "cx": 1015.5, "cy": 762.0,
    "imageWidth": 4032, "imageHeight": 3024
  },
  "depthAssetUrl": "s3://.../photo-id.depth.fp32",
  "sidecarMetadataUrl": "s3://.../photo-id.metadata.json",
  "measurements": [
    {
      "id": "uuid",
      "type": "linear" | "angle" | "area",
      "label": "Width",
      "worldPoints": [
        {"x": 0.123, "y": 1.456, "z": -2.345},
        {"x": 1.234, "y": 1.456, "z": -2.345}
      ],
      "imagePoints": [
        {"x": 1024, "y": 1500},
        {"x": 2840, "y": 1500}
      ],
      "valueMeters": 0.9144,
      "primaryDisplayUnit": "imperial_fraction",
      "labelPlacement": {"side": "north", "leaderLengthPx": 60},
      "source": "auto" | "manual" | "edited"
    }
  ],
  "openings": [
    {
      "id": "uuid",
      "type": "window" | "door" | "wall_section",
      "boundingPolygon": [{"x":..., "y":...}],
      "classificationConfidence": 0.92,
      "measurementIds": ["uuid", "uuid", "uuid", "uuid"]
    }
  ]
}
```

**Field rules:**
- `worldPoints` is **authoritative** for the measurement value (used to compute `valueMeters` via Euclidean distance).
- `imagePoints` is **derived** from `worldPoints` via `ARFrame.camera.projectPoint(...)` and stored only for fast offline rendering (so we don't recompute projection every time the photo is viewed). The renderer MUST recompute and reconcile `imagePoints` against `worldPoints` on first load; if they drift by >5 px, log a warning and use the recomputed value.
- `primaryDisplayUnit` is the user's preferred unit FOR THIS measurement (defaults to user's global setting at capture time). Dual-unit display (`14′ 6½″ / 4.43 m`) is a render-time decision in §3.5 — not stored as a list.
- `boundingPolygon` is in image-pixel coordinates (origin top-left).
- `valueMeters` is a denormalized convenience field — always re-derivable from `worldPoints`. Store it so the web app can render without depth math.

### 4.2 SwiftData model changes (iOS)

**Extend `PhotoAnnotation` with FOUR new fields in two clearly separated groups:**

**Synced field (round-trips to Supabase `dimensions` jsonb):**
- `dimensionsData: Data?` — Codable encoding of the `DimensionsData` struct above. Encoded to JSONB on push, decoded on pull. `captureMode`, `calibration`, `intrinsics`, `measurements`, `openings` etc. all live *inside* this blob (do not promote them to top-level columns — keeps the schema clean and avoids further iOS-sync constraint pressure).

**Local-only fields (never synced — pure on-device cache):**
- `localDepthMapPath: String?` — file URL to cached depth map. The depth map itself uploads to S3 and the URL is recorded inside `dimensionsData.depthAssetUrl`. This local path is just a working cache.
- `localSidecarPath: String?` — file URL to cached sidecar metadata. Same pattern.
- `localCaptureFinishedAt: Date?` — when the capture finished locally (used to dedupe in-flight uploads).

All four fields are additive nullable — safe under the iOS sync constraint. Only `dimensionsData` corresponds to a Supabase column; the other three are pure local working state and never serialize to the server.

### 4.3 RLS policies

Inherit from existing `project_photo_annotations` policies — no new policies needed since `dimensions` is just an additional column on the same row.

**Verified live policy state (queried 2026-05-10):**

| Policy name | Command | USING expr | WITH CHECK expr |
|---|---|---|---|
| `Users can create annotations` | INSERT | — | `true` |
| `Users can read company annotations` | SELECT | `true` | — |
| `Users can update annotations` | UPDATE | `true` | — |

All three policies evaluate to `true` for any authenticated user — there is **no `company_id` or `project_id` scoping**. This is a pre-existing security gap on the table; this spec does not introduce it and does not make it worse, but the dimensions data inherits the same wide-open access. **Recommended follow-up** (separate ticket, not in this scope): tighten all three policies to `(project_id IN (SELECT id FROM projects WHERE company_id = auth_company_id()))` plus a soft-delete guard. Track in §13.

### 4.4 SwiftData local migration

Adding four new optional fields to `PhotoAnnotation` (`dimensionsData`, `localDepthMapPath`, `localSidecarPath`, `localCaptureFinishedAt`) is a **lightweight migration** in SwiftData — all four are `Optional` and default to `nil`, so existing rows migrate transparently with no schema-version bump. Verify by:
1. Adding the fields in a separate commit
2. Building against an existing user's pre-migration `.store` file (use a TestFlight install with realistic data)
3. Confirming first launch after update completes without `MigrationError`

If SwiftData throws on the migration (it shouldn't, given all fields are optional), fall back to an explicit `SchemaMigrationPlan` with a single-stage migration that maps old → new schema.

### 4.5 Apple framework API surface (deployment target verification)

**Project deployment target:** iOS 17.6 / 18.2 (verified via `OPS.xcodeproj/project.pbxproj`). All APIs below are available; no `@available` guards required for the targeted versions but `if #available` checks are still recommended for any iOS 18-only behavior:

| API | Framework | iOS introduced | Use in spec |
|---|---|---|---|
| `AVCaptureDevice.DeviceType.builtInLiDARDepthCamera` | AVFoundation | iOS 15.4 | §3.2 capture pipeline |
| `AVCaptureSynchronizedDataCollection` | AVFoundation | iOS 11 | §3.2 sync capture |
| `AVCameraCalibrationData` (intrinsicMatrix, lensDistortionLookupTable) | AVFoundation | iOS 11 | §3.2 intrinsics + §3.3 reprojection |
| `kCGImageAuxiliaryDataTypeDisparity` | ImageIO | iOS 11 | §3.7 HEIC embedded depth |
| `ARWorldTrackingConfiguration.frameSemantics = .smoothedSceneDepth` | ARKit | iOS 14 | §3.2 live aim |
| `ARWorldTrackingConfiguration.sceneReconstruction = .meshWithClassification` | ARKit | iOS 13.4 (mesh), iOS 14 (.classification) | §3.2 opening detection |
| `ARWorldTrackingConfiguration.supportsSceneReconstruction(_:)` | ARKit | iOS 13.4 | §3.8 capability gate |
| `ARSession.captureHighResolutionFrame(completion:)` | ARKit | iOS 16 | Alternative capture path; spec uses `builtInLiDARDepthCamera` instead for 768×576 depth |
| `ARFrame.camera.projectPoint(_:orientation:viewportSize:)` | ARKit | iOS 11 | §3.3 world → image projection |
| `VNDetectRectanglesRequest` | Vision | iOS 11 | §3.3 reference-object calibration |
| `VNDetectContoursRequest` | Vision | iOS 14 | §3.3 edge auto-snap |
| `PencilKit.PKDrawing` / `PKCanvasView` | PencilKit | iOS 13 | §3.4 existing markup, reused |
| `PDFKit.PDFDocument` | PDFKit | iOS 11 | §3.7 PDF export |

**Implementation acceptance gate:** before merging, a build against iOS 17.6 minimum target must compile without `@available` warnings on the LiDAR capture path. If any API has shifted (e.g., Apple deprecates a depth pipeline at WWDC 2026), the implementation must reconcile with the actual SDK before claiming the spec complete.

**Note on Apple doc fetching:** I attempted live verification of these symbols via `WebFetch` to Apple's developer docs. Apple's docs are JavaScript-rendered and return truncated content to non-browser fetches. The API names above are sourced from: (1) the existing OPS-iOS AR codebase (`DeckBuilder/AR/*.swift`) which already uses ARKit successfully, (2) Apple WWDC session references cited in the research pass, and (3) cross-checking against the deployment target's known SDK. **Implementation must validate each symbol against the actual SDK in Xcode before relying on it.**

### 4.6 Required Info.plist entries

The new flow requires:
- `NSCameraUsageDescription` — already present in `Info.plist` for existing camera flow; **verify it covers the new use case** (current copy may say "to take project photos" — extend to "to take project photos and capture LiDAR-measured dimensions")
- `NSPhotoLibraryAddUsageDescription` — required if export-to-photos is offered (deferred — export saves to project gallery only in v1)
- No new entitlements required (ARKit and AVCaptureDevice both work with the standard camera permission)

## 5. UI specs

### 5.1 `DimensionedCaptureView`

Full-screen capture view, OPS HUD aesthetic. All chrome over a `glass-dense` overlay on the live camera. Canvas color `OPSStyle.Colors.background` (#0A0A0A) where the camera is paused — matches iOS app baseline; do NOT use literal `Color.black`. Cake Mono Light for UPPERCASE labels; JetBrains Mono for any numbers.

**Top bar:**
- Title `MEASURE` (Cake Mono Light, 14 pt, `text` color)
- Close `×` right (44×44 pt hit, `text2`)

**Center:**
- AR camera preview, faint mesh overlay (1 px hairline at `rgba(111,148,176,0.08)` — steel blue at 8% alpha)
- Pulsing reticle on detected opening (steel-blue stroke, no fill, 1.5 px line)
- Torch toggle bottom-left (44×44 pt, SF Symbol `flashlight.off.fill` / `.on.fill`)

**Bottom bar:**
- Left: torch toggle (above)
- Center: shutter (72 pt outer ring `text` color, 60 pt inner circle `text` fill, scales to 0.92 on press) — 60 pt minimum for primary actions per `ops-ios/CLAUDE.md` field-first rule
- Right: capability indicator chip — text-only (no emoji): `LIDAR` (chip `olive`) / `VISUAL` (chip `tan`) / `NO DEPTH` (chip `textMute`)

**Pre-shutter helper text** — terse, OPS voice, `//` prefix per design system. Progressive state, never random:

| State | Copy | Trigger |
|---|---|---|
| Warm-up (ARSession initializing) | `// INITIALIZING …` | 0–800 ms after view appears |
| Idle (warm but no plane) | `// AIM AT OPENING` | ARSession ready, no plane detected |
| Wall detected, scanning | `// SEARCHING` | Wall plane detected, opening not yet classified |
| Wall detected, can capture | `// WALL DETECTED` | Wall plane confident, no rectangular opening found (user can still capture; auto-detect won't fire) |
| Opening locked, optimal capture | `// OPENING LOCKED` | Rectangular window/door classified with >0.8 confidence |
| Post-capture flash | `// CAPTURED · 0.07s` | 250 ms after shutter, then dismiss to §5.2 |

All helper text uses `text-shadow: 0 1px 2px rgba(0,0,0,0.6)` for sunlight legibility against bright AR scenes (root CLAUDE.md mandates ≥7:1 contrast — verified in field test matrix §10).

**Level indicator** — faint horizontal hairline through center of viewfinder when device is level (±2°), slightly off-center / rotated when tilted. `text3` color when level, `tan` when >5° tilt. Toggleable in settings; **default ON** for LiDAR devices (skewed shots degrade measurement precision). Matches CompanyCam LiDAR Mode pattern.

**Zoom** — pinch-to-zoom enabled (1×–3× digital zoom on the AR preview). Auto-detect disables when zoom >1× (focal length change affects mesh classification reliability). Zoom level chip shows current factor (`1.5×`) when not at 1×.

**Dismissal** — primary: swipe down anywhere (matches Apple Measure, reachable one-handed on Pro Max). Fallback: × top-right (44×44 pt).

**Error states** (toast at top of viewfinder, `glass-dense` chip, dismissible by tap or auto-dismiss 4 s):
- `// ERROR — TRACKING LOST · HOLD STEADY · RESUME`
- `// LIDAR PAUSED · DEVICE COOLING · WAIT 30s`
- `// CAMERA OFF · ENABLE IN SETTINGS` (if permission denied — paired with `OPEN SETTINGS` button that calls `UIApplication.openSettingsURLString`)

**Reduced motion:** mesh overlay fades in once at 150 ms opacity transition (no pulse), reticle stops pulsing, helper text fades instead of slides. Level indicator stays static (no tilt animation).

### 5.2 `DimensionedAnnotationView`

Full-screen photo viewer with measurement tools. Pure black background. Photo rendered at fit-to-screen (letterboxed if needed). All chrome on `glass-dense` panels.

**Top bar (44 pt height):**
- Title `MEASURE` (Cake Mono Light, 14 pt, `text`)
- Right: `×` only (44×44 pt, `text2`) — single button, one-handed reachable on Pro Max
- (UNDO/REDO moved to bottom toolbar — see below)

**Photo area:** rendered with dimension overlays per §3.5. Two-finger pan/zoom always works regardless of active tool. Single-finger tap drops a point ONLY when the `MEASURE` tool is active (Apple Measure mental model — explicit modal tool selection prevents gesture conflict).

**Loupe behavior** — when a point is dropped (first or second), user can drag from the dropped point to refine. A 2× zoom loupe appears under the finger during drag, releasing when finger lifts. Initial tap drops the point at finger location; refinement is drag-after-place. Matches Apple Measure.

**Bottom toolbar** — 60 pt height (field-first), 6 tools + 2 history buttons. On screens ≥375 pt wide: each tool 60×60 pt with 4 pt gaps. On screens <375 pt (iPhone SE 1st gen): tools shrink to 50×50 pt with 6 pt gaps (still above the 44 pt minimum). No overflow menu — overflow buries primary actions, against OPS rules.

History buttons live bottom-left (one-handed reachable):
- `UNDO` (SF Symbol `arrow.uturn.backward`, 44×44 pt, disabled state `textMute`)
- `REDO` (`arrow.uturn.forward`, 44×44 pt)

Each tool is a vertical stack: SF Symbol top (24 pt, 1.5 pt stroke equivalent — `.regular` weight), Cake Mono Light label below (10 pt UPPERCASE):

| Order | Label | SF Symbol | Disabled when |
|---|---|---|---|
| 1 | `MEASURE` | `ruler` | Never |
| 2 | `AUTO` | `viewfinder.rectangular` | No opening detected at capture |
| 3 | `CALIBRATE` | `creditcard` | Never |
| 4 | `MARK` | `pencil.tip` | Never (existing PencilKit) |
| 5 | `NOTE` | `text.bubble` | Never |
| 6 | `EXPORT` | `square.and.arrow.up` | No measurements yet |

Active tool: filled background `rgba(255,255,255,0.08)` (per design system active state), label in `text`. Inactive: label in `text3`.

**Unit chip placement** — pinned top-right of photo content area (immediately below top bar, above measurement zone). Safe-area aware. Auto-hides for 1.5 s when it would overlap a measurement label, then re-appears.
- Cycling chip showing CURRENT unit only: `IN` / `FT` / `M` (Cake Mono Light, 12 pt)
- Tap: cycles to next unit (haptic light)
- Long-press: opens popover menu with all three options + per-user default toggle

**Bottom-right corner of photo:** accuracy badge from §3.6 (one chip). When non-LiDAR + calibrated, paired with a second chip directly below: `COPLANAR ONLY` (chip `tan`, JetBrains Mono).

**Calibrate flow** — tapping CALIBRATE on this view does NOT open inline. Sequence:
1. Confirmation sheet appears (`glass-dense` bottom-sheet): `// CALIBRATE · PLACE CARD IN FRAME, RECAPTURE` with `CONTINUE` and `CANCEL`
2. On CONTINUE: returns to §5.1 in **calibration mode** (helper text `// CALIBRATE · PLACE CARD ON SURFACE`)
3. On shutter: capture pipeline runs Vision rectangle detection + PnP solve
4. On success: returns to §5.2 with accuracy badge upgraded to `±5 MM · CALIBRATED`
5. On failure: stays on §5.1 with `// ERROR — REFERENCE NOT FOUND · INCREASE LIGHT · RETRY` and a `USE UNCALIBRATED` button to abort calibration and keep the existing capture's measurements

**Export flow** — tapping EXPORT opens a `glass-dense` bottom-sheet with two rows (each 56 pt tall, SF Symbol + Cake Mono Light label):
- `SAVE TO PROJECT` (default — `tray.and.arrow.down`) — uploads as `project_photos` row
- `EXPORT PDF` (`doc.richtext`) — generates single-page PDF, opens system share sheet (system share sheet can then route to Photos, Files, AirDrop, etc. without requiring `NSPhotoLibraryAddUsageDescription`)

**Direct "save to Photos library" is deferred** — it would require adding `NSPhotoLibraryAddUsageDescription` to Info.plist (out of scope per §4.6) and adds a third sheet row that crowds the bottom-sheet on small screens. Users who want a Photos-library copy can route the PDF through the system share sheet. Reconsider for v2 if field users push for it.

**Empty states:**
- No measurements yet on this photo: rendered photo only, no overlay text. The toolbar's `MEASURE` button is the affordance.
- Failed measurement (depth missing at tapped pixel): toast top `// ERROR — NO DEPTH AT POINT · TAP A SOLID SURFACE`
- After 3 failed depth taps in same session: one-time `glass-dense` bottom-sheet `// DEPTH UNAVAILABLE · USE MANUAL SCALE?` with `MANUAL SCALE` and `KEEP TRYING` buttons. Don't force; offer.

**Layout and edge-case rules:**

- **Label canvas:** dimension labels render in the full screen content area between top bar and bottom toolbar (including letterbox bars when photo aspect doesn't match screen). Labels are NOT clipped to the photo's bounding rectangle. Leader lines extend from world points anchored to the photo, terminating at chip positions in the surrounding canvas.
- **Tool visibility:** `AUTO` is **hidden** entirely (not disabled-greyed) when no rectangular opening was detected at capture. Remaining 5 tools shift left to fill. This avoids the visual clutter of greyed-out chrome on a 6-tool field-first toolbar.
- **Loupe clamping:** the 2× zoom loupe during drag-to-refine clamps to screen edges — never goes off-screen, never reveals letterbox bars (Apple Measure pattern). When the touched point is near an edge, the loupe shifts inward so the loupe content stays visible.
- **Photo orientation:** iOS auto-rotates ARKit captures based on device orientation at shutter time. `DimensionedAnnotationView` rotates to match the captured photo's orientation (portrait photos in portrait view, landscape photos in landscape view). Measurements are anchored to **photo coordinate space**, not screen — rotating the device doesn't move the dimension lines relative to the photo content.

**Close confirmation (destructive-action policy):**

Tap `×` close with measurements that have not yet been saved (committed to `project_photo_annotations` table):
- Bottom-sheet `glass-dense`: `// DISCARD MEASUREMENTS?` (Cake Mono Light, 14 pt)
- Two buttons: `DISCARD` (rose, destructive) and `KEEP EDITING` (default)
- Tap outside sheet = same as `KEEP EDITING`

Tap `×` close with all measurements already saved → close immediately, no sheet. Per root CLAUDE.md "Always confirm destructive actions" — saved work doesn't require confirmation.

**Calibration cancel path:**

When `§5.1` is in calibration mode (entered via CALIBRATE from §5.2), the top bar shows `// CALIBRATE` title (not `MEASURE`) and a `CANCEL` chip top-left (44×44 pt, Cake Mono Light). Tapping CANCEL returns directly to §5.2 with the existing accuracy badge unchanged — no calibration applied. This prevents the user from being trapped in calibration mode if the marker isn't available.

**Haptics** (per `ops-ios/CLAUDE.md` field-first):
- Light impact: tap-snap (point dropped on edge)
- Medium impact: measurement committed (second tap)
- Success notification: calibration complete, export complete
- No haptic spam — drag adjustments do NOT haptic per-frame, only on snap to edge

**Iconography (iOS):** SF Symbols throughout — see table above. Root CLAUDE.md mention of Lucide is web-only; iOS uses SF Symbols and `ops-design-system/project/ui_kits/opsapp/` confirms this. SF Symbols `.regular` weight matches OPS hairline aesthetic; never use `.bold` or `.heavy` in this view.

**Z-order on the still photo (top to bottom):**
1. Active tap reticle / 2× zoom loupe (touch interaction layer)
2. Dimension labels (chip + text)
3. Dimension leader lines + endpoints
4. PencilKit drawing layer
5. Photo

Measurements always render *above* PencilKit so a user's freehand ink can't obscure dimensions. PencilKit ink can pass behind dimension labels, but the chip backgrounds keep labels legible.

### 5.3 Animations

Audited via `animation-studio:animation-architect` (gateway skill). All durations and curves locked to OPS design system tokens: single easing curve `cubic-bezier(0.22, 1, 0.36, 1)`, no spring/bounce, every motion respects `@Environment(\.accessibilityReduceMotion)`. Add an extension to `Animation` matching `OPSStyle` motion tokens (or use existing if defined):

```swift
extension Animation {
    static let opsCurve  = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)
    static let opsStagger = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.30)
    static let opsCardFlip = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.35)
}
```

Implementation framework for every moment: **SwiftUI** (sufficient at this element count; no Metal / Core Animation needed). Per architect Principle 4 (visuals over numbers), revisit only if a profiling pass shows jank.

| # | Moment | Emotional beat | Animation spec | Framework | Haptic | Reduced-motion fallback |
|---|---|---|---|---|---|---|
| 1 | Mesh fade-in on AR session start | Entry / Arrival | Opacity 0 → 1 over 200 ms, OPS curve | SwiftUI implicit `.animation(.opsCurve, value: meshVisible)` on RealityKit material opacity | None (passive — user didn't trigger) | 150 ms opacity transition (mesh appears, no other motion) |
| 2 | Reticle pulse on opening detection | Discovery | Loop 1.6 s: scale 0.92 → 1.0 → 0.92, opacity 60% → 100% → 60%. OPS curve on both halves (mirrored on contract). Steel-blue stroke, no fill | SwiftUI `Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.8).repeatForever(autoreverses: true)` on `scaleEffect` + `opacity` | None (ambient — never haptic per architect Never-list #4) | Static reticle (no pulse), single 200 ms opacity fade-in on first detection |
| 3 | Shutter flash | Commitment | White overlay rect, opacity 0 → 1 (80 ms in, OPS curve) → 0 (160 ms out, OPS curve) = 240 ms total | SwiftUI `Color.white.opacity(flashOpacity)` overlay + two-stage `withAnimation` | **Medium impact at flash peak** (80 ms in) — single haptic, per `ops-ios/CLAUDE.md` "Medium impact on commits/confirmations" | 150 ms opacity transition only, no brightness ramp |
| 4 | Post-capture helper text `// CAPTURED · 0.07s` | Commitment (afterglow) | offset y: −8 pt → 0 + opacity 0 → 1 over 200 ms (enter), hold 1.5 s, 200 ms exit. OPS curve | SwiftUI `Text` with `.offset` + `.opacity` modifiers, transition coordinated with shutter | None (paired with shutter haptic — never double-haptic) | Fade-only enter/exit, no offset |
| 5 | Auto-measure dimension line trace (×N) | Discovery → Achievement | Each line: `Path.trim(from: 0, to: 1)` 0 → 1 over 180 ms, OPS curve. Stagger 50 ms between lines (matches design system "+50 ms per item" stagger token). Label fades in 150 ms after line completes | SwiftUI `Path` shape with `.trim(from:to:)` modifier, animated via `@State` per-line `trimEnd` values fired with `DispatchQueue.main.asyncAfter` for stagger | **Single success notification at end of stagger** (one haptic for the achievement moment, not per-line — per architect "haptics earned not spammed") | All lines + labels fade in simultaneously over 200 ms — no stroke trace, no stagger |
| 6 | Calibration-confirmed pulse on accuracy badge | Achievement | Scale 1.0 → 1.06 → 1.0 over 240 ms + olive background opacity 0.8 → 1.0 → 0.8 simultaneous. OPS curve. No bounce (one peak, one return) | SwiftUI `.scaleEffect` + background opacity, fired by `.onChange` of `calibrationStatus` | **Success notification at peak (120 ms in)** — single haptic per OPS earned-haptic rule | Scale removed; 200 ms olive-fill color fade (neutral → olive → neutral) carries the achievement beat |

**Z-order interaction:** Animation modifiers do NOT block tap input on the photo. The active tap reticle and loupe (z-layer 1 per §5.2 z-order) sit above all dimension animations — measurements can be added while another measurement is animating in (no input lockout).

**Performance budget:** Target 60 fps on iPhone 12 Pro (oldest LiDAR-equipped device — base iPhone 12 / 12 mini have no LiDAR and fall to the visual-SLAM path). 120 fps (ProMotion) target on iPhone 13 Pro and newer. If profiling shows <60 fps on iPhone 12 Pro during the staggered auto-measure trace, revisit framework — move to Core Animation `CAShapeLayer.strokeEnd` for the trace only (SwiftUI `Path` with `.trim` has known overhead with many concurrent animations).

**Never-list compliance** (architect §6):
- ✓ No `setTimeout`/`Timer` for animation pacing — only `DispatchQueue.main.asyncAfter` for stagger triggering (acceptable; not a per-frame loop)
- ✓ No layout property animation — only `opacity`, `scaleEffect`, `offset`, `.trim`
- ✓ Reduced motion handled per moment with same-beat alternatives, not disabled
- ✓ Haptics paired only with warranted moments (shutter, calibration success, auto-measure achievement)
- ✓ Every animation has explicit end condition (`.repeatForever` reticle pulse stops when opening detection clears)

## 6. Notification integration

`notifications.type` is a `text` column (not an enum) — new types are added by writing a new string literal, no migration needed. Copy follows OPS voice: `//` prefix on titles, UPPERCASE authority, JetBrains Mono for numbers, `·` interpunct separator, no emoji.

**Capture saved:**
- `type`: `"measurement_captured"`
- `title`: `// MEASUREMENT SAVED`
- `body`: `[PROJECT_NAME] · 36″×60″ WINDOW · SILL 28″` (or for wall section: `[PROJECT_NAME] · WALL SECTION · 14′6″ × 8′`)
- `actionUrl`: deep link to the photo in `ProjectDetailsView`
- `actionLabel`: `VIEW`
- `is_read`: false; standard dismissible. iOS `persistent` is a client-side concept — map to `is_read = false` and let the rail surface it.

**Upload pending (no connectivity):**
- `type`: `"measurement_pending_sync"`
- `title`: `// SYNC QUEUED`
- `body`: `3 MEASUREMENTS · WILL UPLOAD ON SIGNAL` (count is dynamic; for 1: `1 MEASUREMENT · WILL UPLOAD ON SIGNAL`)
- iOS-side: surface as a persistent (non-dismissible) banner until the local sync queue empties, then auto-clear. Web rail treats it as standard dismissible.

**Upload failed (after retries exhausted):**
- `type`: `"measurement_sync_failed"`
- `title`: `// ERROR — SYNC FAILED`
- `body`: `[PROJECT_NAME] · MEASUREMENT NOT UPLOADED · RETRY`
- `actionLabel`: `RETRY`

Reference: bible §07_SPECIALIZED_FEATURES Section 14 documents the `notifications` table and the iOS `NotificationListView` / web `EdgeTab` surfacing patterns. No new columns required.

## 7. Performance, storage & cost

**Performance:**
- HEIC + depth file size: ~4–6 MB per dimensioned capture (vs ~1.5 MB standard photo)
- Sidecar JSON: ~5–20 KB per capture
- AR session warm-up: ~800 ms typical — pre-warm session when `DimensionedCaptureView` opens
- Auto-detect inference: runs on shutter (one-shot Vision contour detection + mesh classification overlap), <300 ms on iPhone 13+
- Reference-object PnP solve: <50 ms
- PDF generation: on-device via `PDFKit`, <500 ms for single-page

**Upload pipeline:**
Reuse existing [`PresignedURLUploadService`](../../ops-ios/OPS/Network/PresignedURLUploadService.swift) — same path as PencilKit annotation PNGs. Three uploads per dimensioned capture:
1. HEIC photo with embedded depth → `project_photos.url`
2. Sidecar metadata JSON → S3 key recorded in `dimensions.sidecarMetadataUrl`
3. Standalone depth map (FP32 raw) → S3 key recorded in `dimensions.depthAssetUrl`

The depth channel embedded in HEIC (item 1) is enough for re-projection in most cases. The standalone FP32 depth (item 3) is for high-precision re-rendering and PDF export — kept for 90 days then lifecycled out (see cost below).

**Storage volumes (Supabase pricing not verified — see action items below):**

| Asset | Size per capture | Retention | Notes |
|---|---|---|---|
| HEIC + embedded depth | ~5 MB | Forever (alongside other project photos) | Counts toward existing photo storage budget |
| Sidecar JSON | ~10 KB | Forever | Negligible |
| Standalone FP32 depth map | ~1.7 MB (768×576 × 4 bytes) | **90 days then lifecycled** | Lifecycle policy needed |
| Rendered output PNG (with overlays burned in) | ~2 MB | Forever | Same gallery as standard photos |

**Projected storage volume** at scale (1 customer = 50 active jobs/month, 5 dimensioned captures/job avg):
- 250 captures/customer/month × ~9 MB hot (HEIC + sidecar + raw depth) = **~2.25 GB/customer/month while ramping**
- After 90-day lifecycle drops the FP32 raw depth: ~7 MB per old capture retained = settling to **~1.75 GB/customer/month steady-state additional growth**
- Egress assumption: each capture downloaded ~3× (capture device + office web view + 1 share) = ~6.75 MB egress per capture = ~1.7 GB/customer/month egress

**Cost — needs verification before launch.** Per CLAUDE.md cost transparency rule: I have not verified current Supabase Storage and bandwidth pricing as of 2026-05-10 and will not guess. Action items before launch:
1. Pull current Supabase Storage $/GB-month and egress $/GB from the Supabase pricing page
2. Multiply against the 2.25 GB hot / 1.75 GB steady / 1.7 GB egress numbers above
3. Confirm the per-customer monthly figure is acceptable to the user
4. If material, decide whether the standalone FP32 depth (item 3 above) should drop to 30-day retention or be eliminated entirely (HEIC embedded depth is sufficient for ~95% of re-rendering needs)

**Compute cost:** All on-device (Vision, ARKit, PDFKit). Zero cloud inference. No new third-party SDKs, no licensing.

## 8. Out of scope (v1)

- Multi-photo stitching (e.g., scan a whole wall over multiple shots)
- Volume / 3D measurement (only linear distances + areas in v1)
- Custom AR markers beyond the OPS-branded one (third-party markers later)
- Web-side editing of measurements (read-only on web in v1; iOS-only authoring)
- Voice annotations on dimensioned photos (covered by future "voice notes" feature)
- Auto-detection of objects beyond windows/doors/wall-sections (cabinets, fixtures, etc. — v2)

## 9. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Auto-detect false positives label wrong rectangles | Always show editable handles; require user tap to confirm "looks right" before saving |
| Depth map alignment drift on iPhone 12 Pro original (known Apple bug) | Detect device model on capture, apply correction matrix from Apple sample code, badge as `±1.5″` instead of `±1″` |
| Reference-object detection fails in low light | Show inline error with "increase light, try again" — don't silently degrade |
| Storage cost from depth maps | Lifecycle policy in §7 (90-day drop of standalone FP32 depth); HEIC + JSON kept forever |
| Web app can't render depth-aware photos | Web v1 just shows the rendered PNG — JSON viewer in web v2 |

## 10. Testing strategy & acceptance criteria

### 10.1 Tests

- **Unit tests:** `DimensionsRenderer` (label placement, leader routing), `ReferenceObjectCalibrator` (PnP correctness against known fixtures), `DepthRaycaster` (world-point extraction from depth+intrinsics)
- **Snapshot tests:** rendered PNG output for known fixture photos with known dimensions
- **Field-test matrix** (manual, on real devices):
  - iPhone 15 Pro (LiDAR) + iPhone SE 3rd gen (no LiDAR) + iPad Pro M4 (LiDAR)
  - 5 fixture targets: standard 36″ door, 36×60 window, 4×8 sheet of plywood, 16-on-center stud bay, exterior corner trim
- **Sync test:** capture offline, verify deferred upload of HEIC + depth + JSON when connectivity restored
- **Accessibility:** VoiceOver labels for every measurement (`"Width: 36 inches and one half"`); Dynamic Type support on all labels

### 10.2 Acceptance criteria ("done" definition)

This spec is implemented and shippable when ALL of the following pass:

| Criterion | Target | Measurement |
|---|---|---|
| LiDAR auto-detect success rate | ≥85% on the 5 fixture-target matrix in good lighting | Manual test, ≥4 of 5 fixtures auto-detect within 2 seconds of stable framing |
| Manual measurement accuracy (LiDAR) | ≥90% within ±1″ vs tape-measure ground truth | 10 captures per fixture × 5 fixtures = 50 measurements |
| Reference-object calibrated accuracy | ≥90% within ±5 mm | 10 captures, credit card in-plane with target, vs tape |
| Visual SLAM (non-LiDAR) accuracy | ≥80% within ±2″ in-plane | 10 captures per fixture on iPhone SE 3rd gen |
| Shutter-to-still latency | <750 ms end-to-end (tap shutter to §5.2 visible) | Instruments time profiler |
| Auto-measure animation budget | 60 fps minimum on iPhone 12 Pro (oldest LiDAR device) | Instruments GPU profiler, all 4 dimensions trace + label |
| Memory ceiling | <250 MB resident during capture session | Instruments allocations |
| Crash rate, first 7 days | <0.1% of dimensioned-capture sessions | Crashlytics post-launch |
| Auto-detect false-positive rate | <5% (detection on non-rectangular surfaces) | Manual test on 20 non-target shots (sky, ground, foliage) |

### 10.3 Rollback plan

This feature ships behind a remote flag `feature.measurement.dimensioned_capture` (default OFF in v1.x.0 release, ON in v1.x.1 after 48 hrs of crash-free operation). If post-launch crash rate exceeds 0.5%:
1. Flip flag OFF remotely (Supabase RPC `set_feature_flag`)
2. Existing dimensioned photos remain viewable (read path is separate from capture path)
3. Only the `Measure` entry point on `ProjectActionBar` hides
4. Bug triage, hotfix, re-enable

If crashes are tied to a specific device model, ship a device-blocklist update via the same flag rather than disabling globally.

## 11. Files to be added / changed

**New files:**
- `ops-ios/OPS/Views/Measurement/DimensionedCaptureView.swift`
- `ops-ios/OPS/Views/Measurement/DimensionedAnnotationView.swift`
- `ops-ios/OPS/Views/Measurement/Components/DimensionLabelView.swift`
- `ops-ios/OPS/Views/Measurement/Components/AccuracyBadge.swift`
- `ops-ios/OPS/Views/Measurement/Components/ReticleOverlay.swift`
- `ops-ios/OPS/Measurement/LiDARCaptureCoordinator.swift` (AVFoundation+ARKit orchestration)
- `ops-ios/OPS/Measurement/DepthRaycaster.swift` (depth + intrinsics → world points)
- `ops-ios/OPS/Measurement/DimensionsRenderer.swift` (label placement + Hover-style overlay rendering)
- `ops-ios/OPS/Measurement/OpeningClassifier.swift` (mesh classification + Vision contour fusion)
- `ops-ios/OPS/Measurement/ReferenceObjectCalibrator.swift` (Vision rectangle + PnP solve)
- `ops-ios/OPS/Measurement/PDFExporter.swift` (single-page dimensioned PDF)
- `ops-ios/OPS/DataModels/Measurement/DimensionsData.swift` (Codable schema for jsonb)
- `ops-ios/OPS/Network/DimensionedPhotoSyncManager.swift` (HEIC + depth + JSON upload)
- `ops-ios/OPSTests/Measurement/*` (unit + snapshot tests)

**Modified (file paths verified against live tree 2026-05-10):**
- `ops-ios/OPS/DataModels/Supabase/PhotoAnnotation.swift` — add new fields per §4.2
- `ops-ios/OPS/Views/Components/Project/ProjectActionBar.swift` — add Measure entry
- `ops-ios/OPS/Views/Components/Project/ProjectDetailsView.swift` — gallery toolbar Measure entry + dimensioned-photo badge in grid (capture site: line 89; markup sites: lines 710, 786)
- `ops-ios/OPS/Network/Supabase/Repositories/PhotoAnnotationRepository.swift` — handle new `dimensions` field on push/pull
- `ops-ios/OPS/Network/PresignedURLUploadService.swift` — new variants for HEIC+depth + sidecar JSON + raw depth uploads (extend, do not duplicate)
- `ops-ios/OPS/Info.plist` — extend `NSCameraUsageDescription` copy to mention LiDAR measurement
- `ops-software-bible/03_DATA_ARCHITECTURE.md` — add LiDAR dimensions schema
- `ops-software-bible/04_API_AND_INTEGRATION.md` — document new field + S3 layout
- `ops-software-bible/07_SPECIALIZED_FEATURES.md` — new **Section 27**: LiDAR Dimensioned Photo Capture (verification correction 2026-05-11: §23–25 taken by Quick Add Task Suggestions, Task Reminders, Task Pairs in the catalog merge; §26 then taken by iPhone Calendar Mirror. My section is §27.)
- `ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` — fix `project_photos` "future" claim
- `ops-software-bible/01_PRODUCT_REQUIREMENTS.md` — feature entry

**Migrations (Supabase):**
- `add_dimensions_jsonb_to_project_photo_annotations.sql`
- `add_measurement_to_photo_source_enum.sql`

## 12. Open questions for user before implementation

None blocking. All architectural decisions resolved via the brainstorming round. Two non-blocking confirmations to gather during implementation:
1. **S3 cost figure** (per §7) — pull current Supabase Storage + egress pricing and present to user before launch decision on the 90-day FP32 depth retention policy.
2. **`NSCameraUsageDescription` copy update** — confirm the new wording with the user (suggested: `"OPS uses your camera to take project photos and capture LiDAR-measured dimensions for quotes."`)

## 13. Out-of-scope follow-ups discovered during this spec

These are real findings from the verification pass that this spec does NOT address but should be tracked separately:

1. **`project_photo_annotations` RLS is wide open.** All three policies (INSERT/SELECT/UPDATE) evaluate to `true` with no `company_id` or `project_id` scoping. Any authenticated user across any company can read/write/edit any other company's annotations. This is a pre-existing security gap — not introduced by this spec, not made worse by adding `dimensions jsonb`. Suggested follow-up: tighten to `(project_id IN (SELECT id FROM projects WHERE company_id = (auth.jwt() ->> 'company_id')))` or whatever helper function the rest of the codebase uses, plus a soft-delete guard on read.

**Spawn as a separate ticket per the CLAUDE.md spawned-task naming convention (`<PROJECT> - P<phase>-<task#>`):**
- Title: `RLS HARDENING - P1-1` (treats RLS hardening as a new initiative independent of this feature; phase 1 because no prior phase exists; task 1 because it's the first spawn)
- TLDR: "Tighten RLS on `project_photo_annotations` so users only read/write rows in their own company. Pre-existing gap discovered during LiDAR Dimensioned Capture spec verification on 2026-05-10."
- Must complete before any beta launch of the LiDAR feature (data exposure risk on production captures).
2. **Bible Section 10 has stale "future tables" list.** `project_photos` is documented as future but exists in production. This spec corrects it as part of the bible update bundle, but other tables in the same list may also be stale — recommend a sweep of Section 10 for accuracy.
3. **Numbering inconsistency in `07_SPECIALIZED_FEATURES.md`** — there are duplicate Section 17 headings (Web Calendar Overhaul AND Feature Flags System). Worth a one-line fix when this spec's bible updates land.
4. **Bible Section 05 typography is stale.** Still references Kosugi and Bebas Neue as live fonts. Both were deprecated 2026-04-17 per `OPSStyle.swift` spec v2 header. Current iOS typography is Cake Mono Light (display), JetBrains Mono (data/numbers), Mohave (body). Recommend a full rewrite of §05 Section 3 (Typography System) to match the canonical `ops-design-system/project/uploads/system.md` + `OPSStyle.swift` v2.
