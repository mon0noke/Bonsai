# Current iteration — 3.6.9 (60), 8 October 2026

The current feature and evidence records are outputs/Bonsai-3.6.9-Changes.md and outputs/Bonsai-3.6.9-Verification.md. Earlier dated sections below are historical, not the current capability claim.
Current update: supported Sparkle full ZIP installation was verified with an official isolated Keka 1.6.7 → 1.6.8 fixture, including archive/publisher checks and old-bundle recovery. Mole’s native Keka update was observed separately. Optimize details now fits all tasks in two columns without scrolling; task output opens independently. Loading tracks are removed. 186 cases / 1,179 assertions and 60 software checks pass. Final GUI/access evidence is recorded in the current verification file.


- [x] Remove Clean More scans landing section; retain guarded rows.
- [x] Native scan/idle tree animation, Analyze sidebar animation, measured 60 FPS isolated renderer.
- [x] Expand Optimize to 19 recommended / 24 total with real pinned Mole handlers and explicit diagnostics.
- [x] Correct disk allocation/hardlink accounting, bounded memory, plain sizes and separate completeness.
- [x] Update All, source labels, verified Electron ZIP update and fresh installed metadata.
- [x] Test read-only protected scans after user-managed FDA; correct misleading repeated access guidance.
- [x] Direct Sparkle full ZIP runtime: real signed Keka archive installation and recovery verified.
- [ ] Optional framework-based non-ZIP Sparkle path: requires appropriate signing and live integration QA.
- [ ] All source/hardware/OS/release combinations: not implied by local fixture and GUI coverage.

# Implemented feature checklist and capability limits

Status reflects **Bonsai 3.1.0 (31)**, with the approved planet design preserved separately as Otto. This updated app is a preview before a new DMG. DMG-Verification.md describes the previously approved 2.7.1 release only.

