import SwiftUI

enum Module: String, CaseIterable, Identifiable {
    case home, smartScan, largeFiles, duplicates, developer, privacy, spaceLens, uninstaller, appUpdates, extensions, startup, memory, history

    enum Section: String, CaseIterable {
        case overview, clean, manage

        /// Empty for the overview, which has no heading.
        var title: String {
            switch self {
            case .overview: ""
            case .clean: L("BERSIHKAN", "CLEAN UP")
            case .manage: L("KELOLA", "MANAGE")
            }
        }
    }

    var id: String { rawValue }

    var section: Section {
        switch self {
        case .home: .overview
        case .smartScan, .largeFiles, .duplicates, .developer, .privacy: .clean
        case .spaceLens, .uninstaller, .appUpdates, .extensions, .startup, .memory, .history: .manage
        }
    }

    var title: String {
        switch self {
        case .smartScan: "Smart Scan"
        case .largeFiles: L("File Besar", "Large Files")
        case .duplicates: L("Duplikat", "Duplicates")
        case .developer: "Developer"
        case .spaceLens: "Space Lens"
        case .home: L("Beranda", "Home")
        case .startup: "Login Items"
        case .memory: L("Memori", "Memory")
        case .history: L("Riwayat", "History")
        case .extensions: L("Ekstensi", "Extensions")
        case .uninstaller: "Uninstaller"
        case .appUpdates: L("Pembaruan App", "App Updates")
        case .privacy: L("Privasi", "Privacy")
        }
    }

    var tagline: String {
        switch self {
        case .smartScan: L("Cache, log & sampah", "Caches, logs & junk")
        case .largeFiles: L("Yang makan tempat", "Space hogs")
        case .duplicates: L("File kembar", "Identical files")
        case .developer: L("Sisa coding & build", "Coding leftovers")
        case .spaceLens: L("Peta isi disk", "Disk map")
        case .home: L("Ringkasan & semua fitur", "Overview & all features")
        case .startup: L("Yang jalan saat login", "What starts at login")
        case .memory: L("RAM & app terboros", "RAM & heavy apps")
        case .history: L("Yang sudah dibersihkan", "What was cleaned")
        case .extensions: L("Plug-in & ekstensi app", "Plug-ins & app extensions")
        case .uninstaller: L("Hapus app sampai bersih", "Remove apps completely")
        case .appUpdates: L("Versi baru app kamu", "New versions of your apps")
        case .privacy: L("Riwayat & cookie browser", "Browser history & cookies")
        }
    }

    var subtitle: String {
        switch self {
        case .smartScan: L("Bersihkan cache, log, dan sisa file yang tidak terpakai.", "Clean up caches, logs and leftover files you no longer need.")
        case .largeFiles: L("Temukan file berukuran besar di folder pribadimu.", "Find big files in your home folder.")
        case .duplicates: L("Temukan file dengan isi yang persis sama.", "Find files with exactly the same content.")
        case .developer: L("Bersihkan dependensi proyek lama, cache package manager, simulator, dan arsip Xcode.", "Clean up old project dependencies, package manager caches, simulators and Xcode archives.")
        case .spaceLens: L("Lihat folder mana yang paling banyak makan tempat.", "See which folders take up the most space.")
        case .home: L("Ringkasan kondisi Mac dan semua fitur KhaiCleanMac.", "An overview of your Mac and every KhaiCleanMac feature.")
        case .startup: L("Atur app dan agent yang otomatis jalan saat login, dan bersihkan yang yatim.", "Manage the apps and agents that start at login, and clean up orphans.")
        case .memory: L("Lihat tekanan memori dan app yang paling banyak memakai RAM.", "See memory pressure and the apps using the most RAM.")
        case .history: L("Semua yang pernah dibersihkan, dan kembalikan yang masih ada di Trash.", "Everything you've cleaned, and put back what's still in the Trash.")
        case .extensions: L("Atur ekstensi Safari, Finder, widget, Quick Look, dan plug-in lain.", "Manage Safari, Finder, widget and Quick Look extensions and other plug-ins.")
        case .uninstaller: L("Hapus aplikasi beserta file sisa yang ditinggalkannya.", "Remove apps together with the files they leave behind.")
        case .appUpdates: L("Cari tahu app mana yang punya versi lebih baru.", "Find out which apps have a newer version.")
        case .privacy: L("Hapus riwayat, cookie, dan isian formulir browser. Hanya yang kamu pilih.", "Clear browser history, cookies and form data. Only what you pick.")
        }
    }

    var symbol: String {
        switch self {
        case .smartScan: "sparkles"
        case .largeFiles: "doc.text.magnifyingglass"
        case .duplicates: "doc.on.doc.fill"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .spaceLens: "square.split.2x2.fill"
        case .home: "house.fill"
        case .startup: "power"
        case .memory: "memorychip.fill"
        case .history: "clock.arrow.circlepath"
        case .extensions: "puzzlepiece.extension.fill"
        case .uninstaller: "xmark.bin.fill"
        case .appUpdates: "arrow.down.app.fill"
        case .privacy: "hand.raised.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .smartScan: Palette.mint
        case .largeFiles: Palette.peach
        case .duplicates: Palette.sky
        case .developer: Palette.ocean
        case .spaceLens: Palette.candy
        case .home: Palette.logo
        case .startup: Palette.sunny
        case .memory: Palette.leaf
        case .history: Palette.grape
        case .extensions: Palette.sky
        case .uninstaller: Palette.lavender
        case .appUpdates: Palette.aqua
        case .privacy: Palette.blush
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
    /// Items that are already in the Trash can only be deleted for good.
    var removesPermanently = false
    /// Matched only by a guess (e.g. a folder named like the app), so it's never preselected.
    var isGuess = false

    var id: URL { url }
    var name: String { title ?? url.lastPathComponent }
}

enum JunkKind: String, CaseIterable, Identifiable, Sendable {
    case userCache, browsers, userLogs, developer, installers, oldDownloads, mailDownloads, iosBackups, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userCache: L("Cache Aplikasi", "App Caches")
        case .browsers: L("Cache Browser", "Browser Cache")
        case .userLogs: L("Log Aplikasi", "App Logs")
        case .developer: L("Sampah Xcode", "Xcode Junk")
        case .installers: L("Installer Lama", "Old Installers")
        case .oldDownloads: L("Downloads Lama", "Old Downloads")
        case .mailDownloads: L("Lampiran Mail", "Mail Attachments")
        case .iosBackups: L("Backup & Update iOS", "iOS Backups & Updates")
        case .trash: L("Isi Trash", "Trash")
        }
    }

