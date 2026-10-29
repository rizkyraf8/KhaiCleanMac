import AppKit
import SwiftUI

/// A version like "v0.4.0" or "0.4", compared number by number (0.10.0 is newer than 0.9.0).
struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    let numbers: [Int]

    /// Accepts an optional "v" and ignores suffixes such as "-beta"; nil for things like "dev".
    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let core = text.split(separator: "-", maxSplits: 1).first.map(String.init) ?? text
        let numbers = core.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        self.numbers = numbers.compactMap { $0 }
    }

    var description: String { numbers.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// The newest published build, as described by rizkyraf.id.
struct LatestRelease: Sendable, Equatable {
    let version: AppVersion
    let notes: String?
    let fileName: String?
    let size: Int64?
    let downloadURL: URL?
    let releasedAt: Date?
    /// Lowercase hex SHA-256 of the DMG. Without it the app only offers the browser download.
    var sha256: String? = nil
    /// The project page, used when there is no direct download link.
    var pageURL: URL? = nil
}

enum UpdateAPI {
    static let endpoint = URL(string: "https://rizkyraf.id/api/projects/khaicleanmac/latest")!
    static let projectPage = URL(string: "https://rizkyraf.id/projects/khaicleanmac")!

    private struct Response: Decodable {
        struct Project: Decodable { let url: String? }
        struct Latest: Decodable {
            let version: String
            let notes: String?
            let file_name: String?
            let size: Int64?
            let download_url: String?
            let released_at: String?
            let sha256: String?
        }
        let project: Project?
        let latest: Latest
    }

    /// Only https links on rizkyraf.id (or a subdomain) are opened. If the server were ever tampered
    /// with, a `file://` link could launch a local app and an `http://` one could swap the download.
    static func trustedURL(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string), url.scheme?.lowercased() == "https",
              let host = url.host()?.lowercased(), url.user() == nil, url.password() == nil else { return nil }
        return host == "rizkyraf.id" || host.hasSuffix(".rizkyraf.id") ? url : nil
    }

    /// 64 hex characters, or nothing.
    static func checksum(_ string: String?) -> String? {
        guard let text = string?.trimmingCharacters(in: .whitespaces).lowercased(), text.count == 64,
              text.allSatisfy({ $0.isHexDigit }) else { return nil }
        return text
    }

    enum Failure: Error {
        case badStatus(Int)
        case unreadableVersion(String)
    }

    static func decode(_ data: Data) throws -> LatestRelease {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let version = AppVersion(response.latest.version) else {
            throw Failure.unreadableVersion(response.latest.version)
        }
        let notes = response.latest.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LatestRelease(
            version: version,
            notes: notes?.isEmpty == false ? notes : nil,
            fileName: response.latest.file_name,
            size: response.latest.size,
            downloadURL: trustedURL(response.latest.download_url),
            releasedAt: response.latest.released_at.flatMap { try? Date($0, strategy: .iso8601) },
            sha256: checksum(response.latest.sha256),
            pageURL: trustedURL(response.project?.url)
        )
    }

    /// Sends no personal data: only the app's own version, as the User-Agent.
    static func fetch() async throws -> LatestRelease {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.badStatus(status) }
        return try decode(data)
    }
}

/// Checks rizkyraf.id for a newer KhaiCleanMac: once a day when enabled, or whenever the user asks.
@MainActor @Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle, checking, upToDate, available, failed
    }

    /// The in-app install, from the "Update" button to the relaunch.
    enum InstallStep: Equatable {
        case idle, downloading, verifying, installing
        case failed(AppUpdater.Failure)

        var isBusy: Bool { self == .downloading || self == .verifying || self == .installing }
    }

    private(set) var status: Status = .idle
    private(set) var latest: LatestRelease?
    private(set) var installStep: InstallStep = .idle

    private static let interval: TimeInterval = 24 * 60 * 60

    /// The installed version; nil for a development build ("dev").
    var installed: AppVersion? {
        #if DEBUG
        if let installedOverride { return installedOverride }
        #endif
        return AppVersion(AppInfo.version)
    }

    #if DEBUG
    /// Debug snapshots only: show the "update available" screens without a real newer release.
    var installedOverride: AppVersion?

    func preview(_ release: LatestRelease?, installed: AppVersion?, step: InstallStep = .idle) {
        installedOverride = installed
        latest = release
        status = release == nil ? .idle : (isUpdateAvailable ? .available : .upToDate)
        installStep = step
    }
    #endif

    var isUpdateAvailable: Bool {
        guard let latest, let installed else { return false }
        return installed < latest.version
    }

    /// Runs the daily check if it's on and a day has passed since the last one.
    func checkIfDue() async {
        let settings = AppSettings.shared
        guard settings.checksForUpdates, !AppInfo.isSnapshot, status != .checking else { return }
        if let last = settings.lastUpdateCheck, Date().timeIntervalSince(last) < Self.interval, latest != nil { return }
        await check()
    }

    func check() async {
        guard status != .checking else { return }
        withAnimation(.snappy) { status = .checking }
        do {
            let release = try await UpdateAPI.fetch()
            AppSettings.shared.lastUpdateCheck = Date()
            withAnimation(.snappy) {
                latest = release
                status = isUpdateAvailable ? .available : .upToDate
            }
        } catch {
            withAnimation(.snappy) { status = .failed }
        }
    }

    /// True when the update can be installed here; otherwise the button opens the browser download.
    var canInstallInApp: Bool {
        guard isUpdateAvailable, let latest else { return false }
        #if DEBUG
        if installedOverride != nil { return latest.sha256 != nil }
        #endif
        return AppUpdater.canInstall(latest)
    }

    /// Download, verify and swap in the new version, then relaunch. Every check happens before the
    /// installed app is touched; if one fails, the old app keeps running as it is.
    func install() async {
        guard canInstallInApp, !installStep.isBusy, let latest, let link = latest.downloadURL, let checksum = latest.sha256 else {
            openDownload()
            return
        }
        let current = Bundle.main.bundleURL
        withAnimation(.snappy) { installStep = .downloading }
        do {
            let dmg = try await AppUpdater.download(link)
            withAnimation(.snappy) { installStep = .verifying }
            let staged = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                defer { try? FileManager.default.removeItem(at: dmg) }
                if let size = latest.size, (try? dmg.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) != size { throw AppUpdater.Failure.checksumMismatch }
                guard try AppUpdater.sha256(of: dmg) == checksum else { throw AppUpdater.Failure.checksumMismatch }
                return try AppUpdater.stage(dmg: dmg, expectedVersion: latest.version, nextTo: current)
            }.value
            withAnimation(.snappy) { installStep = .installing }
            do {
                try AppUpdater.swapAndRelaunch(staged: staged, current: current)
            } catch {
                try? FileManager.default.removeItem(at: staged)
                throw error
            }
            NSApp.terminate(nil)
        } catch {
            withAnimation(.snappy) { installStep = .failed(error as? AppUpdater.Failure ?? .download) }
        }
    }

    /// Opens the direct download, falling back to the project page.
    func openDownload() {
        NSWorkspace.shared.open(latest?.downloadURL ?? latest?.pageURL ?? UpdateAPI.projectPage)
    }

    func openProjectPage() {
        NSWorkspace.shared.open(latest?.pageURL ?? UpdateAPI.projectPage)
    }
}
