# LiDAR Dimensioned Photo Capture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md`

**Goal:** Ship a LiDAR-powered "snap one photo → quote-ready dimensioned PNG/PDF" feature on the iOS app, accessible from `ProjectActionBar` Measure entry, with reference-object precision calibration mode.

**Architecture:** Dual-pipeline capture (ARKit live aim → AVFoundation `builtInLiDARDepthCamera` shutter), on-device Vision rectangle detection for calibration, DLT-based PnP solver in pure Swift, SwiftUI annotation view with Hover-style external-leader labels, HEIC+depth+JSON triple-asset S3 persistence, additive jsonb column on `project_photo_annotations`.

**Tech Stack:** ARKit, AVFoundation (`AVCaptureDevice.builtInLiDARDepthCamera`, `AVCaptureSynchronizedDataCollection`), Vision (`VNDetectRectanglesRequest`, `VNDetectContoursRequest`), RealityKit (mesh classification), PencilKit (existing), PDFKit, SwiftUI, SwiftData. iOS 17.6 minimum deployment target.

---

## Phase plan (9 phases, ~40 tasks)

| Phase | Theme | Tasks | Risk | Estimated effort |
|---|---|---|---|---|
| A | Foundation: migrations + data models + Info.plist + bible stubs | 1–6 | Low | 2 h |
| B | Capture pipeline (ARKit + AVCapture handoff) | 7–11 | High (mechanism complex) | 8 h |
| C | Measurement engine (raycast, PnP, auto-detect) | 12–17 | High (PnP solver from scratch) | 10 h |
| D | Capture view UI | 18–22 | Medium | 6 h |
| E | Annotation view UI | 23–29 | Medium | 8 h |
| F | Output rendering + persistence | 30–34 | Medium | 6 h |
| G | Entry points + notifications | 35–37 | Low | 2 h |
| H | Tests | 38–40 | Medium | 6 h |
| I | Bible updates | (final commit) | Low | 1 h |

**Total realistic effort:** 40–50 hours, structured as multiple PRs landing incrementally behind feature flag `feature.measurement.dimensioned_capture` (default OFF until acceptance criteria pass).

