# Bonsai 2.5 — nature identity and inline Apps review

The user requested the approved minimal top-navigation layout for Bonsai Nature. Otto remains separately saved and unchanged. Bonsai retains original AI-assisted oak/maple/pine portraits and warm bonsai identity, with peach accents, mint/sky/peach/butter/seafoam section gradients fading into warm ivory, and dark evergreen text.

## Layout and navigation

The sidebar, duplicate page headings, split hero cards and supporting marketing notes are removed. A centered 544 × 42-point Liquid Glass capsule rail sits at the top: mascot/More, Clean, Apps, Optimize, Analyze and Status. Twelve-point gaps, monospaced labels, a persistent white selection capsule and moving black-text mask match the approved navigation. The companion pill sits to the right. The More menu is again anchored below the mascot using the rail’s shared width calculation.

Nature landings place one animated tree portrait and a small species caption above two quiet serif lines and one orange action. Clean uses an English oak, Optimize a Japanese maple and Analyze a Scots pine. Busy state shows measured progress and Cancel. Artwork scales to available height; the root minimum is 980 × 650 points. Navigation remains visible during cleanup results, so switching sections does not require closing the review list. Scope choices are retained in Settings and cleanup results; History remains in Settings/Command-6. With the navigation rail focused, arrow keys wrap the five primary tabs and return from History. Command-1…6 remain.

## Motion, artwork and accessibility

The retargetable selector uses 0.38 response/0.90 damping. Page switching retains a 0.10-second outgoing fade and 0.32-second directional ease-out entry. Backgrounds crossfade over 0.46 seconds. No animation queue or deferred routing is added. The three transparent tree PNGs are cached once and bundled locally. A native SpriteKit view renders a continuous 12 × 18 mesh (247 vertices) at at most 30 fps. Canopy displacement grows toward the crown while the lower 19% stays planted; a secondary wave adds foliage movement. The maple is more flexible, the pine quieter. At most six leaves (three pine needles) drift and tumble; objects are reused. No whole-image floating, frame sequence, timer queue or new image generation.

Playback is gated by Reduce Motion, view presence, scene phase, app activation/hiding and window visibility/minimize/occlusion. Removing the native view pauses it, removes observers and releases its scene. Resume clears the frame timestamp without advancing hidden time; frame gaps are capped. Reduce Motion substitutes the unwarped static image and removes the native renderer. Decorative rendering ignores input; captions expose the species name. Tree-Motion-Results.txt covers actual SpriteKit scene updates, geometry bounds/topology and clock behavior. SKView's native window lifecycle and system accessibility settings still require GUI/system checks.

Light mode preserves the approved bright surfaces and evergreen text. Dark mode has forest, warm cedar, blue slate, olive and teal section gradients over a charcoal forest base, warm cream text, soft sage details and the same peach primary actions. Cards, search, chart tracks, menu icons, sheets and companion resolve a shared native adaptive palette. Standard native actions use evergreen/sage tint for readable text; the primary peach buttons keep fixed dark lettering. Dark treemap tiles use brighter fills and dark ink to retain readable labels. The bonsai's eyes/nose retain dark ink. Clean Screen keeps its intentional black screen and exit controls. Settings adds persistent Light (default), Dark and System choices with keyboard/VoiceOver selection. Unknown saved values fall back to Light. System removes the app override, allowing macOS appearance to resolve the colors. Each presentation root observes the same app-scoped preference, including sheets and companion. The approved top rail and animation timings remain; selected black labels on white still read clearly.

Native public glassEffect applies to the header rail, companion, segments and secondary controls on macOS 26+; macOS 14–15 use material. Reduced Transparency/Increased Contrast use opaque control surfaces. No planet maps, franchise images, characters, logos or private shaders are bundled in Bonsai Nature. Otto keeps its separately attributed maps.

## Independent saved Otto

Otto’s app, source archive and individual bundle-file hashes are checked against the pre-edit record. This change does not rebuild or modify Otto. Preferences/history/identifiers remain separate; both products protect each other’s local audit/cache/identifier roots. No automatic migration or new DMG. See Verification.md for current checks and release QA limitations.

## Pointer and icon

