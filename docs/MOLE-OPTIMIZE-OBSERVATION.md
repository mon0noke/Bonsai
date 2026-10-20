# Mole Optimize observation — 4 October 2026

Reference: installed Mole 1.15.0. A fresh authorized run was observed in native screenshots/accessibility state and compared with only the appended portion of its operations.log. The user-authorized, backed-up QA reset was used because the app displayed its trial limit. The supplied original was not edited. QA tooling remains outside Bonsai and its source archive.

## Observed interaction

One click on Optimize immediately replaced the quote/button with Running maintenance and a current-task counter, without task selection or confirmation. Mercury stayed in place. A compact glass trace appeared beneath the heading; the first screenshot caught Input switching / Spotlight at 2–3 of 21. Completion kept Mercury and offered Review results / Rest. Review results replaced the main navigation with full-window groups and a close action.

## Log correlation

The observed run appended entries between **19:39:41 and 19:39:44 Melbourne time** (08:39:41–44 UTC). Its log records:

| Group | Recorded outcome |
| --- | --- |
| Glitch fixes | Input switching, Notification Center and Universal Clipboard RAN; Spotlight restart SKIPPED |
| Quick Look | Cache rebuild and thumbnail rebuild RAN |
| Other maintenance | 15 SKIPPED: normal state, database task could not complete, or audit-only findings |
| Orphan command audit | 10 AUDIT entries; individual local paths omitted |

The results UI matched **2 optimized · 15 skipped**, with the three service refreshes shown separately under Glitch fixes. These logs corroborate task dispatch/status; they do not independently prove every underlying effect or establish that all skips were based on a complete diagnostic. No unsupported Mole command or private helper was copied into Bonsai.

## Bonsai adjustment

Bonsai's main Optimize action immediately runs its four supported routine tasks: two Quick Look refreshes plus read-only Spotlight/power checks. The maple no longer shrinks or shifts when execution starts. Custom selection and optional disk verification are separate. Current output labels distinguish checks from refreshes. Mole's other service restarts and database/preference/agent changes remain unsupported.
