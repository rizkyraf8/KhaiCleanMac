<p align="center">
  <img src="docs/logo.png" width="128" alt="KhaiCleanMac logo">
</p>

<h1 align="center">KhaiCleanMac</h1>

<p align="center">
  A friendly, source-available Mac cleaner with a soft pastel look.<br>
  Native Swift + SwiftUI · macOS 15+ · PolyForm Noncommercial license
</p>

<p align="center">
  <a href="CHANGELOG.md"><img src="https://img.shields.io/github/v/tag/rizkyraf8/KhaiCleanMac?label=latest%20version&color=5edcc0" alt="Latest version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-8b7cf6" alt="PolyForm Noncommercial License"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-5edcc0" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6-ff7ea8" alt="Swift 6">
</p>

<p align="center"><a href="README.id.md">Baca dalam Bahasa Indonesia</a></p>

<p align="center">
  <img src="docs/screenshots/smartScan.png" width="820" alt="Smart Scan">
</p>

## Download

<p align="center">
  <a href="https://rizkyraf.id/projects/khaicleanmac"><img src="https://img.shields.io/badge/Download-KhaiCleanMac-8b7cf6?style=for-the-badge&logo=apple&logoColor=white" alt="Download KhaiCleanMac"></a>
</p>

Get the latest version of KhaiCleanMac at **[rizkyraf.id/projects/khaicleanmac](https://rizkyraf.id/projects/khaicleanmac)**, then drag the app into your Applications folder. See what's new in the [changelog](CHANGELOG.md).

- Needs macOS 15 Sequoia or later, on a Mac with Apple silicon or an Intel processor (from 0.7.0; 0.6.1 and older are Apple silicon only).
- The app isn't notarized by Apple yet, so macOS may stop it the first time you open it. Open **System Settings › Privacy & Security** and click **Open Anyway**. You only need to do this once.
- On first launch, the welcome guide walks you through Full Disk Access. It's optional, but some scans need it.
- **Updates:** once a day the app asks `rizkyraf.id/api/projects/khaicleanmac/latest` for the newest version. When a newer one is out, Home, the sidebar and Settings → About offer an **Update** button: the app downloads the new DMG, checks its SHA-256 checksum, version and code signature, swaps itself and reopens. If any check fails, nothing is replaced and you can download it manually instead. Only the app's version is sent, and you can turn the check off in Settings → About. (In-app updates work from 0.5.0 on; 0.4.0 and older need one manual download.)

## Features

| Module | What it does |
|---|---|
| **Home** | The starting point: disk and memory at a glance, battery and SSD health, a one-click Smart Scan, Full Disk Access status and a card for every feature |
| **Smart Scan** | Finds app caches (`~/Library/Caches`), logs (`~/Library/Logs`), Xcode leftovers (DerivedData, Device Support, simulator caches), old `.dmg`/`.pkg` installers, old downloads, Mail attachment copies, iPhone/iPad backups and `.ipsw` files, and what's already in the Trash. Browser caches (Chrome, Brave, Edge, Arc, Vivaldi, Firefox, Safari) are cleaned entry by entry: only old web cache and obsolete code cache go |
| **Large Files** | Finds files above 50 MB, 100 MB, 500 MB or 1 GB in your home folder or on another disk, with type filters and sorting |
| **Duplicates** | Finds files with byte-identical content, in your home folder or on another disk, and keeps the oldest copy by default |
| **Developer** | Finds old project dependencies (`node_modules`, `Pods`, `.build`, `target`) Xcode archives, and Xcode simulator runtimes and devices (often tens of GB; removed through Xcode's own `simctl`). Package manager caches (Gradle, npm, Yarn, Cargo, Maven…) are cleaned entry by entry: only libraries unused for 30, 60 or 90 days go, so active projects keep building fast. Also lists Terminal commands for Homebrew, Docker and Go |
| **Privacy** | Clears browser history, cookies and form data per browser (Chrome, Brave, Edge, Arc, Vivaldi, Firefox, Safari), only for what you tick and only while that browser is closed. Passwords, bookmarks, addresses and cards are never touched |
| **Space Lens** | Shows a treemap of any folder or disk (Home by default). Double-click to drill in, use the breadcrumb to go back |
| **Uninstaller** | Removes apps from `/Applications` and `~/Applications` together with the files they leave behind (Application Support, Caches, Preferences, Containers, Group Containers, LaunchAgents and more) |
| **App Updates** | Finds apps with a newer version by reading each app's own Sparkle update feed, and opens the app so it installs the update itself. App Store apps are listed with a shortcut to the App Store's updates |
| **Extensions** | Turns third-party app extensions (Safari, Finder Sync, Share menu, Quick Look, widgets…) on or off, and removes old plug-ins, Quick Actions and screen savers from `~/Library`. Plug-ins in `/Library` are shown read-only |
| **History** | Every cleanup is logged: what was removed, how big it was and where it went. Anything still in the Trash can be put back with **Restore**, one item or a whole cleanup at once, and nothing at the original place is ever overwritten |
| **Login Items** | Lists login items, your LaunchAgents (turn them off or remove them) and system agents and daemons (read-only), and flags orphans whose app is gone |
| **Memory** | Shows memory pressure, a RAM breakdown and swap use, and lists the apps using the most RAM (helper processes included) with a Quit button. It can also release cached files with `purge`, which needs an administrator password |
| **Menu bar** | Shows live CPU usage in the menu bar, plus a panel with CPU, memory, disk, battery, and battery and SSD health. The app keeps running there after you close the window |
| **Reminders** | Checks junk daily, weekly or monthly and sends a notification once it passes 1, 5 or 10 GB. It never removes anything on its own |
| **Settings** | Language (Bahasa Indonesia or English), appearance (Match System, Light or Dark), open at login, menu bar, reminders, cache and download age limits, and an opt-in "delete permanently" mode. Open it with ⌘, or from the bottom of the sidebar |
| **Welcome guide** | Shown on first launch: what the app promises, and a step-by-step Full Disk Access tutorial that turns green on its own once access is granted. Open it again from Settings → About |

See [CHANGELOG.md](CHANGELOG.md) for what changed in each version. The current version is shown at the bottom of the sidebar and in Settings → About.

<p align="center">
  <img src="docs/screenshots/smartScan-results.png" width="410" alt="Smart Scan results">
  <img src="docs/screenshots/largeFiles-dark.png" width="410" alt="Large Files in dark mode">
</p>
<p align="center">
  <img src="docs/screenshots/duplicates.png" width="410" alt="Duplicates">
  <img src="docs/screenshots/menubar.png" width="200" alt="Menu bar panel">
</p>

## Safety first

- **The Trash is the default.** Everything cleaned goes to the Trash, so you can put it back until you empty it. Deleting permanently is an opt-in setting that has to be confirmed before it turns on, and every confirmation then says so. Items already in the Trash can only be deleted permanently.
- **Nothing is removed without your approval.** Each module shows exactly what it found and asks you to confirm first.
- **Open apps are protected.** Smart Scan locks the caches and logs of apps that are currently running and checks again right before cleaning.
- **Browsers keep their active cache.** Only web cache entries unused for longer than the limit you choose (7, 30 or 90 days) and code cache from an earlier browser version are removed, and only while that browser is closed. Old Chrome versions inside Chrome.app are never touched: while an update waits for a relaunch, the "old" version is the one running, and Chrome removes it itself after relaunching.
- **The Uninstaller skips Apple's built-in apps** and refuses to remove an app while it is running.
- **Login Items only edits what's yours.** Turning an agent off is reversible. System agents and daemons are shown but never changed.
- **Personal files are never preselected.** Old downloads, device backups, installers and the Trash stay unselected until you pick them.
- **Privacy cleanup is opt-in.** Nothing is ticked for you, an open browser is locked, and the confirmation lists every browser and kind of data. Files go to the Trash (restorable from History); Chromium form data is deleted inside its database, and the confirmation says it can't be put back. Firefox history shares a file with bookmarks, so it's left to Firefox.
- **App Updates never installs anything itself.** It only reads each app's public update feed (nothing about you or your other apps is sent) and opens the app, whose own updater checks the download's signature.
- **Other disks get the same guard.** A disk's Spotlight index, Trash, Time Machine backups and system folders are skipped and can't be removed, and read-only disks and disk images aren't offered.
- **Duplicates are handled carefully:**
  - Symlinks and hard links never count as copies.
  - Project and bundle folders (`node_modules`, `Pods`, `build`, `vendor`, `.app`, `.framework`, …) are skipped.
  - iCloud files that are not downloaded are never read.
  - At least one copy in every group is always kept.

### How duplicates are detected

Files are compared by content, never by name, in three passes:

1. **Size.** Only files that share the same size can be duplicates.
2. **First 64 KB.** A SHA-256 of the first 64 KB rules out most of the remaining files quickly.
3. **Full content.** A SHA-256 of the whole file confirms the match.

Similar photos and the same song in different formats are not detected. On APFS, Finder copies can be clones that share disk blocks, so removing one may free less space than its size suggests.

## Requirements

- macOS 15 Sequoia or later
- Xcode 16 or later (Swift 6 toolchain)

## Build and run

```bash
git clone https://github.com/rizkyraf8/KhaiCleanMac.git
cd KhaiCleanMac
./scripts/build-app.sh
open build/KhaiCleanMac.app
```

`build-app.sh` compiles a universal release build (Apple silicon and Intel in one app), generates the app icon and puts together `build/KhaiCleanMac.app`. Set `KHAI_ARCH=arm64` (or `x86_64`) for a quicker single-architecture build. While developing you can also use `swift run`, or open `Package.swift` in Xcode.

If you use [swiftly](https://github.com/swiftlang/swiftly), the `.swift-version` file makes it use Xcode's Swift toolchain in this folder.

### Make a DMG

```bash
./scripts/make-dmg.sh            # builds the app first
./scripts/make-dmg.sh --skip-build   # reuses build/KhaiCleanMac.app
```

This creates `build/KhaiCleanMac-<version>.dmg` and a `.sha256` checksum next to it. Opening the DMG shows the app, an **Applications** shortcut to drag it onto, and a background with an arrow and install notes.

Arranging that window needs permission to control Finder. Run the script from Terminal and allow it when macOS asks, or turn it on in **System Settings › Privacy & Security › Automation**. Without that permission the DMG still works, but Finder uses its default layout.

### Full Disk Access

Some folders can only be scanned with Full Disk Access. You can grant it in **System Settings → Privacy & Security → Full Disk Access**, and the button in the sidebar opens that page for you.

Local builds are ad-hoc signed. Because of that, macOS forgets the permission every time you rebuild. To keep the permission across rebuilds, do one of the following:
- Create a code-signing certificate named `KhaiCleanMac Local` (Keychain Access → Certificate Assistant → Create a Certificate → type *Code Signing*).
- Set `KHAI_SIGN_IDENTITY` to a signing identity you already have.

`build-app.sh` signs with that certificate or identity when it finds one.

### Debug snapshots

Debug builds can render every screen to PNG without opening a window:

```bash
swift build && .build/debug/KhaiCleanMac --snapshot ./snapshots [--dark] [--results]
```

`--results` also runs the scans, which only read files, so you can see the results screens. Those screens show real file names from your home folder, so review them before sharing.

### Tests

```bash
swift test
```

The tests build fake folders in a temporary directory and never touch your files or the real Trash. They cover what gets picked for removal (browser cache entries and their age, code cache from older versions, duplicates versus links, vendor folders, running-app locks, orphaned agents) and how removal works (batch Trash folders, rollback when the Trash refuses, permanent mode). GitHub Actions runs them on every push.

## Project structure

```
Sources/KhaiCleanMac/
  App/         entry point, settings (language, appearance), debug snapshots
  Design/      theme (palette, background, cards), components, logo artwork
  Models/      modules, junk categories, file kinds, scan results
  Services/    scanners (junk, large files, duplicates, apps, disk space, browser privacy),
               app update feeds, battery and disk health, mounted disks,
               running-app matching, Trash, permissions, system monitor
  ViewModels/  @Observable state for each module
  Views/       sidebar and one view per module, menu bar panel
scripts/       build-app.sh, make-icon/
Resources/     Info.plist, AppIcon.icns, logo
docs/          README images
```

The logo is drawn in code in `Design/LogoArtwork.swift`. The app icon and the sidebar logo both come from that file. `build-app.sh` regenerates `AppIcon.icns` whenever that file changes.

## Roadmap

- Clean system caches, system logs and orphaned system agents through a privileged helper
- Developer ID signing and notarization for a downloadable DMG

## Contributing

Issues and pull requests are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first. In short:

- Keep the safety rules above intact. Anything that removes files goes through `Trasher` and is confirmed by the user, and new removal logic needs tests.
- Before your first pull request is merged, you sign the [Contributor License Agreement](CLA.md). The bot asks on the pull request and it takes one comment.

## License

[PolyForm Noncommercial 1.0.0](LICENSE) © 2026 Rizky Aditya Fahreza

KhaiCleanMac is **source-available**, not open source:

- ✅ You may use, study, change and share it for **noncommercial** purposes: personal use, learning, research, hobby projects, and charitable, educational or government organizations.
- ❌ You may not use it for **commercial** purposes, for example selling it, bundling it with a paid product or using it to provide a paid service.
- For commercial use, contact the owner through [GitHub](https://github.com/rizkyraf8).

KhaiCleanMac is an independent project. It is not affiliated with or endorsed by MacPaw or CleanMyMac.
