# Changelog

All notable changes to KhaiCleanMac are listed here.
The project follows [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

## [0.3.0] - 2026-10-28

### Added
- **Developer module** for coding leftovers:
  - Project dependency folders: `node_modules`, `Pods`, `.build` and `target`. A folder only counts when the project's manifest sits next to it. Folders unused for longer than the chosen age are preselected.
  - **Smart package caches** for Gradle, npm, Yarn, Bun, Cargo, Maven, Dart and Android. Each cache is measured entry by entry (a library version, a build-cache file, a Gradle version), using the last time anything in it was read. Only entries unused for longer than 30, 60 or 90 days are cleaned. Libraries your active projects still use stay, and so does a Gradle version that a recently built project's wrapper asks for.
  - Folders inside the Gradle cache that Gradle never uses, such as a hand-made `files-backup`, are flagged and left unselected.
  - Gradle and Maven are locked while Android Studio or IntelliJ IDEA is open.
  - Xcode archives. None are preselected, because they hold the dSYMs used to read crash reports.
  - Copyable Terminal commands for cleanups only the tool can do safely: `brew cleanup`, `docker system prune`, `xcrun simctl delete unavailable` and `go clean -modcache`.
- **Chrome cache, cleaned smartly.** Smart Scan has a new Chrome category that removes only what is no longer useful, not the whole cache folder:
  - Web cache entries unused for longer than 7, 30 or 90 days (Settings → General). Recent cache stays so sites keep loading fast.
  - Code cache made by an earlier Chrome version, which V8 always rejects.
  - Temp folders left by headless Chrome (Puppeteer and similar tools) that are more than a day old.
- A notice when Chrome is waiting to relaunch after an update. The "old" version is still the running one, so the app explains how to reclaim the space instead of deleting it. Old Google Updater versions in the system Library are reported but skipped, because they need admin rights.
- **Keep running in the menu bar** after the window closes, with the Dock icon hidden until the window is reopened. It is on by default.
- **Open at login**, using the system Login Items.
- **Junk reminders:** a daily, weekly or monthly check that sends a notification when junk passes 1, 5 or 10 GB. It only measures and never removes anything. It includes the Chrome category.
- Settings now has tabs: General, Appearance, Reminders and About.
- **Memory module:**
  - Shows memory pressure (Normal, Getting full or Critical), RAM split into apps, wired, compressed, cached files and free, and swap use.
  - Lists the apps using the most RAM, with their helper processes counted in, and lets you quit them the normal way after a confirmation.
  - An optional "Release cached files" button runs `purge` behind macOS's own administrator prompt. The app explains that macOS already releases this cache on its own and that `purge` doesn't reduce swap.

### Changed
- The menu bar shows a one-colour version of the KhaiCleanMac logo instead of a generic sparkle. It adapts to light mode, dark mode and the highlighted state.
- The bundle identifier is now `id.rizkyraf.KhaiCleanMac`. Language and appearance choices are carried over from the old identifier. Full Disk Access, notifications and Open at login have to be granted again.
- Vendor cache folders (Google, Mozilla, JetBrains, Microsoft, Adobe) are listed per app. One open app no longer locks the others, and Android Studio's cache is no longer removed together with Chrome's.
- Items made of many small files go to the Trash as one dated folder, with their original paths kept inside it.

### Fixed
- KhaiCleanMac's own memory use while scanning. Every file walk now releases its temporary objects file by file instead of at the end of the walk. A full run of every scan used to peak at about 2.3 GB and now stays near 400 MB.
- File and app icons are drawn once at the size they are shown and then cached, instead of loading every resolution on each redraw.

## [0.2.0] - 2026-10-28

### Added
- Settings window (⌘, or the button at the bottom of the sidebar).
- Interface language: Bahasa Indonesia or English. Sizes, numbers and dates follow the chosen language.
- Appearance: Match System, Light or Dark.
- The app version is shown in the sidebar and in Settings → About.

## [0.1.0] - 2026-10-28

First public release.

### Added
- **Smart Scan:** finds app caches, logs, Xcode junk and old installers. Caches of apps that are open are locked.
- **Large Files:** finds files above a chosen size in your home folder.
- **Duplicates:** finds files with identical content.
- **Space Lens:** treemap view of a folder's contents.
- **Uninstaller:** removes apps together with their leftover files.
- **Menu bar monitor:** shows CPU, memory, disk and battery.
- Everything that gets removed goes to the Trash, and nothing is removed without confirmation.

[0.3.0]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rizkyraf8/KhaiCleanMac/releases/tag/v0.1.0
