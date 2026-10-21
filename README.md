# Bonsai

<img src="docs/assets/GoldenGinkgo.png" width="160" align="right" alt="Golden ginkgo bonsai">

**A little care. A lighter Mac.**

Bonsai is a native macOS maintenance app built with SwiftUI and AppKit.

**Version 1.0.0 · macOS 14 or later · Apple Silicon**

## Features

- **Clean** — review caches, app leftovers, installers and project build files.
- **Apps** — manage installed apps, supported updates and startup items.
- **Optimize** — choose maintenance tasks and review their results.
- **Analyze** — explore disk usage, find large files and reveal items in Finder.
- **Status** — monitor CPU, GPU, memory, storage, batteries, network and processes.

The menu bar gives quick access to system readings and useful tools. Available readings and update methods depend on the Mac, permissions and application support.

## Download

Get the latest build from [Releases](https://github.com/mon0noke/Bonsai/releases).

## Build

Requires an Apple Silicon Mac, Swift command-line tools with the macOS SDK, and Python 3. Dependencies needed by the default build are included in the repository.

```sh
bash scripts/build.sh release --clean
```

The app is created at `outputs/Bonsai.app`. Building does not replace an installed copy. The default build uses local ad-hoc signing; Developer ID signing and notarization are separate distribution steps.

## Verify

```sh
outputs/BonsaiVerify
bash scripts/verify-design-production.sh
```

With full Xcode installed:

```sh
bash scripts/test.sh
```

## Source

| Folder | Contents |
| --- | --- |
| `Sources/Bonsai` | Interface and application state |
| `Sources/BonsaiCore` | Scanning, updates, maintenance and telemetry |
| `Sources/CBonsai` | Native system bridge |
| `Resources` | Artwork, metadata and backend resources |
| `Tests` | Core tests and fixtures |
| `Vendor` | Bundled dependencies |
| `scripts` | Build and verification tools |

## License

GPL-3.0. See [LICENSE](LICENSE) and the included dependency notices.
