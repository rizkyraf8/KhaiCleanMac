import AppKit
import ImageIO

/// A photo in a similar-looking group, with what's needed to pick the best copy and to notice changes.
struct SimilarPhoto: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let pixelWidth: Int
    let pixelHeight: Int
    let modified: Date?
    let hash: UInt64

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var pixels: Int { pixelWidth * pixelHeight }
}

struct SimilarGroup: Identifiable, Hashable, Sendable {
    let id: String
    /// Best first: the most pixels, then the biggest file.
    var photos: [SimilarPhoto]

    /// Space freed if every photo but the best one went.
    var reclaimable: Int64 { photos.dropFirst().reduce(0) { $0 + $1.size } }
}

/// Finds photos that look alike with a difference hash (dHash): each photo shrinks to 9 × 8 grey pixels,
/// and each bit says whether a pixel is brighter than its right neighbour. Resizing, recompressing
/// or a small edit changes only a few bits, so photos whose hashes differ in at most `maxDistance`
/// bits are grouped.
struct SimilarPhotoScanner: Sendable {
    enum Progress: Sendable {
        case collecting(Int)
        case hashing(Double)
    }

    static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]
    /// Below 8 the groups stay tight: burst shots and resized copies, not just photos of the same place.
    var maxDistance = 6
    var minSize: Int64 = 100_000

    static func defaultRoots(home: URL = .homeDirectory) -> [URL] {
        ["Pictures", "Desktop", "Downloads", "Documents"].map { home.appending(path: $0, directoryHint: .isDirectory) }
    }

    func scan(roots: [URL] = defaultRoots(), progress: @Sendable (Progress) -> Void) -> [SimilarGroup] {
        let files = collect(roots: roots, progress: progress)
        var photos: [SimilarPhoto] = []
        for (index, file) in files.enumerated() {
            if Task.isCancelled { return [] }
            if index % 20 == 0 { progress(.hashing(Double(index) / Double(max(files.count, 1)))) }
            if let photo = autoreleasepool(invoking: { Self.photo(file.url, size: file.size, modified: file.modified) }) {
                photos.append(photo)
            }
        }
        progress(.hashing(1))
        return Self.group(photos, maxDistance: maxDistance)
    }

    private func collect(roots: [URL], progress: (Progress) -> Void) -> [(url: URL, size: Int64, modified: Date?)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .fileResourceIdentifierKey,
                                      .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        var found: [(url: URL, size: Int64, modified: Date?)] = []
        var seen = Set<NSObject>()
        var visited = 0
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }) else { continue }
            enumerator.forEachURL { url in
                if Task.isCancelled { return false }
                visited += 1
                if visited % 1_500 == 0 { progress(.collecting(visited)) }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { return true }
                if values.isDirectory == true {
                    if DuplicateScanner.isProtected(url) { enumerator.skipDescendants() }
                    return true
                }
                guard values.isRegularFile == true, Self.extensions.contains(url.pathExtension.lowercased()),
                      let size = values.fileSize.map(Int64.init), size >= minSize else { return true }
                // Reading an iCloud photo that isn't downloaded would pull it from the cloud.
                if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current { return true }
                if let identity = values.fileResourceIdentifier as? NSObject, !seen.insert(identity).inserted { return true }
                found.append((url, size, values.contentModificationDate))
                return true
            }
        }
        progress(.collecting(visited))
        return found
    }

    static func photo(_ url: URL, size: Int64, modified: Date?) -> SimilarPhoto? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let hash = dHash(source) else { return nil }
        return SimilarPhoto(url: url, size: size, pixelWidth: width, pixelHeight: height, modified: modified, hash: hash)
    }

    /// The 64-bit difference hash, from the photo's embedded preview when it has one, so big RAW and
    /// HEIC photos aren't decoded in full: 9 × 8 pixels need nothing more.
    static func dHash(_ source: CGImageSource) -> UInt64? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return dHash(thumbnail)
    }

    static func dHash(_ image: CGImage) -> UInt64? {
        let width = 9, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var hash: UInt64 = 0
        for row in 0..<height {
            for column in 0..<(width - 1) {
                hash <<= 1
                if pixels[row * width + column] > pixels[row * width + column + 1] { hash |= 1 }
            }
        }
        return hash
    }

    /// Groups photos whose hashes are within `maxDistance` bits. With at most 7 differing bits, two
    /// hashes share at least one of their eight bytes, so only photos sharing a byte are compared.
    static func group(_ photos: [SimilarPhoto], maxDistance: Int) -> [SimilarGroup] {
        precondition(maxDistance < 8, "The byte buckets only find every match below 8 differing bits")
        let photos = photos.filter { isInformative($0.hash) }
        var parent = Array(photos.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }
        var buckets: [Int: [Int]] = [:]
        for (index, photo) in photos.enumerated() {
            for block in 0..<8 {
                let byte = Int((photo.hash >> UInt64(block * 8)) & 0xFF)
                buckets[block << 8 | byte, default: []].append(index)
            }
        }
        for members in buckets.values where members.count > 1 {
            if Task.isCancelled { return [] }
            for (offset, first) in members.enumerated() {
                for second in members[(offset + 1)...] where (photos[first].hash ^ photos[second].hash).nonzeroBitCount <= maxDistance {
                    let a = root(first), b = root(second)
                    if a != b { parent[a] = b }
                }
            }
        }
        let grouped = Dictionary(grouping: photos.indices, by: root).values.filter { $0.count > 1 }
        return grouped.map { indices in
            let sorted = indices.map { photos[$0] }.sorted { ($0.pixels, $0.size) > ($1.pixels, $1.size) }
            return SimilarGroup(id: sorted[0].url.path, photos: sorted)
        }
        .sorted { $0.reclaimable > $1.reclaimable }
    }

    /// A blank screenshot, a flat logo or a smooth gradient has (almost) no differences between
    /// neighbouring pixels, so its hash is nearly all 0s or all 1s whatever it shows. Such photos
    /// would all look alike, so they're left out rather than grouped.
    static func isInformative(_ hash: UInt64) -> Bool {
        let bits = hash.nonzeroBitCount
        return bits > 4 && bits < 60
    }

    /// A photo is only removed when it's still the file that was scanned (same size and date) and
    /// another photo of its group stays.
    static func verifiedRemovals(in group: SimilarGroup, selected: Set<URL>) -> [SimilarPhoto] {
        let kept = group.photos.filter { !selected.contains($0.url) && FileManager.default.fileExists(atPath: $0.url.path) }
        guard !kept.isEmpty else { return [] }
        return group.photos.filter { photo in
            // A URL caches what it read during the scan; this must see the file as it is now.
            var current = photo.url
            current.removeAllCachedResourceValues()
            guard selected.contains(photo.url),
                  let values = try? current.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { return false }
            return Int64(values.fileSize ?? -1) == photo.size && values.contentModificationDate == photo.modified
        }
    }

    /// A small preview for the list, made from the file's embedded thumbnail when it has one.
    static func thumbnail(_ url: URL, maxPixels: Int = 240) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
