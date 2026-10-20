# Current architecture additions — 3.6.9

DiskExplorer uses bounded asynchronous native traversal, inode-based global allocation accounting and root-only disk manifests. Completeness is independent of numeric labels; map scope is not APFS volume usage. Shared tree motion uses SpriteKit with 60 FPS minimum scheduling and capped screen cadence; reduced/inactive modes suspend work.

MaintenanceBackend validates a pinned source/adapter manifest and dispatches the reviewed upstream subset. BonsaiMaintenanceTrash owns allowlisted recoverable mutations; diagnostics are explicitly distinguished from applied maintenance. Clean/Analyze/uninstall remain native filesystem services using public Mole rules/protection data.

DirectUpdates validates full Sparkle ZIP signatures/length/exact build and Electron ZIP digests, archive containment and strict original publisher requirements before atomic replacement/recovery. Appcasts distinguish full archives from nested deltas and guided packages. Optimize details uses adaptive two-column task rows without a report ScrollView; task output is a separate bounded popover. StoreUpdates authorizes a one-shot fixed updater wrapper supplying mas's required approving-user IDs. It collects bounded output/exit evidence and verifies the installed version. SparkleUpdates is conditionally compiled for real signing, with publisher handoff for unsupported non-ZIP releases in ad-hoc builds. Public catalog names require independent consent. See current verification for actual runtime coverage.

Earlier architecture notes below are historical where they differ.

# Architecture and safety review

- `CBonsai`: small C bridge to Mach CPU/VM counters, 64-bit route interface counters, and libproc process identity/usage. All buffers have fixed bounds. No kernel extensions or private SMC driver.
- `BonsaiCore`: filesystem identity, policy, bounded scanners, Trash actions, command runner, reviewed app association, update sources, startup services, telemetry collector, power assertions, audit store, and treemap layout.
- `Bonsai`: MainActor presentation state, SwiftUI sections, AppKit folder pickers/Finder actions/screen curtain, and shared MenuBarExtra.
- `BonsaiVerify`: executable test harness generated from the XCTest cases. Mutation tests use unique disposable directories and an injected fixture Trash destination. Production defaults to Foundation’s real Trash API.

Filesystem scans execute off the main actor, do not traverse user symlinks, and deduplicate physical allocation by device/inode. Contained app-bundle symlinks are recorded without following them; external symlinks make a measurement partial. Fixed root-owned `/var`, `/tmp`, and `/etc` aliases expand to `/private/...`, avoiding Foundation’s surprising reverse standardization. User symlinks remain visible to policy validation.

Each review carries a complete descendant manifest plus a parent identity. Cleanup refuses broad roots, protected locations, other owners, stale contents, changed parents, running associated or contained apps, incomplete scans, and nested selections. After a second manifest scan it revalidates root identity and running-app state, then calls `trashItem`. Adjacent selected items can move independently because parent object identity, rather than parent directory mtime, is compared. Every item returns an outcome; no recursive permanent deletion is used by the app.

Recovery records include the original path and returned Trash location. Finder Put Back may be offered; otherwise move the item manually to its original path. The app never empties Trash and does not claim the estimated bytes have been reclaimed. Hardlinks outside a selected tree, cross-entry hardlinks, and APFS clones can retain allocated storage.

This is a cooperative filesystem safety model, not an atomic snapshot or defense against a hostile process with the same UID changing a tree in the final interval between checks and the Foundation Trash operation. File reads may also be held up by kernel/network filesystem I/O; cancellation is observed between operations. Close dependent apps before cleanup. No privileged helper is installed.

Clean and disk passes have 90-second and 250,000-node cumulative budgets, with at most 100,000 nodes and 15 seconds per location. Dependency discovery is depth-six and bounded to 15,000 directories / 60 seconds, with 10-second artifact measurements. Application inventory is bounded to 90 seconds with per-app measurements capped at 30,000 nodes / 3 seconds; only root snapshots are retained in inventory, and full bundle manifests are refreshed for uninstall review. Disk cache keeps up to three session scans for five minutes; incomplete refreshes do not replace a complete cache. Disk and cleanup manifests live only in memory.

