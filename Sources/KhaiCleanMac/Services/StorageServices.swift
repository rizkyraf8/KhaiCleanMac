import Foundation
import SwiftUI

// MARK: System Data

/// One part of what macOS counts as "System Data", measured from the folders it lives in.
struct StorageBucket: Identifiable, Sendable {
    enum Action: Sendable, Equatable {
        /// Another module cleans this part.
        case module(Module)
        case showInFinder
        /// Only explained: it belongs to macOS or another app's own settings.
        case none
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let colors: [Color]
    let folders: [URL]
    let action: Action
    var size: Int64?
}

enum SystemDataScanner {
    static func buckets(home: URL = .homeDirectory) -> [StorageBucket] {
        let library = home.appending(path: "Library")
        func lib(_ path: String) -> URL { library.appending(path: path) }
        return [
            StorageBucket(id: "caches", title: L("Cache app", "App caches"),
                          detail: L("File sementara app. Sebagian besar bisa dibersihkan lewat Smart Scan.", "Apps' temporary files. Most can be cleaned with Smart Scan."),
                          symbol: "internaldrive.fill", colors: Palette.leaf, folders: [lib("Caches")], action: .module(.smartScan)),
            StorageBucket(id: "logs", title: L("Log & laporan crash", "Logs & crash reports"),
                          detail: L("Log app dan laporan crash milikmu. Bisa dibersihkan lewat Smart Scan.", "Your apps' logs and crash reports. Smart Scan can clean them."),
                          symbol: "doc.plaintext.fill", colors: Palette.sunny, folders: [lib("Logs")], action: .module(.smartScan)),
            StorageBucket(id: "developer", title: L("Xcode & simulator", "Xcode & simulators"),
                          detail: L("DerivedData, arsip, Device Support, dan simulator. Bisa dibersihkan lewat Developer.", "DerivedData, archives, Device Support and simulators. Developer can clean them."),
                          symbol: "hammer.fill", colors: Palette.ocean, folders: [lib("Developer")], action: .module(.developer)),
            StorageBucket(id: "backups", title: L("Backup iPhone & iPad", "iPhone & iPad backups"),
                          detail: L("Backup perangkat dari Finder. Bisa dihapus lewat Smart Scan, atau dikelola di Finder saat perangkat tersambung.", "Device backups made by Finder. Smart Scan can remove them, or manage them in Finder while the device is connected."),
                          symbol: "iphone", colors: Palette.lavender, folders: [lib("Application Support/MobileSync")], action: .module(.smartScan)),
            StorageBucket(id: "icloud", title: L("Salinan lokal iCloud Drive", "iCloud Drive local copies"),
                          detail: L("File iCloud Drive yang sudah diunduh ke Mac ini. Salinannya bisa dilepas tanpa menghapus file di iCloud.", "iCloud Drive files downloaded to this Mac. Their copies can be removed without deleting them from iCloud."),
                          symbol: "icloud.fill", colors: Palette.sky, folders: [lib("Mobile Documents")], action: .module(.iCloud)),
            StorageBucket(id: "containers", title: L("Data app (container)", "App data (containers)"),
                          detail: L("Data app dari App Store dan app yang di-sandbox, termasuk disk image Docker Desktop. Hapus app yang tidak dipakai lewat Uninstaller.", "Data of App Store and sandboxed apps, including Docker Desktop's disk image. Remove apps you don't use with the Uninstaller."),
                          symbol: "shippingbox.fill", colors: Palette.candy, folders: [lib("Containers"), lib("Group Containers")], action: .module(.uninstaller)),
            StorageBucket(id: "support", title: L("Application Support", "Application Support"),
                          detail: L("Data yang disimpan app di luar container. Sisa app yang sudah dihapus bisa dicari lewat Uninstaller.", "Data apps keep outside a container. Leftovers of removed apps can be found with the Uninstaller."),
                          symbol: "folder.fill", colors: Palette.peach, folders: [lib("Application Support")], action: .module(.uninstaller)),
            StorageBucket(id: "mail", title: "Mail",
                          detail: L("Email dan lampiran yang disimpan Mail. Kurangi lewat Mail › Settings › Accounts, atau hapus email lama dengan lampiran besar.", "Mail's stored messages and attachments. Reduce them in Mail › Settings › Accounts, or delete old messages with big attachments."),
                          symbol: "envelope.fill", colors: Palette.ocean, folders: [lib("Mail")], action: .showInFinder),
            StorageBucket(id: "messages", title: L("Lampiran Messages", "Messages attachments"),
                          detail: L("Foto dan video dari Messages. Kelola lewat System Settings › General › Storage › Messages.", "Photos and videos from Messages. Manage them in System Settings › General › Storage › Messages."),
                          symbol: "message.fill", colors: Palette.mint, folders: [lib("Messages/Attachments")], action: .showInFinder),
            StorageBucket(id: "swap", title: L("Swap & sleep image", "Swap & sleep image"),
                          detail: L("Memori yang dipindahkan macOS ke disk. Ukurannya turun sendiri setelah restart atau saat RAM longgar.", "Memory macOS moved to the disk. It shrinks on its own after a restart or once RAM frees up."),
                          symbol: "memorychip.fill", colors: Palette.slate, folders: [URL(filePath: "/private/var/vm")], action: .none),
            StorageBucket(id: "system", title: L("Cache & log sistem", "System caches & logs"),
                          detail: L("Milik macOS dan semua pengguna Mac ini. macOS membersihkannya sendiri; KhaiCleanMac tidak menyentuhnya.", "Belong to macOS and every user on this Mac. macOS cleans them itself; KhaiCleanMac leaves them alone."),
                          symbol: "gearshape.2.fill", colors: Palette.slate,
                          folders: [URL(filePath: "/Library/Caches"), URL(filePath: "/Library/Logs"), URL(filePath: "/private/var/log")], action: .none),
        ]
    }

