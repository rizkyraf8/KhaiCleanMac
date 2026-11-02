import Foundation
import SwiftUI

/// A file that may hold secrets and sits somewhere it can leak from (a synced Desktop, a shared
/// Downloads folder, a backup), or a private key others on this Mac can read.
struct SecurityFinding: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case privateKey, passwordExport, envFile, cloudCredentials, keyStore, oldBackup, loosePermissions

        var title: String {
            switch self {
            case .privateKey: L("Private key", "Private keys")
            case .passwordExport: L("Ekspor kata sandi", "Exported passwords")
            case .envFile: L("File .env berisi rahasia", ".env files with secrets")
            case .cloudCredentials: L("Kredensial cloud", "Cloud credentials")
            case .keyStore: L("Keystore & sertifikat", "Keystores & certificates")
            case .oldBackup: L("Backup lama", "Old backups")
            case .loosePermissions: L("Kunci SSH yang bisa dibaca orang lain", "SSH keys others can read")
            }
        }

        var subtitle: String {
            switch self {
            case .privateKey:
                L("Kunci SSH, TLS, atau GPG di luar ~/.ssh. Siapa pun yang punya salinannya bisa masuk sebagai kamu.",
                  "SSH, TLS or GPG keys outside ~/.ssh. Anyone with a copy can sign in as you.")
            case .passwordExport:
                L("File CSV dari browser atau pengelola kata sandi. Isinya kata sandi tanpa enkripsi.",
                  "CSV files from a browser or password manager. They hold passwords without encryption.")
            case .envFile:
                L("File .env di luar repo Git dengan token, kunci API, atau kata sandi.",
                  ".env files outside a Git repository with tokens, API keys or passwords.")
            case .cloudCredentials:
                L("Kunci akun layanan Google Cloud, kredensial AWS, dan sejenisnya di luar folder alatnya.",
                  "Google Cloud service account keys, AWS credentials and the like outside their tool's folder.")
            case .keyStore:
                L("File .p12, .pfx, .jks, dan .keystore. Biasanya berisi private key, kadang tanpa kata sandi.",
                  ".p12, .pfx, .jks and .keystore files. They usually hold a private key, sometimes without a password.")
            case .oldBackup:
                L("File .bak, .old, dan dump database yang lama tidak dipakai. Bisa berisi data yang sudah kamu hapus di tempat lain.",
                  ".bak, .old and database dump files unused for a long time. They may hold data you deleted elsewhere.")
            case .loosePermissions:
                L("ssh menolak kunci yang bisa dibaca pengguna lain di Mac ini. Perbaiki izinnya supaya hanya kamu yang bisa membacanya.",
                  "ssh refuses keys other users on this Mac can read. Fix the permissions so only you can read them.")
            }
        }

        var symbol: String {
            switch self {
            case .privateKey: "key.fill"
            case .passwordExport: "tablecells.fill"
            case .envFile: "curlybraces"
            case .cloudCredentials: "cloud.fill"
            case .keyStore: "lock.doc.fill"
            case .oldBackup: "archivebox.fill"
            case .loosePermissions: "lock.open.fill"
            }
        }

        var colors: [Color] {
            switch self {
            case .privateKey: Palette.berry
            case .passwordExport: Palette.peach
            case .envFile: Palette.sunny
            case .cloudCredentials: Palette.sky
            case .keyStore: Palette.lavender
            case .oldBackup: Palette.slate
            case .loosePermissions: Palette.candy
            }
        }
    }

    let url: URL
    let kind: Kind
    let size: Int64
    let modified: Date?
    var detail: String?

    var id: String { kind.rawValue + url.path }
    var name: String { url.lastPathComponent }
}

/// Reads at most the first few KB of files whose name or extension already looks like a secret,
/// so file contents never leave this Mac and big files are never read.
struct SecurityScanner: Sendable {
    var home: URL = .homeDirectory
    /// Backups count as old after this.
    var backupAgeDays = 180

    private static let headLimit = 8 * 1024
    private static let keyExtensions: Set<String> = ["pem", "key", "ppk", "asc", "gpg"]
    private static let keyNames: Set<String> = ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", "id_ecdsa_sk", "id_ed25519_sk"]
    private static let keyStoreExtensions: Set<String> = ["p12", "pfx", "jks", "keystore", "kdb"]
    private static let backupExtensions: Set<String> = ["bak", "old", "backup", "sql", "dump"]
    /// Folders a tool keeps its own credentials in, where they belong.
    private static let toolFolders: Set<String> = [".ssh", ".aws", ".gnupg", ".config", ".kube", ".docker", ".azure", ".android"]
    /// Debug keystores every Android project makes, holding no real secret.
    private static let harmlessNames: Set<String> = ["debug.keystore"]

    var roots: [URL] {
        ["Desktop", "Documents", "Downloads"].map { home.appending(path: $0, directoryHint: .isDirectory) }
    }

