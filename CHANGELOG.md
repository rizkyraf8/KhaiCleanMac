# Changelog

All notable changes to KhaiCleanMac are listed here.
The project follows [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

## [Unreleased]

## [0.5.0] - 2026-10-29

### Security
- **Uninstaller no longer trusts names and IDs from other apps' Info.plist.** A crafted name such as `../../Documents` could make a personal folder show up as a preselected "leftover". Names and bundle IDs are now validated, bundle IDs match exactly instead of by substring, and an empty or malformed ID matches nothing.
- Folders matched only by an app's name are labelled "Possibly related" and are no longer preselected.
- **New central safeguard:** whatever a module picks, removal refuses protected locations: system folders, the home folder and its main folders (Documents, Desktop, Downloads, Library and its top-level folders, the Trash itself), keychains and iCloud Drive. Paths with `..` are refused, and symlinks can't be used to get around it. Space Lens shows "Protected" for these.
- Smart Scan no longer offers caches that system services are actively using: background downloads, iCloud, Family Sharing, Home and Music.
- The update check only opens `https` links on rizkyraf.id. Any other link from the API is ignored in favor of the project page.

### Changed
- **License:** KhaiCleanMac is now source-available under the PolyForm Noncommercial License 1.0.0, for every version. Noncommercial use, study, changes and sharing are allowed; commercial use is not.

### Added
- **In-app updates.** "Update" downloads the new version, checks it against the SHA-256 published by rizkyraf.id, mounts it read-only, checks that the app inside is KhaiCleanMac at the announced version with an intact code signature (and the same certificate, when the installed app has one), then swaps it in and reopens. The old app stays until every check passes and is put back if the swap fails. Without a checksum from the server, the button falls back to the browser download.
- **Cleanup history** with **Restore**: every cleanup from any module is logged (up to 100). Anything still in the Trash goes back to where it was, item by item or a whole cleanup at once; an item cleaned file by file goes back file by file. Nothing at the original place is ever overwritten.
- **Extensions** module: turn third-party app extensions on or off (Safari, Finder Sync, Share menu, Quick Look, widgets, Shortcuts…) the same way System Settings does, and remove your own plug-ins, Quick Actions and screen savers from `~/Library`. Plug-ins in `/Library` are shown read-only.
- **Xcode simulators** in the Developer module: simulator runtimes (often 5–10 GB each) and simulator devices, with size and last use. Older runtimes unused for the chosen age and devices whose runtime is gone are preselected; the newest runtime of each platform never is. They are removed through Xcode's own `simctl`, not the Trash. Booted devices are skipped and everything is locked while Simulator is open.
- **Mail attachments** in Smart Scan: copies Mail saved when attachments were opened. The originals stay in your email. Not preselected.
- Contributing guide, Contributor License Agreement, and pull request and issue templates.
- **Update check:** once a day (and on demand in Settings → About), the app asks rizkyraf.id for the latest version. A newer one shows up on Home, in the sidebar and in Settings with a direct download button. Only the app version is sent, and the check can be turned off.
- `scripts/make-dmg.sh` builds a DMG with the app, an Applications shortcut to drag it onto, a background with install notes, a volume icon and a SHA-256 checksum.

### Fixed
- CI: worked around a Swift 6.2 compiler crash in Settings, and CI now shows build and test errors on the run summary.

## [0.4.0] - 2026-10-28

### Added
- **Welcome guide** on first launch:
  - What the app promises: the Trash first, nothing without confirmation, open apps locked.
  - Language choice.
  - A step-by-step **Full Disk Access tutorial**: open the right Settings page, drag the app icon into the list, then check the switch. The status turns green on its own once access is granted. The guide can be opened again from Settings → About, the sidebar or Home.
- **Home**: disk and memory at a glance, a one-click Smart Scan, Full Disk Access status and a card for every feature. The app now opens here.
- **Login Items module**:
  - Lists classic login items (read through System Events after macOS asks for permission) and your LaunchAgents. Agents can be turned off (reversible) or removed.
  - System agents and daemons are shown read-only.
  - Orphans whose program or app is gone are flagged.
- **More to clean in Smart Scan:**
  - Browser cache for Brave, Edge, Arc, Vivaldi, Firefox and Safari, besides Chrome, entry by entry and only while that browser is closed.
  - Old downloads: unopened for 30, 90 or 180 days.
  - iPhone/iPad backups and `.ipsw` update files.
  - What's already in the Trash.
  - None of these are preselected.
- **Delete permanently** setting: off by default, and it asks for confirmation before turning on. Every confirmation, result and Home banner says when it's on.
- **Automated tests** (`swift test`) for removal logic, using fake folders only. Also **GitHub Actions CI** that builds and tests every push.

### Changed
- Smart Scan's scanning screen shows an overall progress bar ("3 of 8 categories", junk found so far) and a four-column grid of categories with their status. Before, eight chips in one row squeezed their names into vertical text.
- Space Lens has a full-width progress bar under the breadcrumb that follows a folder from reading, through "measuring item 11 of 83 (13%)" with the current item's name, to done.

### Fixed
- Headless Chrome leftovers were treated as part of Chrome, so they stayed locked while Chrome was open. Found by the new tests.
- Two items with the same name cleaned in the same second could collide in the Trash staging folder.
- Removal text in every module now follows the chosen removal mode, instead of always saying "Trash".

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

[0.5.0]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rizkyraf8/KhaiCleanMac/releases/tag/v0.1.0
