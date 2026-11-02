import AppKit
import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct LocalSnapshotTests {
    @Test func parsesTmutilOutput() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-10-31-090000.local
        com.apple.TimeMachine.2026-11-01-123456.local
        com.apple.os.update-ABCDEF
        """
        let snapshots = LocalSnapshots.parse(output)
        #expect(snapshots.map(\.stamp) == ["2026-11-01-123456", "2026-10-31-090000"])
        #expect(snapshots.first?.date != nil)
    }

    @Test func onlyWellFormedStampsReachTheShell() {
        #expect(LocalSnapshots.isValidStamp("2026-11-01-123456"))
        #expect(!LocalSnapshots.isValidStamp("2026-11-01-123456; rm -rf ~"))
        #expect(!LocalSnapshots.isValidStamp("\"2026-11-01-123456"))
        // A malformed stamp never reaches the shell (and no admin prompt appears).
        #expect(LocalSnapshots.delete([.init(stamp: "x; reboot", date: nil)], list: { [] }).deleted == 0)
    }

    @Test func systemDataBucketsCoverTheUsualPlaces() {
        let ids = SystemDataScanner.buckets(home: URL(filePath: "/Users/me")).map(\.id)
        #expect(Set(ids).isSuperset(of: ["caches", "logs", "developer", "backups", "icloud", "containers", "mail", "swap"]))
    }
}

@Suite struct ICloudTests {
    @Test func localFilesAreNeverEvicted() throws {
        let temp = try TempFolder()
        let file = try temp.file("Mobile Documents/com~apple~CloudDocs/big.mov", size: 2_000_000)
        // A plain file isn't an iCloud item: its only copy is this one.
        #expect(ICloudScanner.scan(minSize: 1, root: temp.url.appending(path: "Mobile Documents")) { _ in }.isEmpty)
        #expect(!ICloudScanner.evict(CloudFile(url: file, size: 2_000_000, lastUsed: nil), root: temp.url.appending(path: "Mobile Documents")))
    }

    @Test func filesOutsideICloudDriveAreRefused() throws {
        let temp = try TempFolder()
        let file = try temp.file("Documents/report.pdf")
        #expect(!ICloudScanner.evict(CloudFile(url: file, size: 16, lastUsed: nil), root: temp.url.appending(path: "Mobile Documents")))
        #expect(temp.exists("Documents/report.pdf"))
    }
}

@Suite struct SimilarPhotoTests {
    private func photo(_ name: String, hash: UInt64, pixels: Int = 100, size: Int64 = 1000) -> SimilarPhoto {
        SimilarPhoto(url: URL(filePath: "/tmp/\(name).jpg"), size: size, pixelWidth: pixels, pixelHeight: pixels, modified: nil, hash: hash)
    }

    @Test func groupsHashesWithinTheDistance() {
        let base: UInt64 = 0xF0F0_F0F0_0F0F_0F0F
        let photos = [
            photo("a", hash: base, pixels: 400),
            photo("b", hash: base ^ 0b111, pixels: 800),         // 3 bits away
            photo("c", hash: base ^ 0xFF00_0000_0000_00FF),        // 16 bits away
            photo("d", hash: ~base),
        ]
        let groups = SimilarPhotoScanner.group(photos, maxDistance: 6)
        #expect(groups.count == 1)
        // The photo with the most pixels comes first and is the one kept.
        #expect(groups.first?.photos.map(\.name) == ["b.jpg", "a.jpg"])
        #expect(groups.first?.reclaimable == 1000)
    }

    @Test func groupsChainTogether() {
        // a–b and b–c are close, so all three end up together even though a and c differ more.
        let base: UInt64 = 0xF0F0_F0F0_0F0F_0F0F
        let photos = [photo("a", hash: base), photo("b", hash: base ^ 0b11_1111), photo("c", hash: base ^ 0b1111_1111_1111)]
        #expect(SimilarPhotoScanner.group(photos, maxDistance: 6).first?.photos.count == 3)
    }

    @Test func flatImagesAreNeverGrouped() {
        // Different flat images all hash to about 0 (or all 1s for a smooth gradient).
        let photos = [photo("white", hash: 0), photo("logo", hash: 0b1), photo("blue", hash: 0b100),
                      photo("ramp", hash: .max), photo("ramp2", hash: .max ^ 0b10)]
        #expect(SimilarPhotoScanner.group(photos, maxDistance: 6).isEmpty)
        #expect(!SimilarPhotoScanner.isInformative(0))
        #expect(SimilarPhotoScanner.isInformative(0xF0F0_F0F0_0F0F_0F0F))
    }

    @Test func resizedImageHasTheSameHash() throws {
        let original = try #require(Self.gradient(width: 400, height: 300))
        let small = try #require(Self.gradient(width: 90, height: 68))
        let a = try #require(SimilarPhotoScanner.dHash(original))
        let b = try #require(SimilarPhotoScanner.dHash(small))
        #expect((a ^ b).nonzeroBitCount <= 6)
    }

    @Test func keepsAtLeastOnePhotoAndSkipsChangedFiles() throws {
        let temp = try TempFolder()
        let a = try temp.file("a.jpg", size: 1000)
        let b = try temp.file("b.jpg", size: 1000)
        func scanned(_ url: URL) throws -> SimilarPhoto {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            return SimilarPhoto(url: url, size: 1000, pixelWidth: 10, pixelHeight: 10, modified: values.contentModificationDate, hash: 0)
        }
        let group = SimilarGroup(id: "g", photos: [try scanned(a), try scanned(b)])
        #expect(SimilarPhotoScanner.verifiedRemovals(in: group, selected: [a, b]).isEmpty)
        #expect(SimilarPhotoScanner.verifiedRemovals(in: group, selected: [b]).map(\.url) == [b])
        try Data(repeating: 1, count: 2000).write(to: b)
        #expect(SimilarPhotoScanner.verifiedRemovals(in: group, selected: [b]).isEmpty)
    }

    static func gradient(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for x in 0..<width {
            let shade = CGFloat((x * 7) % width) / CGFloat(width)
            context.setFillColor(red: shade, green: 1 - shade, blue: 0.5, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height / 2))
            context.setFillColor(red: 1 - shade, green: shade, blue: 0.2, alpha: 1)
            context.fill(CGRect(x: x, y: height / 2, width: 1, height: height - height / 2))
        }
        return context.makeImage()
    }
}

@Suite struct SecurityScanTests {
    @Test func findsStrayKeysExportsAndSecrets() throws {
        let temp = try TempFolder()
        try temp.file("Downloads/id_ed25519", contents: Data("-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n".utf8))
        try temp.file("Downloads/notes.key", contents: Data("just some keynote text".utf8))
        try temp.file("Desktop/Chrome Passwords.csv", contents: Data("name,url,username,password\n".utf8))
        try temp.file("Desktop/export.csv", contents: Data("url,username,password,note\n".utf8))
        try temp.file("Desktop/budget.csv", contents: Data("month,amount\n".utf8))
        try temp.file("Documents/old/.env", contents: Data("API_KEY=abc123\nDEBUG=1\n".utf8))
        try temp.file("Documents/app/.git/HEAD")
        try temp.file("Documents/app/.env", contents: Data("SECRET_TOKEN=xyz\n".utf8))
        try temp.file("Documents/blank/.env", contents: Data("API_KEY=\n".utf8))
        try temp.file("Downloads/gcp.json", contents: Data(#"{"type": "service_account", "private_key": "-----BEGIN"}"#.utf8))
        try temp.file("Downloads/cert.p12")
        try temp.file("Downloads/project/debug.keystore")
        try temp.file("Documents/db.sql", size: 900, daysOld: 400)
        try temp.file("Documents/fresh.sql", size: 900, daysOld: 3)
        try temp.file("Documents/app/db/schema.sql", size: 900, daysOld: 400)

        let findings = SecurityScanner(home: temp.url).scan { _ in }
        let byName = Dictionary(grouping: findings, by: \.name).mapValues { $0.map(\.kind) }
        #expect(byName["id_ed25519"] == [.privateKey])
        #expect(byName["notes.key"] == nil)
        #expect(byName["Chrome Passwords.csv"] == [.passwordExport])
        #expect(byName["export.csv"] == [.passwordExport])
        #expect(byName["budget.csv"] == nil)
        // Only the .env outside a Git repository, and only when a secret has a value.
        #expect(findings.filter { $0.kind == .envFile }.map { $0.url.deletingLastPathComponent().lastPathComponent } == ["old"])
        #expect(findings.first { $0.kind == .envFile }?.detail == "API_KEY")
        #expect(byName["gcp.json"] == [.cloudCredentials])
        #expect(byName["cert.p12"] == [.keyStore])
        #expect(byName["debug.keystore"] == nil)
        #expect(byName["db.sql"] == [.oldBackup])
        #expect(byName["fresh.sql"] == nil)
        // A project's own schema is source, not a backup.
        #expect(byName["schema.sql"] == nil)
    }

    @Test func flagsAndFixesReadableSSHKeys() throws {
        let temp = try TempFolder()
        let key = try temp.file(".ssh/id_rsa", contents: Data("-----BEGIN RSA PRIVATE KEY-----\n".utf8))
        let pub = try temp.file(".ssh/id_rsa.pub", contents: Data("ssh-rsa AAAA".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: key.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: pub.path)

        let scanner = SecurityScanner(home: temp.url)
        let findings = scanner.loosePermissions()
        #expect(findings.map(\.name) == ["id_rsa"])
        #expect(findings.first?.detail?.contains("644") == true)
        #expect(SecurityScanner.restrictPermissions(key))
        #expect(scanner.loosePermissions().isEmpty)
    }

    @Test func secretNamesNeedAValue() {
        let text = """
        # API_KEY=commented
        export GITHUB_TOKEN="ghp_123"
        DATABASE_URL=postgres://x
        EMPTY_PASSWORD=
        PORT=3000
        """
        #expect(SecurityScanner.secretNames(in: text) == ["GITHUB_TOKEN", "DATABASE_URL"])
    }
}
