import AppKit

/// Where Large Files, Duplicates and Space Lens look: the home folder or another mounted disk.
struct ScanLocation: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    /// A disk under /Volumes rather than the home folder.
    let isVolume: Bool
    let isRemovable: Bool

    var id: URL { url }
    var symbol: String { isVolume ? (isRemovable ? "externaldrive.fill" : "internaldrive.fill") : "house.fill" }

    static let home = ScanLocation(url: .homeDirectory, name: "Home", isVolume: false, isRemovable: false)

    /// Folders at the top of a disk that belong to macOS (a bootable copy, Spotlight, the Trash):
    /// scans step over them and nothing inside them is offered for removal.
    static let volumeSystemFolders: Set<String> = [
        "System", "Library", "private", "usr", "bin", "sbin", "cores", "opt", "Backups.backupdb",
        ".Spotlight-V100", ".fseventsd", ".Trashes", ".DocumentRevisions-V100", ".TemporaryItems",
        ".MobileBackups", ".PKInstallSandboxManager", ".PKInstallSandboxManager-SystemSoftware",
    ]

    /// Whether a walk starting at `root` should leave `folder` (and everything in it) out.
    static func skips(_ folder: URL, root: URL) -> Bool {
        let parent = folder.deletingLastPathComponent().standardizedFileURL.path
        guard parent == root.standardizedFileURL.path else { return false }
        if root.standardizedFileURL.path == URL.homeDirectory.standardizedFileURL.path {
            return folder.lastPathComponent == "Library"
        }
        return volumeSystemFolders.contains(folder.lastPathComponent)
    }
}

enum VolumeFinder {
    static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeIsRootFileSystemKey, .volumeIsReadOnlyKey,
        .volumeIsLocalKey, .volumeIsBrowsableKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey,
    ]

    /// Writable local disks the user can see in Finder, except the startup disk and Time Machine backups.
    static func volumes() -> [ScanLocation] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return location(url, values: values)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func location(_ url: URL, values: URLResourceValues) -> ScanLocation? {
        let components = url.standardizedFileURL.pathComponents
        guard components.count == 3, components[1] == "Volumes",
              values.volumeIsRootFileSystem != true,
              values.volumeIsReadOnly != true,
              values.volumeIsLocal != false,
              values.volumeIsBrowsable != false,
              !FileManager.default.fileExists(atPath: url.appending(path: "Backups.backupdb").path) else { return nil }
        let removable = values.volumeIsRemovable == true || values.volumeIsEjectable == true || values.volumeIsInternal == false
        return ScanLocation(url: url, name: values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent,
                            isVolume: true, isRemovable: removable)
    }
}

/// Mounted disks, kept current as disks come and go.
@MainActor @Observable
final class VolumeList {
    static let shared = VolumeList()

    private(set) var volumes: [ScanLocation] = []
    var locations: [ScanLocation] { [.home] + volumes }

    private init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { VolumeList.shared.refresh() }
            }
        }
    }

    func refresh() {
        volumes = VolumeFinder.volumes()
    }

    func contains(_ location: ScanLocation) -> Bool {
        !location.isVolume || volumes.contains { $0.url == location.url }
    }
}
