# Bonsai

<img src="docs/assets/GoldenGinkgo.png" width="240" align="right" alt="Golden ginkgo bonsai">

**A little care. A lighter Mac.**

Bonsai is a free, open-source macOS maintenance app built with SwiftUI and AppKit. Clear out unwanted files, manage apps, explore your storage, and keep an eye on your Mac—all in a native interface inspired by bonsai trees.

[![Release](https://img.shields.io/github/v/release/mon0noke/Bonsai?style=flat-square&label=Download)](https://github.com/mon0noke/Bonsai/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square)](#requirements)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-arm64-666666?style=flat-square)](#requirements)
[![SwiftUI](https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square)](#build-from-source)
[![No telemetry](https://img.shields.io/badge/telemetry-none-success?style=flat-square)](#privacy)
[![License](https://img.shields.io/github/license/mon0noke/Bonsai?style=flat-square)](LICENSE)
[![Stars](https://img.shields.io/github/stars/mon0noke/Bonsai?style=flat-square)](https://github.com/mon0noke/Bonsai/stargazers)
[![Downloads](https://img.shields.io/github/downloads/mon0noke/Bonsai/total?style=flat-square&label=Downloads)](https://github.com/mon0noke/Bonsai/releases)

[Download](https://github.com/mon0noke/Bonsai/releases/latest) · [Features](#features) · [Getting started](#getting-started) · [Permissions](#permissions) · [Build](#build-from-source) · [Report an issue](https://github.com/mon0noke/Bonsai/issues)

<br clear="right">

## Features

| Section | What you can do |
| --- | --- |
| **Clean** | Find caches, logs, temporary files, old installers, and developer build artifacts. |
| **Apps** | Inspect installed apps and related files, review leftovers, manage supported startup items, and install supported app updates. |
| **Optimize** | Choose local maintenance tasks and system checks, then inspect their outcomes. |
| **Analyze** | Map disk usage, browse folders, and find the largest files. |
| **Status** | View live CPU, GPU, memory, storage, battery, network, thermal, and process readings. |

## Install

### Requirements

- **macOS 14 Sonoma or later**
- **Apple Silicon Mac**—the current release is arm64 only.

### Download

1. Download **Bonsai-1.0.0-arm64.zip** from [Releases](https://github.com/mon0noke/Bonsai/releases/latest).
2. Unzip it and move **Bonsai.app** into **Applications**.
3. Open Bonsai and grant the permissions needed for the features you use.

The current release is locally signed and **not notarized**. macOS may require launch approval in **System Settings → Privacy & Security**.

Each release includes `SHA256SUMS.txt`. To check the downloaded archive, run this from the folder containing both files:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

## Getting started

1. Open **Clean**, scan, and choose the items you want to remove.
2. Use **Apps** to inspect an application, check for updates, or review leftover files.
3. Open **Analyze** and choose **Map your disk** or select a folder to explore its storage use.
4. Visit **Status** for live readings, or enable the menu bar icon for quick access.

Settings includes appearance, cache removal behavior, protected folders, keyboard shortcuts, login behavior, and notification preferences.

## What you can do

### Clean up unwanted files

Clean groups results into categories such as app and system caches, logs, temporary files, browser data, developer tools, AI tools, cloud clients, installers, and dependency folders. Available results depend on installed software and folder access.

Review each selection before removing it. App data and models are not selected by default. Add folders to **Protected Items** in Settings to exclude them from cleaning.

**Cache Removal** offers **Move to Trash** and **Permanently**. Items in Trash still occupy storage until you empty it; permanent removal cannot be restored from Trash.

### Manage apps and leftovers

Inspect an app’s size and related caches, preferences, support files, and launch items. Remove selected applications and eligible related files, reveal paths in Finder, or copy a path for closer inspection.

The optional **App Leftover Notices** watcher detects apps moved to Trash and offers a review of remaining files. Leftover matches are candidates for inspection; a matching name or identifier does not guarantee that a file is unused.

Startup-item inspection shows supported login and background items. Some actions require approval through macOS.

### Update supported apps

Check for updates and use **Update** to install supported releases from inside Bonsai. Progress appears beside the app; failed updates show a short reason on hover.

| Source | Support |
| --- | --- |
| **Publisher feeds** | Supported Sparkle and Electron releases, with archive and publisher checks. |
| **Homebrew** | Supported installed casks, with optional public cask catalog discovery. |
| **App Store** | Eligible installed apps through Apple’s update services and the bundled helper. Apple account access or macOS authorization may be required. |
| **Other publishers** | Supported catalog entries; unsupported formats or sources may require the publisher’s updater or installer. |

Coverage varies by app, installer format, permissions, and publisher. Finding a newer version does not guarantee that it can be installed automatically. Close an app before updating it when requested.

### Run maintenance tasks

Optimize includes Finder preview refreshes, eligible application database maintenance, selected Finder preferences, system checks, and startup-volume verification. Choose the tasks you need and review their results.

Some tasks only inspect settings or report a condition. Results can be skipped or unavailable when access, ownership, or system restrictions prevent an operation. Hardware fan overrides and custom battery charge limits are not supported in this release.

### Explore your storage

Analyze builds an interactive disk map for your disk or a folder you choose. Drill into folders, switch between **Current Folder** and **Largest Files**, and open **More Items** to continue through smaller entries.

Context menus include **Copy Path**, **Reveal in Finder**, and **Move to Trash**. The usage indicator compares the items in view with total disk capacity. Protected or inaccessible locations can leave a scan incomplete.

### Monitor your Mac

Status brings together:

- CPU and GPU usage, with temperatures when available.
- Memory use, pressure, and swap.
- Free storage and network upload/download rates.
- Battery charge, charging or discharge information, and supported connected-device batteries.
- Thermal state and a sortable process list with memory, CPU usage, power impact, and PID.

Process menus provide pinning, process details, Finder reveal, copying, and supported termination actions. Sensor readings, device batteries, and time estimates depend on the hardware and information exposed by macOS.

### Menu bar and everyday tools

Keep Bonsai in the menu bar with a tree icon, CPU reading, or both. Quick tools include **Keep Screen On**, **Clean Screen**, and **Run Doctor**. Assign shortcuts and choose whether closing or quitting Bonsai keeps the menu bar available.

Notifications have a master switch and individual controls for resource pressure, connected-device battery levels of 20% or below, daily app-update counts, app leftovers, and low disk space. The daily update summary runs once per active day after an automatic check.

## Permissions

| Permission | Used for |
| --- | --- |
| **Files & Folders / Full Disk Access** | Measuring protected locations and finding app data. Enable Bonsai in **System Settings → Privacy & Security → Full Disk Access** for broader coverage. |
| **Notifications** | Optional system alerts; categories can be toggled in Bonsai Settings. |
| **Accessibility** | Optional system-wide keyboard protection during Clean Screen. |
| **Login Items** | Opening Bonsai at sign-in when enabled. |
| **Administrator authorization** | Specific supported operations, such as some App Store updates or reading protected startup-item information. |

If access changes are not reflected immediately, reopen Bonsai and retry the scan. Permissions do not make every system file eligible for removal.

## Privacy

File scans, process readings, preferences, and operation history are handled locally. Bonsai does not upload scanned file contents or send usage analytics.

App-update checks and downloads use the network. They can contact publisher feeds, GitHub releases, Apple services, and Homebrew sources; app identifiers or package names may be sent to those services. App Store operations use Apple’s account and authorization mechanisms.

## Build from source

Requires an Apple Silicon Mac, Swift command-line tools with the macOS SDK, and Python 3. Dependencies needed by the default build are included in the repository.

```sh
git clone https://github.com/mon0noke/Bonsai.git
cd Bonsai
bash scripts/build.sh release --clean
```

The app is created at `outputs/Bonsai.app`. Building does not replace an installed copy. The default build uses local ad-hoc signing; Developer ID signing and notarization are separate distribution steps.

### Verify

After building:

```sh
outputs/BonsaiVerify
bash scripts/verify-design-production.sh
```

To run XCTest with full Xcode installed:

```sh
bash scripts/test.sh
```

## Source layout

| Folder | Contents |
| --- | --- |
| `Sources/Bonsai` | SwiftUI/AppKit interface and application state |
| `Sources/BonsaiCore` | Scanning, updates, maintenance, and system metrics |
| `Sources/CBonsai` | Native system bridge |
| `Resources` | Artwork, app metadata, and backend resources |
| `Tests` | Core tests and fixtures |
| `Vendor` | Bundled dependencies |
| `scripts` | Build and verification tools |

## Issues and contributions

Found a problem or have a suggestion? [Open an issue](https://github.com/mon0noke/Bonsai/issues) with your macOS version, Bonsai version, and steps to reproduce it. Screenshots are useful for layout issues.

Pull requests are welcome. Describe what changed and how you verified it. For changes to scanning, removal, or updates, include tests covering the affected behavior.

## License

GPL-3.0. See [LICENSE](LICENSE) and the included dependency notices.