    var subtitle: String {
        switch self {
        case .userCache: L("File sementara yang dibuat ulang otomatis oleh aplikasi.", "Temporary files that apps rebuild automatically.")
        case .browsers: L("Chrome, Brave, Edge, Arc, Vivaldi, Firefox, Safari. Hanya cache lama dan usang.", "Chrome, Brave, Edge, Arc, Vivaldi, Firefox, Safari. Only old and obsolete cache.")
        case .userLogs: L("Catatan aktivitas lama yang jarang dibutuhkan.", "Old activity records you rarely need.")
        case .developer: L("DerivedData, Device Support, dan cache simulator.", "DerivedData, Device Support and simulator caches.")
        case .installers: L("File .dmg dan .pkg di folder Downloads.", ".dmg and .pkg files in your Downloads folder.")
        case .oldDownloads: L("File di Downloads yang sudah lama tidak dibuka.", "Files in Downloads you haven't opened in a long time.")
        case .mailDownloads: L("Salinan lampiran yang pernah dibuka dari Mail. Lampiran aslinya tetap ada di email.", "Copies of attachments opened from Mail. The originals stay in your email.")
        case .iosBackups: L("Backup iPhone/iPad lama dan file update iOS (.ipsw).", "Old iPhone/iPad backups and iOS update files (.ipsw).")
        case .trash: L("Yang sudah ada di Trash. Dihapus permanen.", "What's already in the Trash. Deleted permanently.")
        }
    }

    var symbol: String {
        switch self {
        case .userCache: "internaldrive.fill"
        case .browsers: "globe"
        case .userLogs: "doc.plaintext.fill"
        case .developer: "hammer.fill"
        case .installers: "shippingbox.fill"
        case .oldDownloads: "arrow.down.circle.fill"
        case .mailDownloads: "envelope.fill"
        case .iosBackups: "iphone"
        case .trash: "trash.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .userCache: Palette.leaf
        case .browsers: Palette.sky
        case .userLogs: Palette.sunny
        case .developer: Palette.ocean
        case .installers: Palette.candy
        case .oldDownloads: Palette.peach
        case .mailDownloads: Palette.ocean
        case .iosBackups: Palette.lavender
        case .trash: Palette.berry
        }
    }

    /// Personal files (downloads, backups) and anything permanent are opt-in.
    var selectedByDefault: Bool {
        switch self {
        case .userCache, .browsers, .userLogs, .developer: true
        case .installers, .oldDownloads, .mailDownloads, .iosBackups, .trash: false
        }
    }

    /// macOS only lets the app read these places with Full Disk Access.
    var needsFullDiskAccess: Bool { self == .iosBackups || self == .trash || self == .mailDownloads }
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
    /// Items `SafetyGuard` refused to touch (protected locations).
    var blocked: [CleanItem] = []
    /// What was removed and where it went, for the cleanup history.
    var removed: [RemovedItem] = []
    /// True when items were deleted for good instead of moved to the Trash.
    var permanent = false
    /// Staging folders kept because the Trash refused them and some files couldn't go back.
    var keptInStaging: [URL] = []

    /// Everything still in place: items that failed to move and items `SafetyGuard` refused.
    /// Screens use this, never `failed` alone, so a refused item doesn't vanish from the list as if it went.
    var unremoved: [CleanItem] { failed + blocked }
    var isComplete: Bool { failed.isEmpty && blocked.isEmpty }
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

/// One removed item as kept in the cleanup history, with enough to put it back from the Trash.
struct RemovedItem: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let name: String
    let originalPath: String
    let size: Int64
    /// Where it went in the Trash; nil when it was deleted permanently.
    let trashedPath: String?
    /// For items made of many files: their paths relative to `originalPath`, kept at the same
    /// relative paths inside the trashed folder.
    let memberPaths: [String]
    var restoredAt: Date?
    /// The trashed item's file number. The Trash reuses names once it is emptied, so restore checks
    /// this to never move back an unrelated file that took the same name. Nil in older history.
    var trashedFileNumber: UInt64?

    /// `size` is what actually went, when that is less than the item's scanned size.
    init(_ item: CleanItem, trashedTo: URL?, memberPaths: [String], size: Int64? = nil) {
        name = item.name
        originalPath = item.url.path
        self.size = size ?? item.size
        trashedPath = trashedTo?.path
        self.memberPaths = memberPaths
        trashedFileNumber = trashedTo.flatMap(Self.fileNumber)
    }

    static func fileNumber(_ url: URL) -> UInt64? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? NSNumber)?.uint64Value
    }

    var canRestore: Bool { trashedPath != nil && restoredAt == nil }
}

/// One cleanup run: which module, when, and what it removed.
struct CleanRecord: Codable, Identifiable, Sendable {
    var id = UUID()
    let date: Date
    let source: String
    let permanent: Bool
    var items: [RemovedItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var restorableCount: Int { items.count(where: \.canRestore) }
}