A single cancellable operation controls user mutations and scans. UUID generations and disk-root checks suppress obsolete progress/results. Navigation between sections and shared telemetry remain responsive. Telemetry uses a separate actor, one two-second loop, and at most 60 history samples. Process samples are bounded to 4,096 entries; interface inventory is bounded to 64 and two MB of route data.

Command execution uses an executable allowlist, literal arguments, no shell, inherited user privileges, null stdin, disabled Homebrew analytics/automatic updates, nonblocking bounded stdout/stderr, time limits, SIGTERM and a bounded SIGKILL fallback. Cancellation of a parent command cannot guarantee cancellation of package-installer subprocesses or kernel work already started. Post-checks and captured output explain partial outcomes. Homebrew catalog refresh is separately authorized for each explicit update check; each install has its own confirmation.

Startup controls revalidate the plist identity and persistent state, change the user’s launchctl state, attempt a session bootout/bootstrap, and remeasure the inventory. Failed session changes are explicitly partial. System agents/daemons are read-only. A restored persistent setting may need logout/login. Enable previews display the actual Program/ProgramArguments. Modern third-party login items remain a native Settings handoff.

Process termination is current-user-only, protects PID 1 and Bonsai, checks PID plus start seconds/microseconds plus UID, sends only SIGTERM, and samples again to report whether it exited. App pins persist by bundle path and owner; individual process pins use name and owner. Legacy name pins are recognized. Network rates use monotonic timestamp differences; changed interfaces, counter resets, equal timestamps, and gaps of 30 seconds or more establish new baselines. Interface rates remain separate to avoid VPN double counting.

Power assertions are idempotent and released when disabled, on app termination, and in deinit. Screen curtains cover each display, swallow local key events, use key-capable windows, and provide Escape, an Exit button, and a timeout. No animation is required, so reduced-motion settings need no exception.

Remake additions: CacheRules scopes Chromium profiles and Electron cache leaves; Discovery adds bounded identifier inventory, potential remnants, installers and optional Trash-app metadata notices. Remnant removal repeats an absence check immediately before mutation. Exact identifiers and namespace-boundary running-family patterns avoid over-blocking unrelated apps. Custom exclusions are applied to cached reports and added to the removal policy, including manual disk/uninstall reviews.

Application inventory now reports completion of the configured roots/depth independently from partial per-app size measurements. Dependency discovery propagates global truncation and errors. Appcast XML rejects DOCTYPE/external entities and oversized data; stable/macOS metadata respects minimum/maximum OS and Apple Silicon requirements. Dotted numeric versions are compared with trailing-zero normalization; ambiguous strings are not inferred. HTTPS metadata requests are ephemeral, cancel-aware, capped and opt-in. Appcast packages are never downloaded or installed; the publisher updater remains responsible for verification.

The UI uses top navigation and a category/list/scrollable-inspector clean layout; a six-card status grid and shared companion popover. Timer-backed Keep Screen On releases on deadline and quit. Superseding disk navigation suppresses obsolete errors as well as progress/results.

## 1.3 presentation

PlanetView embeds public SceneKit in SwiftUI with bounded 24 Hz monotonic rotation, native visibility/lifecycle guards and reduced-motion support. Asset maps and attribution are bundled and sealed. AppModel retains bounded download/upload histories from the same timestamped network-rate calculation. Root presentation swaps pages with restrained transitions; mutable workflows continue through existing AppModel and BonsaiCore validators.

## 1.4 navigation presentation

