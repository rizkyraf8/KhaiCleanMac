# Changelog

All notable changes to KhaiCleanMac are listed here.
The project follows [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

## [Unreleased]

### Added
- **Docker cleanup** in Developer. Instead of a command to copy, a Docker card shows what Docker reports as reclaimable and cleans by age: created over **7, 30 or 60 days** ago. Docker removes things itself: dangling images and build cache through `image prune` and `builder prune` with an `until` filter, tagged images one by one with `image rm` when they came from a registry (they have a repo digest, so they can be pulled again), and opted-in stopped containers by ID with `container rm`. Images built, committed or loaded on this Mac are kept.
  - **Only this Mac.** The active Docker context must be the socket of an engine on this Mac (Docker Desktop, OrbStack, Colima, Lima, Rancher Desktop or `/var/run/docker.sock`, also with symlinks resolved) before anything is read or removed. Any other socket and any TCP port, localhost included, may be a tunnel to a server and is refused. Every command names that context, the context is checked again right before cleaning, and `builder prune` uses that context's own builder (`BUILDX_BUILDER`), not a remote or cloud one buildx may have selected. `DOCKER_HOST` and `DOCKER_CONTEXT` are ignored.
  - **Stopped containers are opt-in**, listed by name and removed by ID, so only the ones shown go (none when Docker couldn't list them), with a warning: files inside a container that aren't in a volume (a database run without `-v`) go with it. Volumes and running containers are never touched.
  - Ages count from creation, as Docker keeps no "last used" date, and the card says so. It also explains that Docker Desktop hands space back to macOS gradually.
  - Every Docker command has a time limit (1 minute to check, 10 minutes to clean), so a stuck engine shows "not responding" instead of a spinner that never ends.
  - Each cleanup is logged in History as one permanent entry (Docker has no Trash). Works with Docker Desktop, OrbStack, Colima and Rancher Desktop.

### Security
- **Hardened Runtime.** The app is signed with Hardened Runtime (`codesign --options runtime`), so another program can no longer start it with `DYLD_INSERT_LIBRARIES` and run its own code with KhaiCleanMac's Full Disk Access. The only entitlement is Apple Events, for Login Items. The build script stops if the flag is missing.
- **Uninstaller can't reach another app's data.** An app whose bundle ID spells Apple's in other letter case (`Com.Apple.mail`) is no longer listed, since the disk ignores case and its "leftovers" would be Mail's container. Leftover folders must be spelled exactly like the ID, a sandbox container that names another owner is skipped, and an ID another installed app also uses (a second copy, or an app claiming someone else's ID) gets no leftovers at all. Bundle IDs must be ASCII, and app names that match macOS data folders (AddressBook, MobileSync, CallHistoryDB…) are never matched, not even as a guess.
- **SafetyGuard ignores letter case and Unicode composition**, as the disk does, so `~/documents` or `/LIBRARY/…` can't slip past it. On a bootable clone, its Applications and Users folders are protected and left out of scans.
- **Updates from a renewed certificate:** an update must come from the same Apple Team ID as the running app, when it has one, instead of the very same certificate.

### Fixed
- **Uninstall removes the app first.** If the app can't be moved (it needs an admin password), its data now stays too, instead of leaving the app installed without its settings.
- **Privacy:** a browser opened or quit is noticed right away (the app listened on the wrong notification center), and data of a browser that was open is unticked for good, so it can't be cleared later without being in the confirmation.
- **Partial removals are reported as such.** An item made of many files that only partly went (some files locked, or protected) counts only the size that went, stays listed, and shows as failed instead of fully removed.
- **Smart Scan** no longer offers Poetry's virtual environments (`~/Library/Caches/pypoetry/virtualenvs`) or app updates being installed (`*.ShipIt`).
- **History** won't put back an unrelated file that took the same name in the Trash after it was emptied: each trashed item's file number is checked.
- **Developer:** the Trash button is disabled while a cleanup runs, and a replaced scan can no longer deliver its old results.
- Every helper tool the app runs has a time limit (2 minutes by default, longer for `simctl` and the Login Items permission prompt), so a stuck tool can't hang a screen.
- Time Machine disks in the APFS format are recognized and left out of the disk list; Memory shows Simulator as its own app instead of under Xcode, and can no longer show a huge number when purgeable memory is high.
- **CI:** GitHub Actions are pinned to commit SHAs and the workflow only has read access.
- **Items the safety guard refuses no longer look removed** (code review, issue 1). Large Files, Duplicates, Space Lens, the Uninstaller and Developer took a refused item off the list and showed a green checkmark as if it had gone; Smart Scan's "skipped" note only counted failures. Refused and failed items are now treated alike everywhere: they stay listed and selected, and the result shows a warning.
- **Login Items with a missing app** (issue 2). One item whose path System Events couldn't read made the whole list fail to load. Each item is now read on its own, and one without a readable path shows up as an orphan.
- The menu bar monitor's sampling loop ends when the monitor is released (issue 3), History restores an item through its own record instead of searching for it (issue 4), and the Trash staging folder keeps subfolders when a path is spelled through a symlink such as `/private/var` (issue 5), so two files with the same name no longer collide.
- **CI:** the Intel test step ran the x86_64 tests through Rosetta on an Apple silicon runner and failed there. The Intel tests now run natively on GitHub's `macos-15-intel` runner as a separate job.

## [0.8.0] - 2026-10-29

### Added
- **Seven more languages:** Japanese, Simplified Chinese, Spanish, German, Brazilian Portuguese, French and Korean (日本語, 简体中文, Español, Deutsch, Português (Brasil), Français, 한국어), for all 577 texts in the app. A new install starts in the Mac's own language when the app speaks it (any Portuguese gets the Brazilian one); otherwise English (Traditional Chinese gets English rather than Simplified). A saved choice is kept.
- **These seven languages were translated with AI**, not by native speakers, so some wording may be off. Settings › General says so under the language picker, as does the welcome guide when one of them is chosen, with a link to report mistakes on GitHub.
- The language picker in Settings › General shows all nine languages in a 3 × 3 grid; the welcome guide has a language menu instead of a row of chips.
- `scripts/l10n.py`: `missing [code]` lists texts without a translation, `check` fails on missing, stale or broken entries in any language. CI runs the check. Each language has its own file, `Localization/Translations+<code>.swift`.

### Changed
- `L("Indonesian", "English")` call sites are unchanged. Each English text now doubles as the key for the other languages, with its interpolated values as `%1$@`, `%2$@`… so a translation can reorder them or leave out an English plural. Anything not yet translated falls back to English.

### Fixed
- **Smart Scan on small screens:** the summary and the notices above the results (open apps, Chrome waiting to relaunch) didn't scroll, so on a 13-inch laptop the categories were squeezed into a small strip. Everything but the Clean bar scrolls now.
- **Memory on small screens:** app names were cut to a few letters and "36 processes" broke over two lines. The process count now sits next to the usage bar, leaving the name its own line.
- Number tiles (Uninstaller, Login Items, Extensions, App Updates) keep their title and value on one line, shrinking slightly instead of breaking "3.42 GB" in two.
- Debug snapshots take `--small` to render every screen at the smallest window size.

## [0.7.0] - 2026-10-29

### Added
- **Intel Macs.** `scripts/build-app.sh` now builds a universal app (Apple silicon and Intel in one binary, both requiring macOS 15). `KHAI_ARCH=arm64` or `x86_64` builds a single slice for quicker local builds.
- CI also builds the universal release and runs the whole test suite as x86_64 under Rosetta, through Xcode's `xctest` (SwiftPM's own test runner is arm64-only).

## [0.6.1] - 2026-10-29

### Changed
- The version button next to Settings at the bottom of the sidebar now updates in place like Home and Settings › About (download, verify, install, reopen), with its progress shown in the button. It only opens the browser download when the release has no checksum or an install failed.
- On Home, the Full Disk Access card now sits at the top, right under the greeting.
- While Full Disk Access is still off, the welcome guide opens again at its Full Disk Access step each time the app is launched (once per launch).

### Fixed
- **Trash rollback could delete originals** ([#3](https://github.com/rizkyraf8/KhaiCleanMac/issues/3)). When the Trash refused a staging folder and a file couldn't go back (its place was taken, or not writable), the staging folder was deleted with that file in it. It is now kept and its location shown in the result; it is only removed once it holds nothing but empty folders.
- **Developer could remove a whole cache folder** ([#2](https://github.com/rizkyraf8/KhaiCleanMac/issues/2)). After the last stale entry of an entry-only cache (Gradle, Maven, npm…) was cleaned, the item could be selected again and removed as a whole folder, including files such as `gradle.properties` that were never offered. Entry-only is now set by the scanner instead of guessed from the entry list, an exhausted item leaves the list, and an item with nothing stale hands nothing over.
- **Duplicates are checked again before removal** ([#4](https://github.com/rizkyraf8/KhaiCleanMac/issues/4)). A selected copy only goes when it still has the group's size and content and matches a different, unselected copy that still exists; a hard link to the kept copy doesn't count. Anything else is skipped and the result asks for a new scan. A read error while hashing now fails instead of hashing a partly read file.
- **Uninstaller no longer preselects other apps' data** ([#5](https://github.com/rizkyraf8/KhaiCleanMac/issues/5)). Group Containers are matched to the app groups in the app's code signature, and a container another installed app also declares (such as Microsoft Office's shared one) is labelled "Shared with another installed app" and left unticked. Look-alike IDs, such as `com.vendor.editor.beta` when removing `com.vendor.editor`, are labelled as guesses in Group Containers, LaunchAgents and ByHost preferences.
- 12 regression tests built from the scenarios in those issues (92 tests in all).

## [0.6.0] - 2026-10-29

### Added
- **Battery & disk health** on Home and in the menu bar panel: the battery's maximum capacity compared to new, cycle count (out of the designed 1000) and condition, read from the same source as System Settings › Battery, plus the startup disk's S.M.A.R.T. status. Read once an hour, never changed.
- **App Updates** module: finds apps with a newer version by reading each app's own Sparkle update feed (betas, other platforms and releases that need a newer macOS are skipped), with release notes and date. **Open** launches the app so its own updater installs and verifies the update; KhaiCleanMac never downloads installers itself. App Store apps get a shortcut to the App Store's updates. Only feed addresses are requested, with no cookies.
- **Other disks** in Large Files, Duplicates and Space Lens: pick a mounted disk instead of the home folder. Read-only disks, disk images and Time Machine backups aren't offered, and a disk's system folders (Spotlight, Trash, `.fseventsd`, Time Machine, a bootable system) are skipped and can't be removed. The choice falls back to Home when the disk is ejected.
- **Privacy** module: clear browsing history, cookies and form data per browser (Chrome, Brave, Edge, Arc, Vivaldi, Firefox, Safari), across all profiles. Nothing is preselected, open browsers are locked and checked again before cleaning, and passwords, bookmarks, addresses and cards are never touched. History and cookie files go to the Trash and are logged in History; Chromium form data is deleted inside its database (only the `autofill` table). Firefox history and Safari form data point to the browser's own setting instead, because they share storage with bookmarks or the Keychain.
- Tests for battery and disk parsing, appcast reading and version comparison, browser data discovery and form data clearing, and scanning other disks (80 tests in all).

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

[0.8.0]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rizkyraf8/KhaiCleanMac/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rizkyraf8/KhaiCleanMac/releases/tag/v0.1.0