| Requirement | Implementation / state |
|---|---|
| Original identity and premium native UI | Original jade bonsai app icon and compact vector emblem, three original cherry/maple/pine bonsai portraits with ambient SpriteKit motion; Light ivory/mint/sky/peach and Dark forest/cream palettes, saved Light/Dark/System choice, native pointing-hand button cursors with macOS 14 hover fallback, rounded typography, spacious top capsule navigation with continuous sliding selection, centered nature landings, restrained verses and one primary action; native Liquid Glass on scope/software controls and companion capsule, accessible motion/material/opaque fallbacks |
| Clean categories | App/browser caches, logs, old user temp items, Xcode DerivedData/Archives, npm/pip/uv, Hugging Face models, Code/Cursor/Claude, Slack/Discord/Figma, cloud/design/communication cache classification; models/archives are high risk |
| Scan explanations/paths/sizes/confidence/risk | Expandable category totals, selectable rows and inline item inspector, search, allocated/logical size distinction, completeness and issue labels |
| Exclusions/defaults/running apps | Persistent excluded paths; no-selection or low-risk-log default; manual developer/data/model selection; exact and family app guards |
| Full clean workflow | Scan → selection → per-item review → acknowledgment → revalidation → Trash → itemized outcomes → local history and recovery paths; dry-run preview and cancellation |
| Dependency folders | User-chosen project root; node_modules/.build/target; depth/budget bounds; high-risk independent review; never automatically selected |
| Uninstall | Mole-inspired expandable rows with icons/version/allocated size/running state and truthful used/accessed metadata. Individual Application/cache/data selections, clickable removal/review totals with independent disclosure, hover highlight, icon/sliding-glass Software tabs, Ready/Needs review/Unavailable groups and fixed review footer. Search name/ID/path; persistent bidirectional Name/App size/Last Used/Installed sorting with unknowns last. System apps opt-in. Exact ID user-data and temporary cache discovery, uniquely named tentative support folders (manual only), explicitly declared privileged helpers (unavailable without permitted ownership), shared-copy protection. Two concurrent inspections, cache/refresh/cancel/retry and stale result guards; compact independent selection/disclosure, short inline confirmation, dedicated oak progress/completion, flat per-app results and original/Trash recovery paths; only checked paths enter Trash/outcomes |
| App inventory boundaries | Applications/System Applications/user Applications/Setapp; three-folder depth, explicit completion/partial labels, metadata-first inventory with two bounded background sizing workers, explicit unknown/partial sizes, independent stop-sizing/refresh, cancellation and Add app chooser. Wrapped iOS apps without a normal Bundle metadata layout and third-party installation stores may be omitted |
| Updates | Automatic, independent metadata checks on entering Updates; recent local cache, incremental results, freshness, stop/retry and persistent opt-out. Declared Sparkle/Electron feeds, locale App Store catalog including universal Mac apps, installed Homebrew casks and literal local tap metadata provide available versions. Available rows have Update; remaining app rows have Reveal in Finder and Uninstall with functional sorting/search. Installation requires confirmation or supported publisher/App Store handoff. Unsupported sources and failed checks are disclosed. |
| Startup | Login apps/background registrations from an explicitly authorized read-only BTM inventory, correct parent/helper grouping, current-user launch agents and system services. On/off switches show measured registration or permission state. Supported current-user agents use review, verification, restoration/audit; macOS-managed switches open Settings. Own SMAppService item supported after installation. |
| Modern login/background items | General third-party SMAppService inventory/control is unavailable via a public API; open System Settings Login Items. Structured authorized sfltool snapshot; no private database mutation |
| Analyze | Proportional 2D treemap, breadcrumbs/up/drill-down, allocated/logical sizes, largest-item filtering, session cache/refresh, incremental progress/cancel, permission errors/retry, open/reveal, reviewed Trash actions |
| Doctor menu | Reviewed read-only Spotlight and power-assertion checks, sequential bounded commands/post-checks, cancellation/skipped checks and captured results/history |
| Optimize | Quick Look cache reset and generator reload; Spotlight state, filesystem verification, and power-assertion diagnostics; previews, prerequisites, confirmation, bounded execution, output, post-check, history; Disk Utility repair handoff |
| Live status | CPU tick deltas, active+wired+compressed memory estimate, measured memory pressure, free/capacity, battery charge/cycles and health estimate when registry values exist, uptime, thermal pressure, network counter rates, process CPU/RSS and freshness |
| Charts/process table | CPU/memory/network histories bounded to 60 samples; fixed dashboard/headers, grouped app/helpers, centered glass inspector with six-member preview/expansion, selected-process counters/ancestry/path, search/sort/owner-aware pins; separate confirmation and identity-validated SIGTERM/SIGKILL with post-sample |
| GPU/temperature/fan/power draw | Explicitly unavailable in this build. Detailed Apple Silicon powermetrics requires privileged, hardware-dependent collection; no root collector or private drivers are supplied. Public thermal-pressure state is available |
| Battery health | Optional IOKit source health or registry full/design capacity estimate; no invented value when unavailable. Estimates and inputs are labeled |
| Menu bar | Shares the single collector with the main window, two-second refresh, health/hardware badges, six-card grid, battery/top-process cards with Memory/CPU sort and inspector handoff, freshness, Awake/Screen/local history/Status/Clean/window access, Quit |
| Keep Screen On / Clean Screen | Managed display-sleep assertion with 15-minute, 1-hour or until-quit duration; per-display reversible curtain; Escape/button/60-second exit |
| Privacy activity/fan controls | macOS privacy indicators/Control Center handoff; arbitrary other-app camera/mic activity and fan controls have no supported public interface in this build |
| Local-first/permission handling | No analytics/account/server; scans use existing user permissions, no elevation; Settings access handoff and actionable partial/error states |
| Audit/recovery/safety | Owner-only bounded local JSON history, home-path abbreviation, control-character and common credential redaction; item outcomes, identity/path/ownership/symlink checks; retained Trash recovery |
| Verification | Standalone shared-source harness, fixtures, native GUI inspection, fresh arm64 bundle metadata/signature verification; no new DMG yet. Full XCTest and macOS 14 hardware QA remain external checks |
| Packaging/signing | Reproducible scripted arm64 .app build; DMG script remains available for use after user evaluation; icon/resources/metadata, Applications link, source archive, install instructions; ad-hoc hardened runtime locally. Developer ID/notarization/stapling require release credentials |