    static func measure(_ bucket: StorageBucket) -> Int64 {
        bucket.folders.reduce(0) { $0 + FileSizer.allocatedSize(of: $1) }
    }

    /// Space macOS reports it can free on its own (local snapshots, caches it manages), from the volume itself.
    static func purgeable(volume: URL = URL(filePath: "/")) -> Int64? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? volume.resourceValues(forKeys: keys),
              let important = values.volumeAvailableCapacityForImportantUsage,
              let available = values.volumeAvailableCapacity else { return nil }
        return max(0, important - Int64(available))
    }
}

// MARK: Local Time Machine snapshots

/// Snapshots Time Machine keeps on the startup disk between backups. They hold deleted files until
/// macOS needs the space; removing them never touches backups on the backup disk.
enum LocalSnapshots {
    struct Snapshot: Identifiable, Hashable, Sendable {
        /// "2026-11-01-123456", the form `tmutil deletelocalsnapshots` takes.
        let stamp: String
        let date: Date?

        var id: String { stamp }
    }

    static func list(run: (String, [String]) -> String? = { StartupScanner.run($0, $1, timeout: 60) }) -> [Snapshot] {
        parse(run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]) ?? "")
    }

    /// `com.apple.TimeMachine.2026-11-01-123456.local` lines.
    static func parse(_ output: String) -> [Snapshot] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard let match = line.firstMatch(of: /com\.apple\.TimeMachine\.(\d{4}-\d{2}-\d{2}-\d{6})(?:\.local)?/) else { return nil }
            let stamp = String(match.1)
            return Snapshot(stamp: stamp, date: date(stamp))
        }
        .sorted { $0.stamp > $1.stamp }
    }

    static func date(_ stamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.date(from: stamp)
    }

    /// A stamp is only ever digits and dashes, so it can go into the shell command as is.
    static func isValidStamp(_ stamp: String) -> Bool {
        stamp.wholeMatch(of: /\d{4}-\d{2}-\d{2}-\d{6}/) != nil
    }

    /// Deletes the given snapshots behind macOS's own administrator prompt, so the password never
    /// passes through this app. Returns how many went and the snapshots still there.
    static func delete(_ snapshots: [Snapshot], list: () -> [Snapshot] = { list() }) -> (deleted: Int, remaining: [Snapshot]) {
        let stamps = snapshots.map(\.stamp).filter(isValidStamp)
        guard !stamps.isEmpty else { return (0, snapshots) }
        let commands = stamps.map { "/usr/bin/tmutil deletelocalsnapshots \($0)" }.joined(separator: "; ")
        let script = "do shell script \"\(commands)\" with administrator privileges"
        // Cancelled or failed: nothing may have changed, but reading again tells for sure.
        _ = StartupScanner.run("/usr/bin/osascript", ["-e", script], timeout: 600)
        let remaining = list()
        let left = Set(remaining.map(\.stamp))
        return (stamps.count { !left.contains($0) }, remaining)
    }
}

// MARK: iCloud Drive

/// A file in iCloud Drive that is downloaded to this Mac and fully uploaded, so its local copy can go.
struct CloudFile: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let lastUsed: Date?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum ICloudScanner {
    static func root(home: URL = .homeDirectory) -> URL { home.appending(path: "Library/Mobile Documents") }

    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsUploadingKey, .ubiquitousItemIsExcludedFromSyncKey, .contentAccessDateKey, .contentModificationDateKey,
    ]

    /// Downloaded files of at least `minSize`. Files still uploading, kept out of sync or not yet
    /// in iCloud are skipped: their only copy may be the one on this Mac.
    static func scan(minSize: Int64, root: URL = root(), progress: @Sendable (Int) -> Void) -> [CloudFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }
        var found: [CloudFile] = []
        var visited = 0
        enumerator.forEachURL { url in
            if Task.isCancelled { return false }
            visited += 1
            if visited % 500 == 0 { progress(visited) }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { return true }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard size >= minSize, isEvictable(values) else { return true }
            found.append(CloudFile(url: url, size: size, lastUsed: values.contentAccessDate ?? values.contentModificationDate))
            return true
        }
        progress(visited)
        return Task.isCancelled ? [] : found.sorted { $0.size > $1.size }
    }

    static func isEvictable(_ values: URLResourceValues) -> Bool {
        values.isUbiquitousItem == true
            && values.ubiquitousItemDownloadingStatus == .current
            && values.ubiquitousItemIsUploaded == true
            && values.ubiquitousItemIsUploading != true
            && values.ubiquitousItemIsExcludedFromSync != true
    }

    /// Checks the file again and asks iCloud to drop the local copy. The file itself stays in iCloud.
    static func evict(_ file: CloudFile, root: URL = root()) -> Bool {
        let path = file.url.standardizedFileURL.path
        // The scan's URL still holds the values read then; this must see whether the file is uploaded now.
        var current = file.url
        current.removeAllCachedResourceValues()
        guard path.hasPrefix(root.standardizedFileURL.path + "/"),
              let values = try? current.resourceValues(forKeys: Set(keys)), isEvictable(values) else { return false }
        return (try? FileManager.default.evictUbiquitousItem(at: file.url)) != nil
    }
}