RootView tracks the displayed page separately from the model selection to attach an explicit transition transaction. No artificial timer delays or retained screenshots are used. Background and Software selection animations are scoped to their routing values, avoiding animation of unrelated telemetry/inventory updates. GlassSurface centralizes macOS 26 native glass, older material, opaque accessibility fallbacks and disabled interaction.

## 1.5 anchored menu

RootView owns menu visibility and action routing. BonsaiDropdown supplies focused keyboard rows and a decorative material surface; a full-window clear backdrop supplies dismissal. Software selection moved into AppModel for explicit Updates handoff and retention. Doctor groups only the existing Spotlight/power read-only tasks, uses the existing operation gate/cancellation, and records standard outcomes. About reads bundle metadata rather than assuming a version.

## 1.6 navigation refinement

RootView calculates rail width, selector offset and dropdown anchoring from shared navigation metrics. A persistent selection capsule animates position/width; a matching masked decorative text overlay maintains contrast without duplicate accessibility elements. Outgoing page removal uses a short fade; incoming pages use an ease-out slide without scale. Updates remain immediate and unqueued. Core scanning, mutation and command services are unchanged.

## 2.0 separate identities and nature presentation

Otto is a saved independent package with COtto/OttoCore/Otto/OttoVerify modules, own bundle/preference identifier and audit directory. Bonsai now uses NatureLanding/Canvas instead of PlanetView/SceneKit and has a persistent six-destination sidebar and bottom-anchored menu. Scope selection is exposed before scanning. Both local audit roots/cache names/app-identifier namespaces are protected. Core operation gates, command bounds, filesystem revalidation, consent and recovery services remain. Nature decorative timelines are bounded and use motion/activation/minimize guards.

## 2.1 minimal top shell

Bonsai Nature returns to the approved persistent top capsule selector/contrast mask and shared dropdown anchor metrics. NatureLanding now uses centered geometry instead of a sidebar/split hero. Main navigation is always visible during clean results. History remains a secondary route, with arrow navigation returning to the main five-page rail. No core service, permission, history domain or saved Otto source/bundle changes.

## 2.2 tree portrait resources

NatureScene selects oak, maple and pine resource names and accessible common/botanical captions. TreeArtwork loads the three local NSImages once. NatureIllustration uses the existing bounded lifecycle-aware timeline for small root-anchored transforms; Reduce Motion renders static images. The build script bundles Trees/ PNGs and creation provenance before signing. No runtime image generation, network dependency or core workflow change.

## 2.3 living tree renderer and light palette