Additional clean scopes include strict identifier-based potential leftovers (not proof of abandonment), age-filtered installer review, and an optional read-only Trash-app watcher. Browser profile and Electron cache rules preserve unrelated settings/credentials and do not traverse symlink profiles.

No claim of exact Mole parity: Bonsai intentionally implements a supported, reviewed native scope. It does not clear every cache family in Mole, elevate DNS/Spotlight repairs, delete cloud content or containers, compact app databases, empty Trash, install fan drivers, or supply automatic proprietary-app update feeds. Unreadable and unvisited locations are lower-bound measurements, not zero size. Fallback last access is filesystem metadata, not a reliable launch-history record. Appcast metadata is informational and is not cryptographically authenticated by Bonsai; the app’s updater validates its packages. Ambiguous version strings and unsupported feeds are skipped. Public App Store availability differs by storefront/account; the check uses host locale country, three concurrent requests and up to 128 declared sources within a 120-second admission budget. Runtime-selected/undeclared feeds and custom providers remain unsupported. Installer scans require the user to eject images manually before removal. General third-party inventory requires explicit authorized sfltool reading; managed switches use Settings. Direct arbitrary third-party SMAppService mutation is not implemented.

## Optimize 2.6 acceptance

- [x] Grouped task selection and explanatory details; no command during preview.
- [x] Exact selected-task confirmation and refresh acknowledgment; disk check opt-in.
- [x] Sequential progress, timeout/cancellation and skipped unstarted tasks.
- [x] Itemized grouped results, captured output/post-check, review for retry and local audit.
- [x] Session selection/result retention across navigation; History for prior runs.
- [x] Fixtures cover ordering, unknown IDs, deduplication, failure continuation, cancellation at progress, a worker ignoring cancellation, verification timeout/cancellation and retained completed output.
- [ ] Additional Mole native maintenance operations are not implemented: user-service restarts, database compaction, broken-agent deletion and preference repair. No memory purge or privileged automation is exposed.
- [ ] Minimum-window, full VoiceOver, older OS and native long-running/cancellation lifecycle permutations remain manual QA.

## Optimize 2.7 visual acceptance

- [x] Direct Mole Optimize reference inspection preceded this redesign.
- [x] Centered persistent maple, single main action, compact selection/confirmation sheet.
- [x] Actual rolling progress/checklist and completion hero with reviewed results/rest.
- [x] Full-window flat details, grouped outcomes/categories, whole-row disclosure and hover.
- [x] Separate refresh/check totals, unknown-completion accounting and typed UI stages.
- [x] Prerequisites/commands, acknowledgment, timeouts, cancellation, History and Disk Utility retained.
- [x] Debug native sheet gating/cancel/reopen, read-only completion, output expansion, Escape/rest and page retention checked.
- [ ] Long-running native cancellation, all motion/transparency/contrast/VoiceOver and minimum-window/older-OS permutations remain manual QA.

## Optimize 2.7.1 direct-flow acceptance

- [x] Native Mole execution and appended log inspected before changes.
- [x] Main Optimize starts four supported routine tasks without extra UI steps.
- [x] Custom tasks remain separate; optional disk verification cannot enter the direct plan.
- [x] Stationary maple, real progress, cancellation, itemized output/post-check and audit retained.
- [x] One direct-plan/dispatch fixture; existing runner safety fixtures retained.
- [ ] Additional Mole maintenance commands remain unsupported as listed above.

## Uninstall 2.8 acceptance

- [x] Full installed Mole selection/review/remove/completion/details/recovery observed with a disposable app before changes.
- [x] Rename Bonsai Nature to Bonsai; preserve the existing identifier/history and frozen Otto.
- [x] Metadata-first inventory, two bounded sizing workers, revision-cached sorting/search and stale-result guards.
- [x] Compact selection footer and inline confirmation; changed selection requires fresh confirmation.
- [x] Exact-identifier logs, generated defaults, manual personal-data review and running-app refusal.
- [x] Dedicated oak progress/completion, current-item checklist/cancellation and truthful Trash accounting.
- [x] Full-window flat result rows, whole-row details, Finder reveal, kept/partial outcomes and manual recovery instructions.
- [x] 82 core cases / 306 assertions and 39 actual SoftwareStore checks passed; final clean release/bundle verified.
- [x] Real six-path dummy uninstall, complete six-root/ten-file-hash restoration, final polished-build repeat and keyboard/results checks.
- [ ] Native long-running cancellation, complete VoiceOver/minimum-layout/accessibility/older-OS and comparative performance QA.
- [ ] New 2.8 DMG after user preview; Developer ID/notarization/stapling and full Xcode XCTest before public release.

