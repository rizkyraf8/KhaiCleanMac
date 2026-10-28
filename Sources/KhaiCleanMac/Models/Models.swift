import SwiftUI

enum Module: String, CaseIterable, Identifiable {
    case smartScan, largeFiles, duplicates, developer, spaceLens, uninstaller, memory

    enum Section: String, CaseIterable {
        case clean, manage

        var title: String {
            switch self {
            case .clean: L("BERSIHKAN", "CLEAN UP")
            case .manage: L("KELOLA", "MANAGE")
            }
        }
    }

    var id: String { rawValue }

    var section: Section {
        switch self {
        case .smartScan, .largeFiles, .duplicates, .developer: .clean
        case .spaceLens, .uninstaller, .memory: .manage
        }
    }

    var title: String {
        switch self {
        case .smartScan: "Smart Scan"
        case .largeFiles: L("File Besar", "Large Files")
        case .duplicates: L("Duplikat", "Duplicates")
        case .developer: "Developer"
        case .spaceLens: "Space Lens"
        case .memory: L("Memori", "Memory")
        case .uninstaller: "Uninstaller"
        }
    }

    var tagline: String {
        switch self {
        case .smartScan: L("Cache, log & sampah", "Caches, logs & junk")
        case .largeFiles: L("Yang makan tempat", "Space hogs")
        case .duplicates: L("File kembar", "Identical files")
        case .developer: L("Sisa coding & build", "Coding leftovers")
        case .spaceLens: L("Peta isi disk", "Disk map")
        case .memory: L("RAM & app terboros", "RAM & heavy apps")
        case .uninstaller: L("Hapus app sampai bersih", "Remove apps completely")
        }
    }

    var subtitle: String {
        switch self {
        case .smartScan: L("Bersihkan cache, log, dan sisa file yang tidak terpakai.", "Clean up caches, logs and leftover files you no longer need.")
        case .largeFiles: L("Temukan file berukuran besar di folder pribadimu.", "Find big files in your home folder.")
        case .duplicates: L("Temukan file dengan isi yang persis sama.", "Find files with exactly the same content.")
        case .developer: L("Bersihkan dependensi proyek lama, cache package manager, dan arsip Xcode.", "Clean up old project dependencies, package manager caches and Xcode archives.")
        case .spaceLens: L("Lihat folder mana yang paling banyak makan tempat.", "See which folders take up the most space.")
        case .memory: L("Lihat tekanan memori dan app yang paling banyak memakai RAM.", "See memory pressure and the apps using the most RAM.")
        case .uninstaller: L("Hapus aplikasi beserta file sisa yang ditinggalkannya.", "Remove apps together with the files they leave behind.")
        }
    }

    var symbol: String {
        switch self {
        case .smartScan: "sparkles"
        case .largeFiles: "doc.text.magnifyingglass"
        case .duplicates: "doc.on.doc.fill"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .spaceLens: "square.split.2x2.fill"
        case .memory: "memorychip.fill"
        case .uninstaller: "xmark.bin.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .smartScan: Palette.mint
        case .largeFiles: Palette.peach
        case .duplicates: Palette.sky
        case .developer: Palette.ocean
        case .spaceLens: Palette.candy
        case .memory: Palette.leaf
        case .uninstaller: Palette.lavender
        }
    }
}

/// A file or folder that can be moved to the Trash.
struct CleanItem: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    /// Shown instead of the file name, for items that stand for a group of files.
    var title: String? = nil
    /// Shown instead of the parent folder path.
    var detail: String? = nil
    /// When set, only these files inside `url` are removed, not `url` itself
    /// (e.g. the stale entries of a cache folder that stays in use).
    var members: [URL] = []

    var id: URL { url }
    var name: String { title ?? url.lastPathComponent }
}

