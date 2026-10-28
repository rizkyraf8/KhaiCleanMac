import SwiftUI

enum Module: String, CaseIterable, Identifiable {
    case smartScan, largeFiles, duplicates, spaceLens, uninstaller

    enum Section: String, CaseIterable {
        case clean = "BERSIHKAN"
        case manage = "KELOLA"
    }

    var id: String { rawValue }

    var section: Section {
        switch self {
        case .smartScan, .largeFiles, .duplicates: .clean
        case .spaceLens, .uninstaller: .manage
        }
    }

    var title: String {
        switch self {
        case .smartScan: "Smart Scan"
        case .largeFiles: "File Besar"
        case .duplicates: "Duplikat"
        case .spaceLens: "Space Lens"
        case .uninstaller: "Uninstaller"
        }
    }

    var tagline: String {
        switch self {
        case .smartScan: "Cache, log & sampah"
        case .largeFiles: "Yang makan tempat"
        case .duplicates: "File kembar"
        case .spaceLens: "Peta isi disk"
        case .uninstaller: "Hapus app sampai bersih"
        }
    }

    var subtitle: String {
        switch self {
        case .smartScan: "Bersihkan cache, log, dan sisa file yang tidak terpakai."
        case .largeFiles: "Temukan file berukuran besar di folder pribadimu."
        case .duplicates: "Temukan file dengan isi yang persis sama."
        case .spaceLens: "Lihat folder mana yang paling banyak makan tempat."
        case .uninstaller: "Hapus aplikasi beserta file sisa yang ditinggalkannya."
        }
    }

    var symbol: String {
        switch self {
        case .smartScan: "sparkles"
        case .largeFiles: "doc.text.magnifyingglass"
        case .duplicates: "doc.on.doc.fill"
        case .spaceLens: "square.split.2x2.fill"
        case .uninstaller: "xmark.bin.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .smartScan: Palette.mint
        case .largeFiles: Palette.peach
        case .duplicates: Palette.sky
        case .spaceLens: Palette.candy
        case .uninstaller: Palette.lavender
        }
    }
}

/// A file or folder that can be moved to the Trash.
struct CleanItem: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum JunkKind: String, CaseIterable, Identifiable, Sendable {
    case userCache, userLogs, developer, installers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userCache: "Cache Aplikasi"
        case .userLogs: "Log Aplikasi"
        case .developer: "Sampah Xcode"
        case .installers: "Installer Lama"
        }
    }

    var subtitle: String {
        switch self {
        case .userCache: "File sementara yang dibuat ulang otomatis oleh aplikasi."
        case .userLogs: "Catatan aktivitas lama yang jarang dibutuhkan."
        case .developer: "DerivedData, Device Support, dan cache simulator."
        case .installers: "File .dmg dan .pkg di folder Downloads."
        }
    }

    var symbol: String {
        switch self {
        case .userCache: "internaldrive.fill"
        case .userLogs: "doc.plaintext.fill"
        case .developer: "hammer.fill"
        case .installers: "shippingbox.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .userCache: Palette.leaf
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
        case .image: "Gambar"
        case .archive: "Arsip"
        case .diskImage: "Disk Image"
        case .document: "Dokumen"
        case .other: "Lainnya"
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