## Apps 2.8.1 selection acceptance

- [x] First row click selects without expanding; subsequent clicks only expand/collapse.
- [x] Right group checkbox deselects and collapses; checked paths clear.
- [x] Unselected apps hide summary and details even with cached reports.
- [x] Individual path deselection keeps app review accessible; empty/protected selections cannot enable removal.
- [x] Repeated/pending clicks preserve selections and avoid duplicate inspection work.
- [x] Clean release native select/expand/collapse/reopen/checkbox-hide sequence and About verified; no filesystem mutation.
- [x] 82 core cases / 306 assertions and 39 actual state checks pass; signature/artwork/Otto/source verified.

## Software tabs 2.8.2 acceptance

- [x] Lighter glass rail, ivory inset tile, peach icon badges, rounded typography and restrained focus/press/hover states.
- [x] Persistent selection and matching text-contrast mask; immediate selection and interrupted mouse travel.
- [x] Three accessible native buttons, selected state, hand cursors and arrow-key wrap.
- [x] Light/Dark native screenshots, restored Dark, actual mouse and normal arrow switching verified.
- [x] 82 core cases / 306 assertions and 39 app-state checks pass; final clean release, strict signature and resources verified.
- [ ] Measured frame pacing, high-rate synthetic keyboard burst behavior, complete accessibility/older-OS/minimum-window stress QA.

## Apps services 2.9.0 acceptance

- [x] Smaller software tabs; no outer or focus outline. Persistent selection travel, hand cursors, keyboard switching and reduced motion retained.
- [x] Automatic metadata checks, local cache, incremental publication, bounded work, cancellation/stale guards, retry and persistent opt-out.
- [x] Login-item authorization flow and parser for both macOS disposition formats; helper grouping, parent-relative containment, current-user boundaries and unknown states.
- [x] Verified/reversible user-agent switches and native managed-item handoffs.
- [x] Actually invoked, pinned Mole application-protection backend with integrity checks and upstream GPL notices.
- [ ] Every task routed through the public Mole CLI: not achieved; it has no third-party app-update/login-item API. Native services retain features outside the narrow source adapter.
- [ ] Developer ID, signed read-only XPC helper replacing the deprecated authorization launcher, notarization and full macOS 14/system accessibility matrix.


## Apps 2.10.0 acceptance

- [x] 10% larger than compact preview: content, companion and sheets at 0.88 of original; native OS controls retain system sizing.
- [x] Available-update actions and installed-app Reveal/Uninstall rows; functional ordering, search, per-app status and source disclosures.
- [x] Broader App Store/Sparkle/Electron/Homebrew metadata with bounded concurrency, fresh-pass replacement and source deduplication.
- [x] Literal local tap releases without Ruby execution or trust changes; publisher handoff for untrusted tap.
- [x] Structured current-user login cache/freshness, independent startup task and actual loaded/persistent state distinction.
- [x] Clean build, 93 core cases / 379 assertions, 39 selection checks, 21 update checks, zero failures; installation and final native smoke checks.
- [ ] Own SMAppService registration on/off native test pending user approval; left off.
- [ ] Runtime/undeclared/custom updater feeds and every-task Mole CLI routing not implemented.
- [ ] New DMG after evaluation; signed reader, Developer ID/notarization, full Xcode/platform/accessibility release matrix.

## Apps 2.10.1 polish

- [x] Fully rounded pill-shaped Uninstall/Updates/Startup buttons, matching selection mask, focus, hover and press shapes; borderless track and existing motion retained.
- [x] Another five-percent interface increase: 0.88 × 1.05 = 0.924 of original. Main content, app sheets and companion share the scale; native macOS chrome remains system-sized.
- [x] Clean arm64 release, 93 core cases / 379 assertions, strict bundle/resources, native pill/switching/About checks; evidence in VERIFICATION.md.