    func scan(progress: @Sendable (Int) -> Void) -> [SecurityFinding] {
        var findings = loosePermissions()
        var visited = 0
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            enumerator.forEachURL { url in
                if Task.isCancelled { return false }
                visited += 1
                if visited % 1_500 == 0 { progress(visited) }
                let name = url.lastPathComponent
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isSymbolicLink != true else { return true }
                if values.isDirectory == true {
                    // Hidden folders (.git, caches), dependency folders and tool folders are skipped.
                    if (name.hasPrefix(".") && name != ".env") || DuplicateScanner.isProtected(url) || Self.toolFolders.contains(name) {
                        enumerator.skipDescendants()
                    }
                    return true
                }
                if let finding = check(url, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate) {
                    findings.append(finding)
                }
                return true
            }
        }
        progress(visited)
        return Task.isCancelled ? [] : findings.sorted { ($0.kind.rawValue, $0.url.path) < ($1.kind.rawValue, $1.url.path) }
    }

    /// What `url` is, when it looks like a secret. Exposed for tests.
    func check(_ url: URL, size: Int64, modified: Date?) -> SecurityFinding? {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        let ext = url.pathExtension.lowercased()
        guard !Self.harmlessNames.contains(lower) else { return nil }
        func finding(_ kind: SecurityFinding.Kind, _ detail: String? = nil) -> SecurityFinding {
            SecurityFinding(url: url, kind: kind, size: size, modified: modified, detail: detail)
        }

        if Self.keyNames.contains(lower) || Self.keyExtensions.contains(ext) {
            if let head = Self.head(url), head.contains("PRIVATE KEY-----") || head.contains("PRIVATE KEY BLOCK-----")
                || head.hasPrefix("PuTTY-User-Key-File") {
                return finding(.privateKey)
            }
            return nil
        }
        if Self.keyStoreExtensions.contains(ext) { return finding(.keyStore) }
        if ext == "csv", lower.contains("password") || lower.contains("passwort") || lower.contains("kata sandi")
            || (Self.head(url).map(Self.looksLikePasswordExport) ?? false) {
            return finding(.passwordExport)
        }
        if lower == ".env" || lower.hasPrefix(".env.") || ext == "env" {
            guard !lower.hasSuffix(".example"), !lower.hasSuffix(".sample"), !lower.hasSuffix(".template"),
                  !isInsideRepository(url), let head = Self.head(url) else { return nil }
            let secrets = Self.secretNames(in: head)
            return secrets.isEmpty ? nil : finding(.envFile, secrets.prefix(3).joined(separator: ", "))
        }
        if ext == "json", size < 64 * 1024, let head = Self.head(url),
           head.contains("\"private_key\""), head.contains("\"service_account\"") {
            return finding(.cloudCredentials, L("Kunci akun layanan Google Cloud", "Google Cloud service account key"))
        }
        if lower == "credentials" || lower == "credentials.csv" || lower.hasSuffix("_accesskeys.csv"),
           let head = Self.head(url), head.contains("aws_secret_access_key") || head.lowercased().contains("secret access key") {
            return finding(.cloudCredentials, L("Kunci akses AWS", "AWS access key"))
        }
        if Self.backupExtensions.contains(ext) || lower.hasSuffix(".sql.gz") {
            let cutoff = Date().addingTimeInterval(-Double(backupAgeDays) * 24 * 60 * 60)
            // Inside a project, .sql files are usually its schema or migrations, part of its source.
            guard (modified ?? .distantFuture) < cutoff, size > 0, !isInsideRepository(url) else { return nil }
            return finding(.oldBackup)
        }
        return nil
    }

    /// Private keys in ~/.ssh that the group or others can read. ssh refuses such keys.
    func loosePermissions() -> [SecurityFinding] {
        let ssh = home.appending(path: ".ssh")
        let urls = (try? FileManager.default.contentsOfDirectory(at: ssh, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in
            guard !url.lastPathComponent.hasSuffix(".pub"),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
                  permissions & 0o077 != 0,
                  let head = Self.head(url), head.contains("PRIVATE KEY-----") else { return nil }
            return SecurityFinding(url: url, kind: .loosePermissions, size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                                   modified: attributes[.modificationDate] as? Date,
                                   detail: L("Izin sekarang \(String(permissions & 0o777, radix: 8)), seharusnya 600",
                                             "Permissions are \(String(permissions & 0o777, radix: 8)), should be 600"))
        }
    }

    /// Owner read and write only, as `chmod 600` does.
    static func restrictPermissions(_ url: URL) -> Bool {
        (try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)) != nil
    }

    /// A .env next to a `.git` folder (in it or above it) belongs to a project, where it's expected.
    private func isInsideRepository(_ url: URL) -> Bool {
        var folder = url.deletingLastPathComponent()
        let stop = home.standardizedFileURL.path
        while folder.standardizedFileURL.path.count > stop.count {
            if FileManager.default.fileExists(atPath: folder.appending(path: ".git").path) { return true }
            folder = folder.deletingLastPathComponent()
        }
        return false
    }

    static func head(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headLimit) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func looksLikePasswordExport(_ head: String) -> Bool {
        let header = head.split(whereSeparator: \.isNewline).first?.lowercased() ?? ""
        let columns = Set(header.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) })
        return columns.contains("password") && (columns.contains("username") || columns.contains("login") || columns.contains("url"))
    }

    /// Variable names that hold a non-empty value and are named like a secret.
    static func secretNames(in text: String) -> [String] {
        let markers = ["SECRET", "TOKEN", "PASSWORD", "PASSWD", "API_KEY", "APIKEY", "PRIVATE_KEY", "ACCESS_KEY", "CLIENT_SECRET", "DATABASE_URL"]
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { return nil }
            let name = line[..<equals].replacingOccurrences(of: "export ", with: "").trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            guard !value.isEmpty, markers.contains(where: { name.uppercased().contains($0) }) else { return nil }
            return name
        }
    }
}
