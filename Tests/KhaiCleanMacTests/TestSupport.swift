import Foundation

/// A throwaway folder for one test; removed when the test is done with it.
final class TempFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "KhaiCleanMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Creates a file (and its parent folders) with `size` bytes and the given dates.
    @discardableResult
    func file(_ path: String, size: Int = 16, contents: Data? = nil, daysOld: Double? = nil) throws -> URL {
        let file = url.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (contents ?? Data(repeating: 0x41, count: size)).write(to: file)
        if let daysOld { try age(file, days: daysOld) }
        return file
    }

    @discardableResult
    func folder(_ path: String) throws -> URL {
        let folder = url.appending(path: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Sets both "last opened" and "last modified" to `days` ago (negative means in the future).
    func age(_ file: URL, days: Double) throws {
        var values = URLResourceValues()
        let date = Date().addingTimeInterval(-days * 24 * 60 * 60)
        values.contentModificationDate = date
        values.contentAccessDate = date
        var target = file
        try target.setResourceValues(values)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appending(path: path).path)
    }
}