## Status 2.11 acceptance

- [x] Fixed dashboard, measurement toolbar, sorting/search header and accounting footer; only process rows scroll.
- [x] App icons, measured helper counts, grouped CPU/RSS totals, hover tint and live member inspector.
- [x] Separate path copies/users; bounded ancestry, unknown/partial metrics, search of helper names/PIDs, deterministic reversible sorting and pins.
- [x] Individual confirmed, identity-validated graceful termination with post-sample outcome; disposable-child integration test.
- [x] Native reference/preview checks for grouping, row scrolling, sorting, inspector and termination cancellation.
- [ ] Full VoiceOver, macOS 14 hardware, minimum-window and lifecycle stress release QA.

GPU/power draw, numeric temperatures, fan control and launch-reason attribution remain unavailable; no substitute values are fabricated. RSS totals may count shared pages and app CPU may exceed 100%.

## Page-animation 2.12 acceptance

- [x] Animate all page switches with a directional glide/fade with leaves spanning the full window and fixed top navigation.
- [x] Species-specific oak/maple/pine sweep, bounded to 24 particles and 1.65 seconds.
- [x] Forward/reverse keyboard navigation and rapid replacement settle on the latest selection.
- [x] No particle hit targets; cleanup on completion, cancellation, inactivity or minimization.
- [x] Implement Reduce Motion bypass; verify cancellation/stale completion in actual-source harness.
- [x] Render actual species paths in standalone harness and observe oak/maple/pine sweeps in native preview.
- [x] Clean arm64 release, unchanged 100-case core harness, strict signature and identical installed copy.
- [ ] Native macOS Reduce Motion toggle, full VoiceOver, light/dark/system variants and older macOS/high-refresh/minimum-window matrix remain manual release checks.

## Shared-breeze2.13 acceptance

- [x] One monotonic flight phase and breeze envelope drive tree gust and window-leaf drift.
- [x] Shared species shapes/palettes for ambient and page leaves.
- [x]24 smaller/translucent leaves, slower motion and retained full-window coverage.
- [x] Actual-source page/Canvas and tree/SpriteKit tests rerun, including gust mesh bounds and cancellation.
- [x] Native all-species transitions, reverse keyboard and rapid switching checked in installed release.
- [ ] Full native accessibility/appearance/hardware matrix remains manual.

## Canopy arrival 2.14 acceptance

- [x] Full-window leaves follow curved paths into the actual destination tree bounds.
- [x] Carried leaves match ambient tree positions, sizes, angles and flutter, with complementary opacity.
- [x] Ambient clock continues from arrival; extra leaves dissolve in the canopy.
- [x] All-species actual Canvas/SpriteKit tests, stale-flight/cancellation and bounded geometry pass.
- [x] Installed app: complete maple sequence observed, pine switching, keyboard reverse and rapid replacement checked; About 2.14 confirmed.
- [ ] Full native accessibility, appearance, older OS/hardware and high-refresh matrix remains manual.

## Bonsai 3.0 acceptance

- [x] Name, window/menu/About/companion and icon use Bonsai; previous app/source and Otto preserved.
- [x] Three original transparent miniature bonsai portraits with species-specific petals/leaves.
- [x] Warm ivory/blossom/moss palette and separate dark colour mode.
- [x] Longer 4.2-second full-window circulation; immediate navigation and latest-flight replacement.
- [x] Continuous ambient orbit and matched landing poses/opacity; no wrapping/reset.
- [x] Clean release, core, actual Canvas/SpriteKit, appearance/contrast, bundle and installed hash checks.
- [x] Native all-species layouts, captured longer flow, quick switching, keyboard, Light/Dark, companion and About.
- [ ] Subjective animation approval; full native Reduce Motion/Transparency, VoiceOver, old OS/hardware and frame-pacing matrix.

## Bonsai 3.1 request checklist