LivingTree wraps a transparent native SKView. LivingTreeScene deforms the cached tree texture with a 247-vertex SKWarpGeometryGrid and reuses a fixed leaf-node pool. TreeWindDynamics and TreeAnimationClock are shared with the executable presentation verification script; no GPU compiler package or runtime external asset dependency is added. TreeWindView controls pause/resume from app/window notifications, visibility and the SwiftUI requested-playing flag, and tears down observers/scene on removal. The 30 fps limit and pause behavior use public [Apple SKView APIs](https://developer.apple.com/documentation/spritekit/skview). The 2.3 renderer initially used a light-only scheme; 2.4 appearance support below supersedes that constraint. Clean Screen remains intentionally black.

## 2.4 appearance and owned cursor rectangles

Appearance.swift defines the persistent Light/Dark/System preference and named NSColor dynamic providers, evaluated in each receiving native appearance. Every root/sheet/companion applies the same app-scoped AppStorage preference; the default remains Light and System passes no preferred scheme. No process-global mutable palette or new dependency. HandCursor.swift now uses native SwiftUI pointerStyle on macOS 15+ and an identity-owned onContinuousHover fallback on macOS 14. This supersedes the original NSView cursor rectangles, which the user confirmed did not show a hand in SwiftUI. verify-appearance.sh compiles the actual sources to test appearance resolution/contrast plus enabled/disabled entry, continuous reapplication, transfer, late exit, repeated teardown and removal/deactivation ownership. Native pointer entry/exit remains a manual check because the automation has no hover API. The procedural icon generator emits a new original bonsai/leaf design at all native sizes.

## Apps review and ordering (2.5)

SoftwareStore is retained by AppModel independently of the tab view. It owns typed persistent sort direction, system filtering, selection, expansion, a bounded icon cache and five-minute association reports. It queues at most two utility workers. Cancellation and generation checks reject late results even when a worker ignores cancellation. Refresh retains only eligible selections still present; clearing during inspection cannot reselect anything. Paths shared by reports are deduplicated before totals/review. Only successful Trash outcomes invalidate affected reports; previews leave files and plans intact.

AppSortOrder uses allocated bytes or dates with stable natural-name/path ties and missing values last in both directions. Installed is a folder creation date, not install history. UserCacheLocation reads the per-user Darwin cache directory with confstr; failure grants no broader fallback. AppInventory deduplicates overlapping roots and labels bounded sizes. AppAssociationReport measures each candidate independently (30s/150k nodes overall, 8s/50k per candidate), preserves complete mutation manifests and applies ownership/protection/exclusion policy. Application and generated caches are defaults only after explicit app selection; preferences/support/session/saved state/launch items require individual review. Unique app-name support candidates are unproven and manual. Helper paths come only from SMPrivilegedExecutables declarations; the app never elevates deletion. Root-owned/system helpers remain revealable but disabled.

AppUninstallRow presents file groups inside a rounded row with right-side selection. SoftwareView owns the internal scroll viewport, keeping the sort toolbar and selected-path footer visible. AppModel transfers exactly the checked paths to the existing confirmation sheet, then TrashService remeasures/revalidates identity, descendants, parents, ownership, containment and running apps immediately before each move.

AppRemovalPlan exposes removalBytes for checked eligible paths and reviewBytes for unchecked eligible non-generated data. Neither includes unavailable candidates. Disclosure is a single native Button containing both summary and arrow; it changes only expansion. App-row hover backgrounds and decorative outlines never intercept input. SoftwareTabs is scoped to the Apps rail, with stable label geometry, one matched selection capsule, explicit click/arrow focus and accessibility fallbacks. These presentation refinements add no scanning or filesystem action.

MaintenanceRunner resolves selected catalog IDs in stable order, deduplicates tasks and runs sequentially. It checks cancellation before and after the async progress callback; remaining tasks become itemized Skipped outcomes. Command execution and per-task execution are injectable for fixture tests. AppModel retains the selected tasks, current active ID, completed outcomes, timestamp and view stage; generation guards reject stale progress and completion. Audit presentation can be suppressed for the dedicated result page while still saving History. MaintenanceTask retains completed operation output on cancellation before/during verification and on verification exceptions. Post-check success confirms a system command response, not cache completeness or repair effectiveness.

Optimize 2.7 uses typed overview/run/complete/details stages in AppModel. A single hero owns the maple across progress/completion; task review is a modal sheet, and the details stage hides the shared navigation rail. MaintenanceSummary independently counts known refreshes, read-only checks, unknown completed outcomes, attention and skipped items; UI does not label checks as optimizations. Result disclosure owns only presentation expansion/hover and preserves outcomes. The QA trial-state helper is workspace-only tooling supplied by the user, not an Bonsai runtime dependency or product capability.

Optimize 2.7.1 separates direct routine planning from custom selection. MaintenanceRunner.quickPlan admits only explicitly recommended available commands; disk verification is always optional. AppModel.optimize rejects concurrent/empty runs and delegates to the existing cancellable audited runner. One fixture verifies routine IDs, optional exclusion, availability and the exact sequential executor trace; it runs no real maintenance.

## Bonsai 2.8 uninstall and inventory

Inventory is a separate read-only task/generation rather than occupying the mutation gate. AppInventory returns metadata/root snapshots first; AppSizePipeline admits two off-main utility workers with a 90-second admission deadline and 30,000-node/3-second per-bundle measurements. Identity is revalidated before and after sizing. Cancellation is cooperative between filesystem operations; kernel I/O may outlast a requested stop. MainActor generation guards reject late measurements after refresh or removal. Unknown/partial sizes never authorize mutation; associated-file inspection creates a fresh complete manifest.

SoftwareStore caches sorted/filtered presentation by inventory revision, query, sort and system filter. Two association workers and existing five-minute report caches remain independent. Selection no longer forces expansion. Ready defaults include exact-identifier logs and caches; personal-data review remains manual.

UninstallGroup snapshots the original app, associated files and checked IDs before mutation. AppModel compares the confirmed selection exactly, repeats running-app checks, cancels stale sizing, and calls the existing ownership/path/identity/descendant-validated TrashService. A cancellable progress callback reports the current item and completed outcomes before each move. UninstallSummary normalizes physical root aliases and deduplicates moved paths; counts apps/data/failed/cancelled without labeling checks or failed paths as removed.

The dedicated SoftwareUninstallView renders list/run/complete/details stages. Results preserve original app grouping even after bundle deletion; row expansion is presentation-only. Finder reveal uses the returned recovery path; original path/name and Put Back/manual restoration instructions are visible. Local sanitized audit remains persistent; detailed stage/snapshot retention is current-session only. Clean’s existing preview/confirmation/result workflow is unchanged. The public name is Bonsai while app.ottercare.mac.nature retains existing preferences. No QA fixture/helper/backup is a runtime dependency.

## Apps 2.8.1 explicit selection

SoftwareStore.activateApp selects an unchosen app and otherwise changes only disclosure. toggleApp is the group-checkbox selection control; deselection clears its paths and expanded state. toggleExpanded requires selection. Chosen app state is independent of whether any eligible file is checked, preserving access to blocked/empty review explanations while removal remains gated on nonempty eligible selectedItems. File/group-path controls cannot implicitly deselect an app. Clear/invalidate/consume clear expansion consistently. AppUninstallRow conditionally mounts its summary/details only while chosen and exposes the current select/expand/collapse action through accessibility labels/hints. No Trash/command/network service changed.

## Software tabs 2.8.2 presentation

SoftwareTabs uses fixed geometry, one persistent selection surface and a matching offset mask for readable stationary labels. Animated properties are scoped to the selection and hover/press values. Binding changes are immediate; no timer, transition queue or scan dispatch is added. Three native Buttons retain focus/arrow navigation and selected traits. Decorative overlaid labels ignore hit testing and are accessibility-hidden. Existing GlassSurface/Palette/HandCursor remain; Reduce Motion sets selection/hover/press animations to nil. Core filesystem, selection, telemetry, command and network logic is unchanged.

## 2.9 Apps services

SoftwareUpdatesStore owns independent cancellable read-only tasks, generation publication guards, bounded incremental source reports, persisted metadata snapshots, freshness/throttling and opt-out. SoftwareUpdate/MetadataCheckReport are Codable; installation invalidates the cached row. AppModel keeps mutation operations separate. LoginItemInventory isolates a fixed-command C authorization reader and pure parser; LoginEntry separates app registration from background permission, groups parent helpers and resolves contained relative paths. UI service-label/type deduplication avoids UID-redacted path aliases. ProtectionBackend verifies pinned resource hashes and invokes identifier-only upstream protection before uninstall inspection/action or supported agent mutation. CommandRunner’s general executable allowlist still excludes Bash. See MOLE-BACKEND.md for unmigrated native services and the signed-helper distribution requirement.

## 2.10 Apps discovery and interface scale

InterfaceScaleLayout measures children in unscaled proposals then returns scaled bounds; drawing is anchored top-leading with 0.88 factor. Main content, presentation boundaries and companion scale once; native chrome remains OS-sized. Default window is 1044 by 680; minimum content footprint is 862.4 by 572. No bitmap UI scaling or new event interception is used.

SoftwareUpdatesPanel renders source-aware Update rows and the remaining physical app inventory with Finder/removal-review routing. SoftwareUpdatesStore cache schema 2 invalidates prior incomplete results, replaces cumulative results on fresh passes and tracks per-app checked/failed/unsupported states. Publisher metadata checks schedule three workers; Homebrew installed-cask catalog runs independently. BrewCatalog uses literal bounded local tap reads, physical app matching, truthful marketing/build comparison and source-priority deduplication. ElectronMetadata parses a bounded flat subset without executable YAML semantics. LoginInventorySnapshot persists current-user structured entries/read date; startup loading has its own task/generation and cache freshness state. Raw authorized diagnostics are not persisted.

## 2.10.1 presentation refinement

InterfaceScaleLayout factor is 0.924 (0.88 × 1.05), shared by existing main, sheet and companion boundaries. SoftwareTabs uses identical Capsule shapes for selection, mask and interactive decoration; no selection/store/backend behavior changed. Native chrome retains system size; default content window is 1096 × 714.

## Status 2.11 grouping and layout

StatusView owns a fixed two-row dashboard and measurement toolbar. Only StatusProcessList's native-backed List scrolls; sorting/search headers and size-accounting footer are outside it. Dashboard height is bounded to 248–344 logical points and adapts to the available content height. Details and input popovers have independent bounded scroll areas.

CBonsai captures libproc executable path, parent PID and validity of task counters in fixed buffers, capped at 4096 process records. Main-actor NSWorkspace metadata is copied into Sendable values before actor sampling, using public [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication?language=objc) bundle URL, localized name and PID. The SDK-required proc_pidpath minimum buffer is 1024 bytes; see [Apple libproc source](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c). No command arguments, environments or private process-power APIs are read.

ProcessGrouping selects the newest duplicate PID identity, groups by outer .app path plus UID, and uses only same-user measured older-parent ancestry with cycles rejected and each walk capped at 16 steps. Separate app copies/users and name-only matches stay separate; unassociated processes remain individual rows. Unknown counters remain unavailable, partial group totals carry a +, RSS addition saturates on overflow, and invalid/negative CPU values are excluded. Per-process CPU requires matching identity, valid non-reset counters and a monotonic interval under 30 seconds. RSS sums can include shared pages; aggregate CPU can exceed 100%.

Rows expose a representative PID, with member-specific inspection and graceful termination. Every signal still revalidates PID/start seconds/start microseconds/UID. Group exit disables controls; cancellation sends no signal. App icons are reused per path. Core grouping, parsing and collection occur on the telemetry actor; filtering/sorting use the bounded snapshot. This is measured association, not a verified launch reason or unique physical-memory attribution.

## Replaceable page motion 2.12

RootView tracks the displayed page separately from navigation selection. LeafSweepState holds one UUID-tagged flight, so rapid reversals replace rather than queue work and stale completions cannot remove a newer sweep. LeafPageTransition owns a cancellation-aware SwiftUI task; its .id replaces the old task/view. LeafSweepCanvas uses animatable progress and pure bounded LeafSweepDynamics to draw species-specific local paths. There is no idle leaf timer. Completion, window minimization, view disappearance, app deactivation and enabling Reduce Motion clear the flight. The overlay does not handle input or add VoiceOver elements. The standalone PageMotionVerify compiles the actual dynamics and actual Canvas, including render checks using ImageRenderer. No new filesystem, network, telemetry or maintenance behavior.

Full-window refinement 2.12.1 moves the non-interactive sweep overlay after the root safe-area/footer layout. Its 48-particle grid spans the entire window independently of page geometry. Nine-region and top/bottom coverage assertions protect against returning to the earlier canopy-only cluster.

## Shared botanical breeze 2.13

LeafSweepFlight now records a monotonic start timestamp. RootView propagates the optional flight through treeTransitionBreeze; NatureIllustration forwards it to LivingTree and its existing SpriteKit scene. Only a matching species accepts the flight. SpriteKit and a short-lived30fps TimelineView sample the same flight progress, avoiding separate animation clocks for the gust. TreeWindDynamics owns the sine-squared envelope and integrated leaf travel; roots remain fixed and mesh bounds are tested under signed gusts. BotanicalLeaf owns normalized paths and palettes used by both the Canvas and ambient SpriteKit leaves. The ambient tree's pause/resume clock remains separate and unchanged, so hiding a window does not catch up its idle motion. Root lifecycle cancellation removes the flight from both renderers. No idle leaf TimelineView exists.

## Canopy arrival 2.14

NatureIllustration publishes species-keyed bounds anchors. RootView resolves the destination's actual tree rectangle into the full-window overlay; LeafSweepDynamics validates and normalizes this geometry against the Canvas size. A 24-particle six-by-four field starts across the window. During the 2.1-second monotonic flight, eased cubic Bézier paths curve into the canopy. Leaves shrink and rotate to their landing poses. Extra leaves dissolve into the crown; three pine or six oak/maple leaves converge exactly on shared TreeLeafDynamics ambient positions, sizes, angles and flutter.

Canvas and SpriteKit use complementary opacity during the final handoff. SpriteKit's ambient time follows the flight until completion, then offsets its pause/resume clock to continue from the arrival phase without resetting. Planted-root mesh motion shares the same bounded breeze. Missing/invalid anchors and tree-free pages retain a quiet drifting fade, with no invented landing point. Latest-flight UUID validation, cancellation, deactivation/minimization cleanup, reduced-motion bypass, input and accessibility exclusion remain. Tests compile the actual Canvas and SpriteKit implementations and check all species, directions and seed extremes. No services or data-access behavior changed.

## Bonsai 3.0 continuity

Visible branding, CFBundleName/DisplayName and icon are Bonsai. Internal Swift package/executable and bundle identifier remain stable to preserve preferences, history and ownership protection. No storage migration or service changes. Default build/package targets now emit Bonsai.app and Bonsai release names. Historical Bonsai and independent Otto artifacts are retained separately.

The shared ambient pose function now uses continuous trigonometric orbits instead of a wrapped falling phase. Canvas Bézier gathering adds a bounded curl that vanishes at landing. Duration is 4.2 seconds; three species have bounded 12/8/6 ambient nodes. SpriteKit uses the same landing pose/clock and complementary opacity. The 247-vertex tree warp has slower, smaller sway and retains fixed lower vertices. New assets are cached once and bundled locally. Additional tests cover 40 seconds of orbit continuity and the longer duration; existing renderer, geometry, cancellation, stale-flight and handoff checks still run.

## Bonsai 3.1 — current behavior

Page slides/fades, background interpolation, full-window leaf overlays and transition breeze propagation are removed from RootView. Content reads model.page directly; only control selection/press feedback and continuous idle trees animate. Historical transition sources remain unconnected. The companion uses the existing shared sampler/histories and six compact cards; process clicks select a shared main-window glass inspector. Public libproc detail collection is an actor, on demand, bounded and identity-validated before/after reads. Stale/relaunched process identities disable controls; SIGTERM/SIGKILL each have explicit review and post-sample audit. Missing metrics remain unavailable. Activity totals derive from actual successful history outcomes. The new jade app icon is original generated raster artwork; the compact in-app emblem remains vector. Artwork prompts/provenance are local resources.

## Bonsai 3.2 Analyze and permissions

Analyze has a fixed sidebar and full-height treemap; it never scrolls the entire page. Immediate children appear largest-first, with 16 sidebar entries before optional expansion. Search reaches every listed entry. Positive-sized entries are grouped into at most eight map tiles, including all smaller items in the last group. Unknown/zero items remain available in the sidebar. Groups open a data-bound list; files open an inspector; folders drill down. Breadcrumbs retain the closest three parents and put earlier ancestors in a menu. Parent navigation and Command-R operate on Analyze, and Escape/Command-period stop scanning.

Whole Disk is a catalog of current home, /Applications, /Library and /opt. Actual volume usage is shown separately. The Files total deduplicates file allocation across this scan by device/inode; map weights show per-item sizes and may repeat cross-entry hardlinks. APFS clones/snapshots/purgeable storage are not guaranteed reclaimable bytes. Scans stop admission at 250,000 nodes/90 seconds, with 100,000 nodes/15 seconds per item and a 10,000-child/5-second listing budget. Unmeasured items are retained as unknown, and partial/cancelled results are lower bounds. File system calls themselves can be delayed by an unresponsive mounted filesystem; limits are cooperative, not hard syscall deadlines.

Eight locations are cached in memory for five minutes. Refresh and access retry clear/rebuild measurements. Cancelled scans are not cached. Navigation cancels superseded requests; generation guards reject their results/progress. Traversal never follows final symlinks, checks opened directory identity and rechecks file metadata during allocation reading. Removal additionally uses the existing ownership/path/ancestor/manifest checks and original Trash workflow. Scan access does not relax removal protections.

Full Disk Access cannot be granted or reliably queried through a public macOS API. The shared permissions panel probes one directory-entry listing in Safari, Mail and Messages, reporting actual readable/blocked/missing/unknown capability rather than a fabricated permission-switch state. It reads metadata only. Users enable the installed app in System Settings themselves and handle authentication. File & Folder privacy descriptions cover Desktop, Documents, Downloads, removable and network volumes. No camera/microphone/Screen Recording/Accessibility access is required for this disk workflow. Ad-hoc development signing can require permission to be granted again after builds. Developer ID release signing remains outstanding.


## Analyze actions — 3.2.1

Files now open a compact, centered glass dialog showing name, measured size, Reveal in Finder and Move to Trash. One confirmation gives Trash recovery information; no generic review/preview/results sheet intervenes. Folders still drill into the map and expose the same two context actions. Partial sizing does not block moving a known directory itself. DiskTrash moves the explicitly selected root with identity, parent, containment, ownership, protected-path, exclusion and running-app checks; it never recursively deletes or follows child links. Existing Clean/uninstall recursive validation is unchanged. Outcomes and recovery paths remain in local sanitized history. Analyze folder selection now uses SwiftUI’s managed folder importer with a Go to folder path fallback.

Bonsai 3.3 renders bonsai growth from existing measured allocation only. Original Canvas artwork is local and deterministic. A 30-fps timeline runs only for the bounded 1.6-second successful Trash response; its task cancels when the view leaves. Reduce Motion renders the final still state. No network request, filesystem backend change, new permission or external dependency is introduced.

Bonsai 3.3.1 replaces the vector Analyze bonsai with the shared original realistic pine portrait. A centered vertical composition places the tree above file actions. Measured-size canopy broadening and success-only pruning retain the original texture and fixed pot/roots. New scalar/root tests and native rendering verification accompany the change. Original PNG resources are unchanged.


### Independent Analyze lifecycle (3.8.4)

Disk traversal uses its own task, generation, progress, security-scoped folder and cancellation state. Primary busy/progress remains shared by Clean/Optimize, while Analyze operates independently. Root/scope/generation checks reject late results; file mutations invalidate map/cache state. DiskExplorer runs one bounded traversal in a utility detached task, leaving its actor available for cache reads/invalidation. A cache revision rejects traversal writes after invalidation. Visual map grouping caps individual entries at eight plus remainder, with a separate readable treemap weighting policy; original byte accounting is retained. MenuCompanionController uses one nonactivating floating panel, shared telemetry, active-display anchoring and scoped outside-click/Escape monitors removed on closure.