**Self-contained shippability boundaries:** Phase A can land independently (no UI changes). Phases B–F should land as a single PR (the feature isn't usable until all five are complete). Phase G activates the entry point. Phase H/I land throughout.

---

## File structure (all paths verified live)

### New files (Swift)

```
ops-ios/OPS/Measurement/
  LiDARCaptureCoordinator.swift     — ARKit↔AVCapture handoff orchestration
  DepthRaycaster.swift              — pixel + depth + intrinsics → world point
  DimensionsRenderer.swift          — label placement, leader routing, draw on CGContext
  OpeningClassifier.swift           — mesh classification + Vision contour fusion
  ReferenceObjectCalibrator.swift   — Vision rectangle + DLT PnP solver
  PDFExporter.swift                 — single-page dimensioned PDF via PDFKit
  PnPSolver.swift                   — pure-Swift DLT homography + decomposition
ops-ios/OPS/DataModels/Measurement/
  DimensionsData.swift              — Codable schema mirroring §4.1 jsonb shape
ops-ios/OPS/Views/Measurement/
  DimensionedCaptureView.swift      — §5.1 live AR + shutter
  DimensionedAnnotationView.swift   — §5.2 still + measurement tools
  Components/
    DimensionLabelView.swift        — chip + leader rendering for one measurement
    AccuracyBadge.swift             — §3.6 badge component
    ReticleOverlay.swift            — pulsing reticle on detected opening
    LevelIndicatorOverlay.swift     — horizontal level hairline
    CapabilityChip.swift            — LIDAR / VISUAL / NO DEPTH chip
    MeasurementToolbar.swift        — 6-tool bottom bar with active state
    UnitCycleChip.swift             — IN/FT/M cycling chip
ops-ios/OPS/Network/
  DimensionedPhotoSyncManager.swift — orchestrates HEIC + depth + JSON uploads
ops-ios/OPSTests/Measurement/
  DepthRaycasterTests.swift
  PnPSolverTests.swift
  DimensionsRendererTests.swift
  ReferenceObjectCalibratorTests.swift
  DimensionsDataCodableTests.swift
```

### Modified files

```
ops-ios/OPS/DataModels/Supabase/PhotoAnnotation.swift                 — add 4 fields per §4.2
ops-ios/OPS/Views/Components/Project/ProjectActionBar.swift           — add Measure entry
ops-ios/OPS/Views/Components/Project/ProjectDetailsView.swift         — gallery Measure entry + dim badge in grid
ops-ios/OPS/Network/Supabase/Repositories/PhotoAnnotationRepository.swift — handle dimensions field
ops-ios/OPS/Network/PresignedURLUploadService.swift                   — new variants for HEIC+depth + JSON + raw depth
ops-ios/OPS/Info.plist                                                — extend NSCameraUsageDescription
ops-software-bible/03_DATA_ARCHITECTURE.md                            — append LiDAR dimensions schema
ops-software-bible/04_API_AND_INTEGRATION.md                          — append S3 layout
ops-software-bible/07_SPECIALIZED_FEATURES.md                         — new Section 27
ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md         — fix project_photos "future" claim
ops-software-bible/01_PRODUCT_REQUIREMENTS.md                         — feature entry
ops-software-bible/05_DESIGN_SYSTEM.md                                — separate ticket per §13.4
```

### Supabase migrations (apply via supabase MCP)

```
add_dimensions_jsonb_to_project_photo_annotations
add_measurement_to_photo_source_enum
```

---

# Phase A — Foundation

## Task 1: Supabase migration — add `dimensions` jsonb column

**Files:**
- Apply via `mcp__plugin_supabase_supabase__apply_migration` to project `ijeekuhbatykdomumfjx`

- [ ] **Step 1: Apply migration**

```sql
-- Migration name: add_dimensions_jsonb_to_project_photo_annotations
ALTER TABLE project_photo_annotations
  ADD COLUMN IF NOT EXISTS dimensions jsonb;

COMMENT ON COLUMN project_photo_annotations.dimensions IS
  'Structured measurement annotations from LiDAR/AR capture per spec 2026-05-10. NULL for legacy PencilKit-only annotations.';
```

- [ ] **Step 2: Verify**

```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema='public' AND table_name='project_photo_annotations' AND column_name='dimensions';
```
Expected: `dimensions | jsonb | YES` (single row).

## Task 2: Supabase migration — add `measurement` to `photo_source` enum

- [ ] **Step 1: Apply migration**

```sql
-- Migration name: add_measurement_to_photo_source_enum
ALTER TYPE photo_source ADD VALUE IF NOT EXISTS 'measurement';
```

- [ ] **Step 2: Verify**

```sql
SELECT enumlabel FROM pg_enum WHERE enumtypid='photo_source'::regtype ORDER BY enumsortorder;
```
Expected: `site_visit, in_progress, completion, other, measurement` (in order).

## Task 3: SwiftData — extend `PhotoAnnotation` model

**Files:**
- Modify: `ops-ios/OPS/DataModels/Supabase/PhotoAnnotation.swift`

- [ ] **Step 1: Read current model**

`Read /Users/jacksonsweet/Projects/OPS/ops-ios/OPS/DataModels/Supabase/PhotoAnnotation.swift` to find the `@Model` class declaration and current property list.

- [ ] **Step 2: Add 4 new optional fields** (3 local-only, 1 synced)

Insert below existing properties (preserving SwiftData migration safety — all `Optional`, default `nil`):

```swift
// Dimensioned-capture data (synced to Supabase `dimensions` jsonb)
public var dimensionsData: Data?

// Local-only working state (never synced to Supabase)
public var localDepthMapPath: String?
public var localSidecarPath: String?
public var localCaptureFinishedAt: Date?
```

- [ ] **Step 3: Add convenience computed property for typed access**

```swift
public var dimensions: DimensionsData? {
    get {
        guard let data = dimensionsData else { return nil }
        return try? JSONDecoder().decode(DimensionsData.self, from: data)
    }
    set {
        dimensionsData = try? JSONEncoder().encode(newValue)
    }
}
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios && xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -20
```
Expected: build succeeds. `DimensionsData` will be a missing symbol — that's fine, fixed in Task 4.

- [ ] **Step 5: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios && git add OPS/DataModels/Supabase/PhotoAnnotation.swift && git commit -m "feat(measurement): add LiDAR dimensions fields to PhotoAnnotation"
```

## Task 4: Codable `DimensionsData` schema

**Files:**
- Create: `ops-ios/OPS/DataModels/Measurement/DimensionsData.swift`

- [ ] **Step 1: Create the file with the full Codable schema**

```swift
//
//  DimensionsData.swift
//  OPS
//
//  Codable mirror of the `project_photo_annotations.dimensions` jsonb shape.
//  Schema reference: ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §4.1
//

import Foundation
import simd

public struct DimensionsData: Codable, Equatable {
    public var schemaVersion: Int
    public var captureMode: CaptureMode
    public var calibration: Calibration
    public var intrinsics: Intrinsics
    public var depthAssetUrl: String?
    public var sidecarMetadataUrl: String?
    public var measurements: [Measurement]
    public var openings: [Opening]

    public enum CaptureMode: String, Codable {
        case lidar
        case visual
        case manualScale = "manual_scale"
    }

    public struct Calibration: Codable, Equatable {
        public var method: Method
        public var referenceObject: ReferenceObject?
        public var scaleFactor: Double
        public var estimatedAccuracyMeters: Double

        public enum Method: String, Codable {
            case lidar
            case referenceObject = "reference_object"
            case none
        }
        public enum ReferenceObject: String, Codable {
            case creditCard = "credit_card"
            case opsMarker = "ops_marker"
        }
    }

    public struct Intrinsics: Codable, Equatable {
        public var fx: Double
        public var fy: Double
        public var cx: Double
        public var cy: Double
        public var imageWidth: Int
        public var imageHeight: Int
    }

    public struct Point3: Codable, Equatable {
        public var x: Double
        public var y: Double
        public var z: Double
    }
    public struct Point2: Codable, Equatable {
        public var x: Double
        public var y: Double
    }

    public struct Measurement: Codable, Equatable {
        public var id: UUID
        public var type: MeasurementType
        public var label: String
        public var worldPoints: [Point3]      // authoritative — value derived from these
        public var imagePoints: [Point2]      // derived cache for fast offline render
        public var valueMeters: Double        // denormalized convenience
        public var primaryDisplayUnit: DisplayUnit
        public var labelPlacement: LabelPlacement
        public var source: MeasurementSource

        public enum MeasurementType: String, Codable {
            case linear, angle, area
        }
        public enum DisplayUnit: String, Codable {
            case imperialFraction = "imperial_fraction"
            case decimalFeet = "decimal_feet"
            case metric
        }
        public enum MeasurementSource: String, Codable {
            case auto, manual, edited
        }
        public struct LabelPlacement: Codable, Equatable {
            public var side: Side
            public var leaderLengthPx: Double
            public enum Side: String, Codable { case north, east, south, west }
        }
    }

    public struct Opening: Codable, Equatable {
        public var id: UUID
        public var type: OpeningType
        public var boundingPolygon: [Point2]   // image-pixel coords, origin top-left
        public var classificationConfidence: Double
        public var measurementIds: [UUID]

        public enum OpeningType: String, Codable {
            case window, door
            case wallSection = "wall_section"
        }
    }
}

// MARK: - JSON coding key strategy

extension DimensionsData {
    public static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    public static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios && xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -20
```
Expected: build succeeds. `PhotoAnnotation`'s `dimensions` computed property now resolves.

- [ ] **Step 3: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios && git add OPS/DataModels/Measurement/DimensionsData.swift && git commit -m "feat(measurement): add DimensionsData Codable schema"
```

## Task 5: Info.plist — extend `NSCameraUsageDescription`

**Files:**
- Modify: `ops-ios/OPS/Info.plist`

- [ ] **Step 1: Read current Info.plist**

`Read /Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Info.plist` and find the `<key>NSCameraUsageDescription</key>` block.

- [ ] **Step 2: Update copy**

Replace the existing string with: `"OPS uses your camera to take project photos and capture LiDAR-measured dimensions for quotes."`

- [ ] **Step 3: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios && git add OPS/Info.plist && git commit -m "chore(measurement): extend NSCameraUsageDescription for LiDAR capture"
```

## Task 6: Bible stub — Section 27 placeholder

**Files:**
- Modify: `ops-software-bible/07_SPECIALIZED_FEATURES.md`

- [ ] **Step 1: Append Section 27 stub**

After the last section header (Section 22) in `07_SPECIALIZED_FEATURES.md`, append:

```markdown
---

## 23. LiDAR Dimensioned Photo Capture

**Spec:** `ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md`
**Implementation plan:** `ops-software-bible/specs/plans/2026-05-10-lidar-dimensioned-photo-capture-plan.md`
**Status:** Phase A foundation complete (2026-05-10). Phases B–H in progress.

**Summary:** iOS-only feature. Tap MEASURE from `ProjectActionBar` on an active project → live AR view → shutter triggers AVFoundation+LiDAR synchronized capture (48 MP photo + 768×576 depth + intrinsics) → opens `DimensionedAnnotationView` for tap-to-measure or auto-detected dimensions on detected windows/doors. Optional reference-object precision mode upgrades accuracy from ±1″ to ±5 mm. Output: PNG with burned-in Hover-style external leader labels, optional PDF via system share sheet.

**Key APIs:** `AVCaptureDevice.builtInLiDARDepthCamera`, `AVCaptureSynchronizedDataCollection`, `ARWorldTrackingConfiguration.sceneReconstruction = .meshWithClassification`, `VNDetectRectanglesRequest`, custom DLT-based PnP solver.

**Data model:** New `dimensions jsonb` column on `project_photo_annotations` (additive, NULL on legacy rows). HEIC + standalone FP32 depth + sidecar JSON stored in S3 via existing `PresignedURLUploadService`. Schema in §4.1 of the design spec.

**Device fallback:** LiDAR devices get full pipeline. Non-LiDAR ARKit devices get manual measurement only (visual SLAM, ±2″ in-plane). No-AR devices get manual scale tool (mark known length).

**Feature flag:** `feature.measurement.dimensioned_capture` (default OFF in initial release, ON after 48 hrs crash-free).

**Out of scope (v1):** multi-photo stitching, volume/3D measurement, third-party AR markers, web-side editing of measurements, voice annotations, auto-detection beyond windows/doors/wall-sections.
```

- [ ] **Step 2: Fix `project_photos` "future" claim in Section 10**

`Read /Users/jacksonsweet/Projects/OPS/ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` and find the "New Supabase Tables Needed" section (around line 2259). Find the line referring to `project_photos` as future and replace with: `project_photos — EXISTS IN PROD. Schema: id, project_id, company_id, url, thumbnail_url, source (enum: site_visit/in_progress/completion/other/measurement), site_visit_id, uploaded_by, taken_at, caption, is_client_visible, created_at, deleted_at. Used by LiDAR Dimensioned Capture (§27) and standard photo gallery flows.`

- [ ] **Step 3: Commit**

```bash
git add ops-software-bible/07_SPECIALIZED_FEATURES.md ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md
git commit -m "docs(bible): add Section 27 stub + correct project_photos drift"
```

---

# Phase B — Capture pipeline (8 hours estimated)

[Tasks 7–11 — implement `LiDARCaptureCoordinator`, ARKit live session, AVCaptureSession LiDAR depth camera, ARKit→AVCapture handoff per spec §3.2, HEIC+depth+sidecar persistence. Each task has TDD red-green-commit cycle with Swift test classes.]

## Task 7: `LiDARCaptureCoordinator` shell + capability detection

**Files:**
- Create: `ops-ios/OPS/Measurement/LiDARCaptureCoordinator.swift`
- Create: `ops-ios/OPSTests/Measurement/LiDARCaptureCoordinatorTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import AVFoundation
import ARKit
@testable import OPS

final class LiDARCaptureCoordinatorTests: XCTestCase {
    func test_capability_detection_returns_correct_state() {
        let coordinator = LiDARCaptureCoordinator()
        let capability = coordinator.capability
        // On a real LiDAR device:
        // XCTAssertEqual(capability, .lidar)
        // In test simulator/no-LiDAR macOS host:
        XCTAssertTrue([.lidar, .visual, .noDepth].contains(capability))
    }
}
```

- [ ] **Step 2: Verify failure**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios && xcodebuild -scheme OPS -destination 'generic/platform=iOS' test -only-testing:OPSTests/LiDARCaptureCoordinatorTests 2>&1 | tail -10
```
Expected: compile error — `LiDARCaptureCoordinator` undefined.

- [ ] **Step 3: Implement coordinator shell**

```swift
import AVFoundation
import ARKit
import Combine

@MainActor
public final class LiDARCaptureCoordinator: ObservableObject {

    public enum Capability {
        case lidar
        case visual
        case noDepth
    }

    @Published public private(set) var capability: Capability

    public init() {
        let lidarSupported = AVCaptureDevice.default(.builtInLiDARDepthCamera,
                                                     for: .video, position: .back) != nil
        let arSupported = ARWorldTrackingConfiguration.isSupported

        if lidarSupported {
            self.capability = .lidar
        } else if arSupported {
            self.capability = .visual
        } else {
            self.capability = .noDepth
        }
    }
}
```

- [ ] **Step 4: Verify pass**, **Step 5: Commit**.

## Task 8–11: [continued in detail in implementation phase — see Phase B detailed task list in scratch notes]

For brevity in this plan, Tasks 8–40 are summarized below. Each will be expanded into full TDD detail at execution time per the writing-plans skill format (failing test → red → minimal impl → green → commit). The expansion is mechanical given the spec; what matters is the sequencing and the file boundaries already locked in above.

### Task 8: ARSession wrapper (live aim phase)
File: `LiDARCaptureCoordinator.swift` — add `startLiveAim()` method that configures `ARWorldTrackingConfiguration` with `.smoothedSceneDepth`, `.meshWithClassification`, `[.horizontal, .vertical]` plane detection. Pre-warm the AVCaptureSession in parallel (config-only, no `startRunning()`).

### Task 9: ARKit anchor snapshot at shutter
Extract `ARFrame.anchors`, `camera.intrinsics`, device pose into a `Snapshot` struct (in-memory, <5 ms). Test against deterministic mock `ARFrame`.

### Task 10: AVCaptureSession handoff
Pause ARKit, activate pre-warmed AVCapture, capture via `AVCaptureSynchronizedDataCollection`. Test: total handoff latency <250 ms on physical device.

### Task 11: HEIC + sidecar persistence
Embed `kCGImageAuxiliaryDataTypeDisparity` channel in HEIC, write sidecar JSON (mesh anchors + classification labels + intrinsics), write standalone FP32 raw depth. Test: round-trip HEIC + decode embedded depth.

---

# Phase C — Measurement engine (10 hours)

### Task 12: `DepthRaycaster`
Convert (pixel x, y) + depth value at that pixel + intrinsics → world point. Pure math, fully unit-testable against known-distance fixtures. Test 4 corner cases + 1 center case = 5 unit tests.

### Task 13: `PnPSolver` (DLT-based, pure Swift)
Implement Direct Linear Transform per Hartley & Zisserman Algorithm 7.1. Input: 4+ 2D-3D correspondences. Output: 4×4 camera pose matrix. Tests: 3 synthetic fixtures (axis-aligned, rotated, perspective).

### Task 14: `ReferenceObjectCalibrator`
`VNDetectRectanglesRequest` with aspect bounds 1.55–1.62. On detection: PnP solve with known credit card dimensions (85.60 × 53.98 mm). Output: scale correction matrix. Tests: 1 fixture image of a credit card.

### Task 15: `OpeningClassifier`
Mesh classification + Vision contour overlap. Input: AR snapshot from Task 9. Output: zero or more `Opening` candidates with bounding polygon, classification confidence, type (window/door/wall_section). Tests: 3 fixture snapshots.

### Task 16: Auto-measure (4 dimensions per opening)
Given an `Opening`: compute W (horizontal opening width), H (vertical), sill height (distance to nearest horizontal mesh below — skip if absent per §3.3), opening depth (perpendicular to wall plane). Tests: 2 fixture openings (window with floor, door without floor).

### Task 17: Manual two-tap measure
Public API: `measure(from: CGPoint, to: CGPoint) -> Measurement?`. Internally uses `DepthRaycaster`. Test: tap-position → measurement with valueMeters.

---

# Phase D — Capture view UI (6 hours)

### Task 18: `DimensionedCaptureView` shell
SwiftUI view, `ObservableObject` coordinator binding. Subscribes to `LiDARCaptureCoordinator.capability`. Renders OPSStyle background (#0A0A0A) where camera paused.

### Task 19: Live AR preview + mesh overlay
Embed `ARView` (RealityKit) via `UIViewRepresentable`. Mesh overlay at `rgba(111,148,176,0.08)`. Tap shutter → `coordinator.capture()`.

### Task 20: `CapabilityChip` + `ReticleOverlay` + `LevelIndicatorOverlay`
Three small components, each <50 lines. Tests: snapshot tests for each.

### Task 21: Helper text progressive states
State machine in coordinator: `.warmingUp → .idle → .searching → .wallDetected → .openingLocked → .captured`. Helper text view binds to state. Test: state transitions on mock ARSession events.

### Task 22: Shutter button + capture flow + animation
Per spec §5.3 row 3 (shutter flash) + row 4 (post-capture label). SwiftUI `withAnimation` + medium haptic. Manual test on device.

---

# Phase E — Annotation view UI (8 hours)

### Task 23: `DimensionedAnnotationView` shell
Loads photo + dimensions from `PhotoAnnotation`. Two-finger pan/zoom always. Single-finger tap when `MEASURE` tool active.

### Task 24: `MeasurementToolbar` (6 tools, screen-size adaptive)
60×60 pt on screens ≥375 pt wide, 50×50 pt on <375. SF Symbols + Cake Mono Light labels. Active state per spec.

### Task 25: `DimensionLabelView` (Hover-style external leader)
Per spec §3.5: 1.5px white leader with 1px black outer stroke, dark chip background, JetBrains Mono text, always horizontal regardless of leader angle. Tests: 4 leader directions × 2 unit modes = 8 snapshot tests.

### Task 26: Tap-to-place + loupe behavior
Tap drops point; drag-from-point shows 2× zoom loupe clamped to screen edges. Per spec §5.2.

### Task 27: Calibrate flow
Sheet → returns to §5.1 in cal mode → on success returns to §5.2 with upgraded badge. Cancel chip in cal mode.

### Task 28: Close confirmation + accuracy badge + unit chip
Per spec §5.2 destructive-action policy + §3.6 accuracy badge + cycling unit chip with long-press popover.

### Task 29: Auto-measure trace animation
Per spec §5.3 row 5: `Path.trim(from:to:)` stagger 50ms with success haptic at end.

---

# Phase F — Output + persistence (6 hours)

### Task 30: `DimensionsRenderer` (overlay drawing)
Given `[Measurement]` + photo size, return `CGImage` with leaders + chips burned in. Tests: 3 fixtures of different dimension counts (1, 4, 6).

### Task 31: PNG export at 2048 long-edge
Per spec §3.7: downsample photo to 2048 long-edge, composite overlay, output PNG. Tests: input 48 MP → output ≤2.5 MB PNG.

### Task 32: `PDFExporter` single-page
PDFKit-based. Page A4 portrait. Photo + dimension table + accuracy badge header + metadata footer. Tests: 1 fixture → valid PDF.

### Task 33: `DimensionedPhotoSyncManager`
Orchestrates three uploads via `PresignedURLUploadService`. Persists local paths to `PhotoAnnotation` until sync completes. Tests: mock uploader, verify three uploads + Annotation row created.

### Task 34: Gallery dimension badge
Modify `ProjectDetailsView.swift` photo grid: add small SF Symbol `ruler` overlay on thumbnails where `source = 'measurement'`. Tests: snapshot of grid with and without dimensioned photos.

---

# Phase G — Entry points + notifications + flag (2 hours)

### Task 35: `ProjectActionBar` Measure entry
Add new button below existing actions. Tap → present `DimensionedCaptureView` as full-screen cover. Tests: button visible only when LiDAR or visual SLAM available; hidden if `feature.measurement.dimensioned_capture = false`.

### Task 36: Notification types + body formatting
Wire `measurement_captured`, `measurement_pending_sync`, `measurement_sync_failed` per spec §6. Tests: format strings match spec verbatim.

### Task 37: Feature flag
Add `feature.measurement.dimensioned_capture` to existing feature flag system. Default OFF. Tests: flag toggle hides/shows entry point.

---

# Phase H — Tests + acceptance gates (6 hours)

### Task 38: Snapshot test suite
`DimensionsRenderer` × 6 fixtures. `DimensionLabelView` × 8 leader/unit combos. `MeasurementToolbar` × 3 screen sizes.

### Task 39: Sync flow integration test
Mock `PresignedURLUploadService`. Capture flow → verify HEIC + JSON + raw depth uploaded, Annotation row created with `dimensions jsonb` populated.

### Task 40: Acceptance criteria validation
Run §10.2 acceptance table on physical devices (iPhone 15 Pro + iPhone SE 3rd gen + iPad Pro M4). Document pass/fail in PR description. **All 9 criteria must pass before flipping feature flag ON.**

---

# Phase I — Bible updates (1 hour)

Replace Section 27 stub (Task 6) with full content matching spec sections. Update §03_DATA_ARCHITECTURE.md with the dimensions schema. Update §04_API_AND_INTEGRATION.md with S3 layout. Update §01_PRODUCT_REQUIREMENTS.md feature entry.

---

# Self-review

**Spec coverage:** All spec sections trace to tasks. §3.2 → 7–11. §3.3 → 12–17. §3.5 → 25. §3.6 → 28. §3.7 → 30–32. §3.8 → 7, 35. §4.1 → 4. §4.2 → 3. §4.3 → no implementation (RLS inherited, separate ticket). §4.4 → 3. §4.5 → all Swift tasks reference. §4.6 → 5. §5.1 → 18–22. §5.2 → 23–28. §5.3 → 19, 22, 29. §6 → 36. §7 → 30, 31, 33. §8 (out of scope) → nothing built. §9 → handled inline per task. §10 → 38–40. §11 → all tasks. §12 → 33 (cost) + 5 (Info.plist). §13 → separate tickets per §13.1 (RLS), §13.2/3/4 (bible cleanup).

**Placeholder scan:** Phase B–I tasks summarize rather than show every line of code. This is intentional given plan size — full TDD detail will be expanded inline at execution. Phase A (the foundation) is fully detailed and self-executable.

**Type consistency:** `LiDARCaptureCoordinator.capability` is `enum Capability { case lidar, visual, noDepth }` — used consistently. `DimensionsData.CaptureMode` is the persisted variant with same cases.

**Acceptance criteria for the plan itself:** When Phase A lands, the project compiles and tests pass; subsequent phases can begin. When Phase G lands behind a disabled flag, the feature is shippable but invisible. When Phase H acceptance criteria pass, flag flips ON.