- [x] Immediate page content/background; no switching sweep or page fade/slide.
- [x] Compact six-card companion, shared readings, battery/process/history and working quick controls.
- [x] Status centered glass inspector and compact member list inspired by supplied Mole panel.
- [x] Public metadata, bounded descriptor counting, unavailable states and stale identity guards.
- [x] Separate SIGTERM/SIGKILL confirmations, verification/audit; real force test only on disposable fixture.
- [x] Original jade bonsai icon, transparent corners, native sizes, prompt/provenance.
- [x] Clean release, shared-source tests, native workflow checks, installed byte/signature checks and recoverable previous version.
- [ ] User visual acceptance of actual menu-bar popover; full native VoiceOver/OS/hardware matrix and publisher signing.

## Bonsai 3.2 Analyze and permissions

Analyze has a fixed sidebar and full-height treemap; it never scrolls the entire page. Immediate children appear largest-first, with 16 sidebar entries before optional expansion. Search reaches every listed entry. Positive-sized entries are grouped into at most eight map tiles, including all smaller items in the last group. Unknown/zero items remain available in the sidebar. Groups open a data-bound list; files open an inspector; folders drill down. Breadcrumbs retain the closest three parents and put earlier ancestors in a menu. Parent navigation and Command-R operate on Analyze, and Escape/Command-period stop scanning.

Whole Disk is a catalog of current home, /Applications, /Library and /opt. Actual volume usage is shown separately. The Files total deduplicates file allocation across this scan by device/inode; map weights show per-item sizes and may repeat cross-entry hardlinks. APFS clones/snapshots/purgeable storage are not guaranteed reclaimable bytes. Scans stop admission at 250,000 nodes/90 seconds, with 100,000 nodes/15 seconds per item and a 10,000-child/5-second listing budget. Unmeasured items are retained as unknown, and partial/cancelled results are lower bounds. File system calls themselves can be delayed by an unresponsive mounted filesystem; limits are cooperative, not hard syscall deadlines.

Eight locations are cached in memory for five minutes. Refresh and access retry clear/rebuild measurements. Cancelled scans are not cached. Navigation cancels superseded requests; generation guards reject their results/progress. Traversal never follows final symlinks, checks opened directory identity and rechecks file metadata during allocation reading. Removal additionally uses the existing ownership/path/ancestor/manifest checks and original Trash workflow. Scan access does not relax removal protections.

Full Disk Access cannot be granted or reliably queried through a public macOS API. The shared permissions panel probes one directory-entry listing in Safari, Mail and Messages, reporting actual readable/blocked/missing/unknown capability rather than a fabricated permission-switch state. It reads metadata only. Users enable the installed app in System Settings themselves and handle authentication. File & Folder privacy descriptions cover Desktop, Documents, Downloads, removable and network volumes. No camera/microphone/Screen Recording/Accessibility access is required for this disk workflow. Ad-hoc development signing can require permission to be granted again after builds. Developer ID release signing remains outstanding.


## Analyze actions — 3.2.1

Files now open a compact, centered glass dialog showing name, measured size, Reveal in Finder and Move to Trash. One confirmation gives Trash recovery information; no generic review/preview/results sheet intervenes. Folders still drill into the map and expose the same two context actions. Partial sizing does not block moving a known directory itself. DiskTrash moves the explicitly selected root with identity, parent, containment, ownership, protected-path, exclusion and running-app checks; it never recursively deletes or follows child links. Existing Clean/uninstall recursive validation is unchanged. Outcomes and recovery paths remain in local sanitized history. Analyze folder selection now uses SwiftUI’s managed folder importer with a Go to folder path fallback.

## Bonsai 3.3: immersive Analyze actions

Full-window action scene, original size-dependent bonsai foliage in folder tiles/sidebar, brief success-only pruning and static Reduce Motion response. Two main file actions and one Trash confirmation remain. No page transition or ambient animation loop is added. See Bonsai-3.3-Design.md and Analyze-Verification.md for accounting, behavior and verification limits.

Bonsai 3.3.1 replaces the vector Analyze bonsai with the shared original realistic pine portrait. A centered vertical composition places the tree above file actions. Measured-size canopy broadening and success-only pruning retain the original texture and fixed pot/roots. New scalar/root tests and native rendering verification accompany the change. Original PNG resources are unchanged.