Every explicit Button uses a shared handCursor modifier; disk/process menus and companion native segments also use it. After the user reported that 2.4.0's non-intercepting AppKit overlay did not display a hand, 2.4.1 removes that overlay. On macOS 15+, SwiftUI's native pointerStyle(.link) applies a hand to enabled controls, with .default for disabled ones; SwiftUI manages hit testing and restoration. See [Apple's pointing-hand documentation](https://developer.apple.com/documentation/swiftui/pointerstyle/link). macOS 14 uses onContinuousHover with an identity-owned cursor setter: continuous entry reapplies the hand, while exit, disabling, deactivation and removal release only the current owner. Late callbacks from a previous button cannot reset a newer hover. No cursor push/pop stack, native cursor overlay or hover timer remains. The available automation has no hover operation, and the user confirmed the hand now appears in the final 2.4.1 build. Older-system and additional lifecycle permutations remain manual.

The original editable AppKit icon shows a leaf-carrying bonsai on a mint tile. Small ears, large muzzle and simple leaf distinguish it from the old dark face-only icon; whisker/vein detail reduces at 16 pixels. All ten native PNG representations and the ICNS are generated during the reproducible build. Header mascot and the frozen Otto icon remain independent.

## Apps reference refinement

The user supplied Mole's expanded UninstallPKG row. Installed Mole was inspected read-only to compare disclosure, per-file selection and persistent removal summaries. Bonsai now uses the same clear hierarchy in its own adaptive nature palette: 40-point app icon, name, compact version/size/activity line, right-aligned removal total, disclosure and group checkbox. Expanded rounded rows show Ready to remove, Needs review and Unavailable sections, with individual checkboxes, kinds, middle-truncated selectable paths and right-aligned allocated sizes. Personal settings/support remain manual selections; inaccessible/privileged paths explain their limitation. Paths reveal in Finder; contextual actions copy the path.

Four explicit sort buttons show active direction, reverse on a second click and retain state across sections/relaunch. The toolbar and selected-path footer stay outside the scrolling list. User apps are shown first by default; Filters includes system apps. Search accepts app names, identifiers and paths. Inspection uses local per-row progress, cancellation and retry; disclosure alone never selects files. Expansion respects Reduce Motion. The approved top navigation, native pointer handling, living trees, icon and saved Otto are retained.

## 2.5.1 summary target, hover and Software tabs

The full right-hand summary and rotating chevron form one padded Button. Clicking only expands/collapses; selection remains in its separate checkbox. Inspected rows show checked eligible bytes to remove and unchecked eligible personal-data bytes to review, separated by a middle dot. Units adapt to KB/MB/GB and zero is 0 MB; unavailable/partial candidates are excluded from actionable totals. Before inspection the target says Inspect files. VoiceOver exposes the summary and disclosure state.

The app card gains a sage wash and thin border on hover; the wash sits behind content and decorative borders ignore input. Hover clears on removal, deactivation and busy state. SoftwareTabs replaces only the Software-specific QuietSegments instance: trash/refresh/power symbols, fixed-width stable labels and a single spring-retargeted matched selection capsule over the existing public glass/material/opaque fallbacks. Press feedback is subtle; focus rings and arrow wrapping remain. Reduce Motion disables spring, rotation, scale and hover interpolation. The other approved navigation controls remain unchanged.

## Optimize 2.6

Keeps the top rail and animated Japanese maple. Landing opens a read-only selection review. Finder previews, System checks and Disk health are grouped full-width rows with native icons, duration bounds and details. The fixed glass footer leads to a confirmation sheet listing only selected tasks and prerequisites. Refresh tasks require explicit acknowledgment; disk verification is excluded from recommended defaults. Technical commands are folded into details.

Execution uses one sequential runner, a bounded task progress list and cancellation. Results group Completed, Needs attention and Skipped, with Checked/Refreshed labels and expandable output/post-checks. Review unfinished tasks repopulates selection for a new confirmation, never automatically retries. Selection and results live in AppModel so page navigation retains them. History stores the existing sanitized local outcomes; current result view is session-local and earlier runs remain in History. Reduced Motion disables view transitions and uses the existing static tree fallback. No performance score or automatic unreviewed restart is introduced.

References inspected: https://github.com/tw93/Mole and https://mole.fit/ (2026-10-04), plus installed Mole 1.15.0. Mole's public repository is the CLI; native-app UI observations supply visual reference only. Original Bonsai code/assets and frozen Otto remain separate.

## Optimize 2.7: inspected Mole flow

Supersedes the 2.6 full-page task review. The user supplied a Mole QA reset script and authorized its use. A checked copy was run before editing Bonsai; the original remains untouched. Ownership/symlink checks, verified private backups, app-closed/state-change checks and CUA launch replaced the script's direct launcher. It cleared only the trialUsage_optimize entry listed in Mole's trial record and its local trial.dat. Backup retained counter 2; after one authorized Mole Optimize run the new counter was 1. No app binary, purchased-license account or unrelated preference was changed. This QA helper is outside Bonsai and excluded from its source archive/bundle.

Observed Mole 1.15.0: one centered planet through landing/progress/completion, compact rolling checklist, Review results/Rest actions and flat full-window grouped details. Bonsai uses its original living maple/sky-forest colors and approved top rail. A compact sheet collects task choices and confirmation instead of another dashboard. A white capsule leads to the sheet; its refresh acknowledgment remains required. The running hero uses the actual active task/group and last four started tasks; completion separates checks/refreshes/attention/skips. Details temporarily hide the top rail, with whole-row disclosure, hover wash, section separators, optional retry review and History. Escape closes review/details. Rest returns to landing without discarding last results. No fabricated success, unsupported service button or new maintenance command is added.

Typed MaintenanceScreen replaces string stages. Pure MaintenanceSummary distinguishes completed changing tasks from completed read-only checks; unknown completed tasks are classified separately and not counted as refreshes. Two fixtures verify mixed results, unknown completion, zero results and cancellation headlines. Adaptive colors, native hand cursors, current glass accessibility fallback and existing tree lifecycle remain. Animation/display frame rate and minimum-window/accessibility permutations still require native QA.

## Optimize 2.7.1: direct action

Supersedes 2.7's default sheet entry. A further authorized native Mole run and appended operation log confirmed immediate dispatch, a stationary hero and compact progress. The main Optimize capsule now calls AppModel.optimize() directly; its explicit available routine plan is independent of custom selection and cannot include disk verification. The sliders control opens custom review separately, preserving optional confirmation. Hover help describes the actual commands' effects. The maple no longer shifts/scales between stages; narrow progress keeps two recent rows and larger layouts keep four. No artificial command delay or fabricated task is added. Five supported operations remain unchanged. See MOLE-OPTIMIZE-OBSERVATION.md for reference evidence.

## Software tabs 2.8.2

The glass track uses a continuous 19-point radius and a 40-point-high ivory tile with a 14-point radius; controls have fixed 106-point frames with four-point gaps. Rounded labels remain stationary. The active symbol appears over a peach square badge; removal, downloading and dawn graphics distinguish the three destinations. A persistent spring-driven offset and matching contrast mask retarget together rather than replacing the selected capsule. The decorative dark-label layer cannot intercept clicks or duplicate accessibility. Subtle press tint/hover wash and a one-point focus outline avoid scale jumps and native focus bloom. Light/Dark and public glass/material/opaque fallbacks remain; Reduce Motion disables movement/interpolation.

## Apps services 2.9.0

Software controls shrink to 94 × 32 points with two-point gaps and three-point rail padding. A borderless quiet fill replaces the outlined glass track; the ivory tile and contrast mask keep their existing spring. Keyboard focus uses fill rather than an outline. Startup follows login/background/services groups with real switches and icons; registration details stay secondary. Duplicate plist/BTM agent rows merge by label and kind. Updates shows recent results immediately and publishes checked sources without blocking navigation; freshness/stop/retry/opt-out remain visible.

## Apps 2.10 final scale and rows

The accepted compact design is increased ten percent: 0.80 × 1.10 = 0.88 of original, applied consistently to main content, sheets and companion. Native window controls, menus and OS permission alerts stay at system size. Updates uses a minimal available section with versions/source/Update action and a second installed-app list with hover tint, Finder and Uninstall. Startup keeps the same top tabs, switch rows, app icons and separate login/background/services groups. Saved state is visible instead of disappearing on relaunch. Final dark layouts and keyboard switching were inspected in the installed app.

## Apps 2.10.1 pill buttons

Software tabs use full capsules for the selection surface, moving contrast mask, button hit shape, track, hover, keyboard focus and press tint. Labels and peach icon badges stay stationary; the accepted spring and accessibility/reduced-motion behavior remain. Overall content scale increases five percent from 0.88 to 0.924; default window increases to 1096 × 714. Existing restored window dimensions follow macOS state restoration.

## Status 2.11

Mole's installed Status page informed the fixed dashboard and grouped list. Eight quiet metric cards stay visible above anchored NAME/MEM/% CPU/PID headers. Only app/process rows scroll. Rows show real app icons, helper-count badges, combined resident-memory/CPU values, restrained CPU bars, subtle hover tint and a consistent action menu. Clicking a row opens a live, scrollable member inspector. Measurement and interface explanations are popovers so opening them does not shift the dashboard. Unavailable and partial inputs stay explicit. The approved 0.924 interface scale, nature palette and rounded Software controls remain unchanged.

## Page transitions 2.13

The rail stays anchored while pages glide/fade. A sparse field of 24 small leaves spans the full root window. Tree canopy bending and leaf drift share a monotonic 1.65-second breeze: a sine-squared envelope softly rises and settles, and its integral determines leaf travel speed. Per-leaf staggered fading peaks at24% opacity, widths7–13 points, with slower turns and less flutter. Ambient tree leaves also turn more slowly and use the same botanical silhouettes and colors. The full-window Canvas draws at the tree's30fps rhythm only during a switch, excludes input/accessibility and is removed at completion or cancellation. Reduce Motion bypass remains. Scale0.924, approved Software pills and fixed Status are preserved.

### Full-window refinement 2.12.1

The user requested that the sweep cover the entire app. The decorative Canvas now spans the root view rather than the lower page container. An eight-by-six jittered field spreads leaves to the top rail, sides and lower corners; gentle directional drift preserves the selected species and short lifetime. The full-window layer still excludes all input and accessibility.

## Canopy arrival 2.14

Page switching begins with small translucent leaves throughout the window. They curve around and gather into the visible destination tree rather than continuing as an independent drifting field. The 2.1-second sequence closes on the tree's own small ambient leaves: position, size, angle, flutter and opacity match across the two renderers, then idle movement continues. Actual layout anchors keep the landing attached to the canopy as the window changes size. Extra leaves softly dissolve in the crown. No tree is added to Apps, Status or result layouts. The fixed rail, short content glide, approved scale, Software capsules and Status layout stay unchanged. Reduce Motion bypasses the transition.

## Bonsai 3.0 identity and motion

User approved replacing Bonsai with Bonsai. Original cherry blossom, black pine and maple bonsai portraits in shallow ceramic pots replace the larger tree specimens. The bonsai emblem and app icon are original editable vectors. Light mode uses ivory, blossom pink, moss and ceramic accents; dark mode uses quiet plum/forest/earthen gradients. Main navigation, Software capsules and 0.924 scale remain.

The supplied Spirit Tree video informed slow petal circulation, not copied visuals. A 4.2-second full-window transition now follows gentler curved paths with a soft lateral curl. Twelve cherry petals, eight maple leaves or six pine particles blend into continuously orbiting ambient poses with subtle depth/opacity changes; extra particles dissolve. Small canopy motion is slower, and pot/root geometry remains planted. Navigation still changes immediately; rapid choices replace the flight, and reduced-motion/input safeguards remain. All image prompts and provenance accompany the assets.

## Bonsai 3.1 — current behavior

Page slides/fades, background interpolation, full-window leaf overlays and transition breeze propagation are removed from RootView. Content reads model.page directly; only control selection/press feedback and continuous idle trees animate. Historical transition sources remain unconnected. The companion uses the existing shared sampler/histories and six compact cards; process clicks select a shared main-window glass inspector. Public libproc detail collection is an actor, on demand, bounded and identity-validated before/after reads. Stale/relaunched process identities disable controls; SIGTERM/SIGKILL each have explicit review and post-sample audit. Missing metrics remain unavailable. Activity totals derive from actual successful history outcomes. The new jade app icon is original generated raster artwork; the compact in-app emblem remains vector. Artwork prompts/provenance are local resources.