enum JunkKind: String, CaseIterable, Identifiable, Sendable {
    case userCache, chrome, userLogs, developer, installers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userCache: L("Cache Aplikasi", "App Caches")
        case .chrome: L("Cache Chrome", "Chrome Cache")
        case .userLogs: L("Log Aplikasi", "App Logs")
        case .developer: L("Sampah Xcode", "Xcode Junk")
        case .installers: L("Installer Lama", "Old Installers")
        }
    }

    var subtitle: String {
        switch self {
        case .userCache: L("File sementara yang dibuat ulang otomatis oleh aplikasi.", "Temporary files that apps rebuild automatically.")
        case .chrome: L("Hanya cache lama dan usang. Cache yang masih aktif tetap disimpan.", "Only old and obsolete cache. Cache still in use is kept.")
        case .userLogs: L("Catatan aktivitas lama yang jarang dibutuhkan.", "Old activity records you rarely need.")
        case .developer: L("DerivedData, Device Support, dan cache simulator.", "DerivedData, Device Support and simulator caches.")
        case .installers: L("File .dmg dan .pkg di folder Downloads.", ".dmg and .pkg files in your Downloads folder.")
        }
    }

    var symbol: String {
        switch self {
        case .userCache: "internaldrive.fill"
        case .chrome: "globe"
        case .userLogs: "doc.plaintext.fill"
        case .developer: "hammer.fill"
        case .installers: "shippingbox.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .userCache: Palette.leaf
        case .chrome: Palette.sky
        case .userLogs: Palette.sunny
        case .developer: Palette.ocean
        case .installers: Palette.candy
        }
    }

    /// Installers are personal downloads, so the user opts in explicitly.
    var selectedByDefault: Bool { self != .installers }
}

struct JunkCategory: Identifiable, Sendable {
    let kind: JunkKind
    let items: [CleanItem]

    var id: JunkKind { kind }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

enum FileKind: String, CaseIterable, Identifiable, Sendable {
    case video, audio, image, archive, diskImage, document, other

    var id: String { rawValue }

    init(pathExtension ext: String) {
        switch ext.lowercased() {
        case "mp4", "mov", "m4v", "mkv", "avi", "wmv", "flv", "webm", "mts":
            self = .video
        case "mp3", "wav", "aiff", "aif", "flac", "m4a", "aac", "ogg", "caf":
            self = .audio
        case "jpg", "jpeg", "png", "heic", "tif", "tiff", "gif", "psd", "raw", "cr2", "cr3", "nef", "arw", "dng":
            self = .image
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz":
            self = .archive
        case "dmg", "iso", "pkg", "mpkg", "xip", "img", "sparseimage", "sparsebundle":
            self = .diskImage
        case "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "key", "pages", "numbers", "epub":
            self = .document
        default:
            self = .other
        }
    }

    var title: String {
        switch self {
        case .video: "Video"
        case .audio: "Audio"
        case .image: L("Gambar", "Images")
        case .archive: L("Arsip", "Archives")
        case .diskImage: L("Disk Image", "Disk Images")
        case .document: L("Dokumen", "Documents")
        case .other: L("Lainnya", "Other")
        }
    }

    var symbol: String {
        switch self {
        case .video: "film.fill"
        case .audio: "music.note"
        case .image: "photo.fill"
        case .archive: "archivebox.fill"
        case .diskImage: "opticaldiscdrive.fill"
        case .document: "doc.richtext.fill"
        case .other: "doc.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .video: Palette.berry
        case .audio: Palette.candy
        case .image: Palette.sky
        case .archive: Palette.sunny
        case .diskImage: Palette.ocean
        case .document: Palette.leaf
        case .other: Palette.slate
        }
    }
}

struct LargeFile: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let lastUsed: Date?
    let kind: FileKind

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var item: CleanItem { CleanItem(url: url, size: size) }
}

enum SizeThreshold: Int64, CaseIterable, Identifiable {
    case mb50 = 50_000_000
    case mb100 = 100_000_000
    case mb500 = 500_000_000
    case gb1 = 1_000_000_000

    var id: Int64 { rawValue }
    var label: String { rawValue.formattedBytes }
}

struct InstalledApp: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String?
    /// Names used to look for leftover folders (file name and CFBundleName).
    let searchNames: [String]

    var id: URL { url }
}

struct CleanReport: Sendable {
    var movedCount = 0
    var movedSize: Int64 = 0
    var failed: [CleanItem] = []
}

struct DuplicateFile: Identifiable, Hashable, Sendable {
    let url: URL
    let modified: Date?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Files whose contents are byte-for-byte identical.
struct DuplicateGroup: Identifiable, Hashable, Sendable {
    let id: String
    let size: Int64
    var files: [DuplicateFile]

    /// Space freed if every copy but one were removed.
    var wasted: Int64 { size * Int64(max(files.count - 1, 0)) }
}

/// One entry in a Space Lens folder; `size` stays nil until it has been measured.
struct SpaceItem: Identifiable, Hashable, Sendable {
    let url: URL
    let canOpen: Bool
    var size: Int64?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}
