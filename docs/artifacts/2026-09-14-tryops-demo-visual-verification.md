# Try OPS visual refinement verification — September 14, 2026

## Source and status

TryOps `29679e5a818e35b69fcfa4cef23040c32b024cac`, a direct child of the previously verified combined candidate `262caad0a229a43ff2b007e8a7571a578adf7ef5`. PM and independent QA accepted the refined presentation after resolving five observed visual/interaction issues. The clean commit and technical verification were shared with the separate release task; this record establishes local acceptance, not production authorization or deployment completion.

The change contains exactly five files: `components/demo/DemoExperience.tsx`, `components/demo/demo.module.css`, a new three-case `tests/demo-motion.test.tsx`, and two existing test typing corrections. Landing, state machine, funnel/native navigation, registration and SQL are unchanged. The existing SQL file SHA-256 remains `1dddda94e7e3383ba6f9a5ed1402834acf56320d54d2d0b52929ce3a402a88b2`; production schema release status belongs to the coordinated release record.

## Verified behavior and presentation

The same job/task moves from an owner schedule into a photo-led crew field plan, then returns as a completed owner task. The pending task no longer presents an inert checkbox. Supporting context resolves after the moving anchors to prevent text collisions. A stable desktop stage, responsive density, readable phone context and native52px primary actions preserve the two-action experience.

PM independently ran234 tests across29 files on the exact clean commit: exit0. The production build includes lint/type checking and uses build ID `jXTaMlnwsWpFxu8C9Dk_Q`. Independent QA also passed234 tests during the refinement and matched frozen source hashes. Final component SHA-256 is `3d61c18a1d47fed6e09e777855f925230d42d59ce4399e44b586623b961913f0`; final CSS is `967d06fb0211a1e1065e6065e654b8a4cbacea39b97fb8ff3cc57f830301a082`.

All three states were inspected at320×568,375×667,390×844,430×932,768×1024,844×390,1280×720 and1440×900. No horizontal overflow or sub44px controls were found. All primary actions are fully visible at390×844,1280×720 and1440×900. Smaller/shorter viewports scroll naturally without an overlay hiding content. Desktop stage origins differ by at most0.5px between states.

Normal browser actions and sampled intermediate frames verified the phone and desktop handoffs without destination-text collisions. Back, Restart, reload, double-click handling, keyboard behavior, native exit, and native trial anchors were checked. All48 referenced CSS variables resolve; caption metadata uses JetBrains Mono and canonical token values show no drift.

## Loading and proof limits

The built demo measures49.3kB route /143kB first-load JS, versus5.22kB /98.1kB before refinement. The +44.9kB first-load cost is the existing synchronous Motion layout engine, selected to make it available for the first action. This is a measured bundle tradeoff, not a customer speed or conversion result.

Reduced motion has live media-query subscription and cleanup, immediate semantic actions, CSS suppression of spatial projection/delayed reveals, and three real-component regression cases covering preference changes and interruption. The browser tooling does not expose media-preference emulation; an actual OS preference change during painted motion was not recorded. Physical-phone frame rate, screen-reader speech, field Core Web Vitals and conversion lift are not claimed.

## Evidence

Project evidence root: `/Users/jacksonsweet/Projects/OPS/docs/artifacts/tryops-demo-visual-2026-09-14/`.

- PM: `pm/review.md`, `pm/final-tests.log`, `pm/final-source-receipt.json`, settled phone screenshots and `pm/production-phone-*` motion sequences with tool-relative timestamps.
- Implementation: `experience/build-final.log`, `experience/report.md`, six final desktop screenshots, `experience/desktop-geometry.json`, `experience/token-audit.json` and `experience/skills-used.md`.
- Independent QA: `qa/final-browser-evidence.json`, `qa/final-interactions.json`, all24 state/size screenshots, `qa/final-desktop-*` moving frames, `qa/independent-tests.log`, source/token evidence and final acceptance report.
- Planning/skills: `docs/plans/2026-09-14-tryops-demo-visual-refinement.md`, `pm-art-direction.md`, and PM/implementation/QA skill manifests. These document frontend design, OPS Design, interface/mobile UX, copywriting, tutorial/wizard and animation plugin use.

Interrupted-development-server captures and the initial unsettled viewport capture are explicitly excluded from final proof. The prior functional/funnel verification remains in `docs/artifacts/2026-09-14-tryops-demo-verification.md`; this record supersedes its earlier aesthetic acceptance and demo bundle measurements.
