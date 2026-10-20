# Current Mole boundary — 3.6.9

Pinned c430bac637929ebede043df81d3bef319428309c; source/licenses/integrity manifests are bundled. Optimize executes reviewed actual shell handlers plus explicit preview aliases. Native verified Trash handles recoverable cache/preference/list/saved-state changes; unapproved sudo and broad service/history resets are not performed. Detailed operation mapping: outputs/Mole-Optimize-Comparison.md.

Clean, disk accounting, telemetry, app inventory and file mutations use native Swift/AppKit services informed by Mole public rules. Uninstall/startup call Mole protection code. Updates uses publisher protocols, pinned mas and the existing Homebrew installation, because the public Mole CLI does not provide the proprietary GUI updater backend. No proprietary Mole binary/helper/trial/source is bundled.

Earlier integration notes below are historical where they differ.

# Backend provenance and supported boundaries

Source: https://github.com/tw93/Mole . Pinned revision: c430bac637929ebede043df81d3bef319428309c. The public README distinguishes the CLI from the separate native app; `mo update` is Mole self-update, not a third-party app update catalog.

Bonsai 2.10 actually invokes upstream protection logic through a constrained, read-only adapter. `Resources/ProtectionBackend/app_protection_data.sh` is an unmodified upstream file. `protection.sh` embeds byte-identical bundle_matches_pattern, build_regex_var, _ensure_uninstall_regex, should_protect_from_uninstall and official_uninstaller_vendor functions, with a small literal-identifier classifier wrapper. Runtime SHA-256 checks bind both scripts to their reviewed bytes before execution. Arguments are identifier-only, at most 512; no user command, path, shell expansion, deletion or network operation is exposed. General CommandRunner callers still cannot execute Bash. Shell startup-file environment hooks are stripped. Missing/tampered/failed/incomplete classification refuses the relevant action.

| Workflow | Actual engine |
| --- | --- |
| Uninstall inspection and final application protection | Pinned Mole classifier followed by native bundle association, ownership/path/identity and Trash services |
| Startup inventory and user-agent mutation protection | Pinned Mole classifier for critical/vendor labels followed by native inventory and launchctl review/change/revalidation/restoration |
| Clean, disk analysis and Trash | Existing native scanner/identity policy/Trash APIs, developed against Mole cleanup families; no CLI deletion |
| Optimize | Seven actual pinned Mole handlers through an allowlisted adapter; native commands for Spotlight/power/disk checks. See outputs/Mole-Optimize-Comparison.md for supported tasks and explicit gaps. |
| Updates | Native HTTPS Sparkle/Electron metadata, locale App Store lookup and Homebrew installed-cask/literal-tap metadata; the public CLI has no third-party update API |
| Managed login-item inventory | Apple sfltool dumpbtm, user-authorized read-only launch; the public CLI has no inventory API |
| Status and companion | Native Darwin/Mach/IOKit collection and power assertions |

**This is not an all-task Mole backend migration.** No proprietary native Mole engine, helper or licensing code is shipped. Routing every existing reviewed workflow through terminal-oriented scripts is a separate engineering change; the current app must not claim that integration is complete.

The login inventory uses the deprecated public AuthorizationExecuteWithPrivileges API only to run a hard-coded `/usr/bin/sfltool dumpbtm`. No arbitrary commands, caller paths, arguments, credentials or persistent privileged helper are accepted. After authorization, output is capped at 2 MiB and 15 seconds. The authorization sheet waits for the person; Cancel in Bonsai instructs them to cancel the sheet. Rights are destroyed on completion. Raw output stays in memory in the delivered app; a structured current-user snapshot with a read timestamp is cached in own UserDefaults and labeled saved until refreshed. Third-party managed switches open System Settings; Bonsai never edits the BTM database or resets it. App 'disabled' describes Open at Login; 'allowed' describes background permission. Those inputs are separate and neither proves that a process is running.

Distribution requirement: replace this deprecated authorization launcher with a Developer ID signed, narrowly scoped read-only XPC helper, then review notarization and macOS-version behavior. Local ad-hoc functionality is verified separately from distributable signing. System-owned launch services remain Settings/vendor handoffs.
