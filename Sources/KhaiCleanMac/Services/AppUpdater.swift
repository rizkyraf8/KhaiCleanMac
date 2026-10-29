import AppKit
import CryptoKit

/// Installs a newer KhaiCleanMac from inside the app:
/// download → SHA-256 must match the API → mount read-only → the app inside must be KhaiCleanMac at the
/// announced version with an intact code signature → swap it in place of the running copy → relaunch.
/// Any failed check stops the update and leaves the installed app untouched.
enum AppUpdater {
    enum Failure: Error, Equatable {
        case notInstallable, download, checksumMismatch, mount, appMissing, wrongApp, wrongVersion, badSignature, install
    }

    static var workFolder: URL {
        URL.homeDirectory.appending(path: "Library/Caches/\(AppInfo.bundleID)/Update")
    }

    /// In-app updates need a real .app in a folder we can write to, and a checksum to verify against.
    static func canInstall(_ release: LatestRelease, app: URL = Bundle.main.bundleURL) -> Bool {
        release.sha256 != nil && release.downloadURL != nil && app.pathExtension == "app"
            && FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    // MARK: Steps

    /// The link starts on rizkyraf.id and redirects to file storage on another host, so the host of the
    /// final URL isn't what makes the file trustworthy: the SHA-256 from the API is.
    static func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.url?.scheme?.lowercased() == "https" else { throw Failure.download }
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        let destination = workFolder.appending(path: "KhaiCleanMac-update.dmg")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let more = try autoreleasepool { () -> Bool in
                guard let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty else { return false }
                hasher.update(data: chunk)
                return true
            }
            if !more { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Mounts the DMG, checks the app inside and copies it into `current`'s folder.
    /// Returns the staged copy, ready to be swapped in.
    static func stage(dmg: URL, expectedVersion: AppVersion, nextTo current: URL) throws -> URL {
        guard let mount = attach(dmg) else { throw Failure.mount }
        defer { detach(mount) }
        let newApp = mount.appending(path: "\(AppInfo.name).app")
        guard FileManager.default.fileExists(atPath: newApp.path) else { throw Failure.appMissing }
        try check(newApp, expectedVersion: expectedVersion, signedLike: current)

        let staged = current.deletingLastPathComponent().appending(path: ".\(AppInfo.name)-update.app")
        try? FileManager.default.removeItem(at: staged)
        guard StartupScanner.run("/usr/bin/ditto", [newApp.path, staged.path]) != nil else { throw Failure.install }
        // The copy must still be the same, intact app.
        try check(staged, expectedVersion: expectedVersion, signedLike: current)
        return staged
    }

    static func check(_ app: URL, expectedVersion: AppVersion, signedLike current: URL) throws {
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == AppInfo.bundleID else { throw Failure.wrongApp }
        let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
        guard version == expectedVersion else { throw Failure.wrongVersion }
        guard StartupScanner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) != nil,
              sameSigner(app, as: current) else {
            throw Failure.badSignature
        }
    }

    /// When the running app is signed with a certificate, the update must be signed with that same one.
    /// An ad-hoc signed app has no certificate to compare, so the checksum is the check there.
    static func sameSigner(_ app: URL, as current: URL) -> Bool {
        guard let mine = leafCertificate(current) else { return true }
        return leafCertificate(app) == mine
    }

    private static func leafCertificate(_ app: URL) -> Data? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let certificates = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return nil }
        return SecCertificateCopyData(leaf) as Data
    }

    /// Hands over to a small script that waits for this app to quit, swaps the bundles, and opens the
    /// new one. If the swap fails, the old app is put back. Paths go in as arguments, never into the script text.
    static func swapAndRelaunch(staged: URL, current: URL) throws {
        let script = workFolder.appending(path: "swap.sh")
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        try """
        #!/bin/sh
        pid="$1"; current="$2"; staged="$3"; backup="$2.previous"
        i=0
        while /bin/kill -0 "$pid" 2>/dev/null && [ "$i" -lt 150 ]; do /bin/sleep 0.2; i=$((i + 1)); done
        /bin/rm -rf "$backup"
        if /bin/mv "$current" "$backup" && /bin/mv "$staged" "$current"; then
            /usr/bin/open "$current"
            /bin/rm -rf "$backup"
        else
            if [ -d "$backup" ] && [ ! -d "$current" ]; then /bin/mv "$backup" "$current"; fi
            /usr/bin/open "$current"
        fi
        """.write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), current.path, staged.path]
        do { try process.run() } catch { throw Failure.install }
    }

    // MARK: Disk images

    private static func attach(_ dmg: URL) -> URL? {
        guard let output = StartupScanner.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-plist"]),
              let plist = try? PropertyListSerialization.propertyList(from: Data(output.utf8), format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mount = entities.compactMap({ $0["mount-point"] as? String }).first else { return nil }
        return URL(filePath: mount)
    }

    private static func detach(_ mount: URL) {
        StartupScanner.run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"])
    }
}
