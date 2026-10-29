import Foundation
import Synchronization

/// How long ago something must have been created before Docker cleanup takes it. Docker keeps no
/// "last used" date, so this is the creation date: an old image pulled yesterday is still "old".
enum DockerAge: Int, CaseIterable, Identifiable, Sendable {
    case days7 = 7, days30 = 30, days60 = 60

    var id: Int { rawValue }
    var label: String { L("\(rawValue) hari", "\(rawValue) days") }
    /// Docker's `until` filter takes a Go duration; it has no unit for days.
    var untilFilter: String { "until=\(rawValue * 24)h" }

    func cutoff(from now: Date = Date()) -> Date {
        now.addingTimeInterval(-Double(rawValue) * 24 * 60 * 60)
    }
}

/// What `docker system df` reports, per kind of data.
struct DockerUsage: Equatable, Sendable {
    struct Kind: Equatable, Sendable {
        var size: Int64 = 0
        var reclaimable: Int64 = 0
        var count = 0
    }

    var images = Kind()
    var containers = Kind()
    var buildCache = Kind()
    var volumes = Kind()

    /// Volumes hold data (databases and the like) and are never cleaned, so they don't count.
    var reclaimable: Int64 { images.reclaimable + containers.reclaimable + buildCache.reclaimable }
}

/// A container that isn't running. Its own files (anything not in a volume) go with it.
struct DockerContainer: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let image: String
    let created: Date?
}

/// The engine on this Mac that cleanup talks to, pinned by its context name.
struct DockerEngine: Equatable, Sendable {
    let context: String
    let host: String
    let usage: DockerUsage
    let stoppedContainers: [DockerContainer]

    /// Stopped containers created before the cutoff: exactly what `container prune --filter until=` removes.
    func containers(olderThan age: DockerAge, now: Date = Date()) -> [DockerContainer] {
        stoppedContainers.filter { ($0.created ?? .distantFuture) < age.cutoff(from: now) }
    }
}

enum DockerState: Equatable, Sendable {
    case notInstalled
    /// The CLI is there, but no engine answers (Docker Desktop, OrbStack or Colima isn't running).
    case notRunning
    /// The engine didn't answer in time.
    case timedOut
    /// The active context points somewhere other than this Mac (a server over SSH or TCP), or it
    /// couldn't be read. Cleanup never runs there.
    case notLocal(context: String, host: String)
    case ready(DockerEngine)
}

struct DockerPruneResult: Equatable, Sendable {
    var reclaimed: Int64 = 0
    /// The prune steps that failed, with Docker's own message.
    var failures: [String] = []
}

/// Cleans Docker through Docker itself. Its data lives in a disk image only the engine understands,
/// so files are never touched directly, and what it removes is gone for good (it has no Trash).
enum DockerCleaner {
    typealias Runner = @Sendable (_ binary: URL, _ arguments: [String], _ timeout: TimeInterval) -> (status: Int32, output: String)

    /// The status `run` returns when a command was stopped for taking too long.
    static let timedOutStatus: Int32 = -2
    /// Reading sizes is quick unless the engine is stuck; pruning a big cache can take minutes.
    static let checkTimeout: TimeInterval = 60
    static let pruneTimeout: TimeInterval = 10 * 60

    /// Docker Desktop, Homebrew, OrbStack and Rancher Desktop put the CLI in one of these.
    static func binary(home: URL = .homeDirectory, exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> URL? {
        let candidates = [
            "/usr/local/bin/docker", "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            home.appending(path: ".docker/bin/docker").path,
            home.appending(path: ".orbstack/bin/docker").path,
            home.appending(path: ".rd/bin/docker").path,
        ]
        return candidates.first(where: exists).map { URL(filePath: $0) }
    }

    /// Checks that the active context is this Mac before reading anything, then reads sizes and the
    /// stopped containers through that context, so a context switch later can't redirect cleanup.
    static func state(binary: URL?, runner: Runner = run) -> DockerState {
        guard let binary else { return .notInstalled }
        let context = runner(binary, ["context", "inspect", "--format", "{{.Name}}\t{{.Endpoints.docker.Host}}"], checkTimeout)
        if context.status == timedOutStatus { return .timedOut }
        guard context.status == 0, let (name, host) = parseContext(context.output) else { return .notLocal(context: "", host: "") }
        guard isLocal(host) else { return .notLocal(context: name, host: host) }

        let df = runner(binary, ["--context", name, "system", "df", "--format", "{{json .}}"], checkTimeout)
        if df.status == timedOutStatus { return .timedOut }
        guard df.status == 0, let usage = parseUsage(df.output) else { return .notRunning }

        let ps = runner(binary, ["--context", name, "ps", "--all", "--no-trunc",
                                 "--filter", "status=exited", "--filter", "status=created", "--filter", "status=dead",
                                 "--format", "{{json .}}"], checkTimeout)
        let stopped = ps.status == 0 ? parseContainers(ps.output) : []
        return .ready(DockerEngine(context: name, host: host, usage: usage, stoppedContainers: stopped))
    }

    /// A Unix socket on this Mac (Docker Desktop, OrbStack, Colima, Rancher Desktop) or a TCP port on
    /// localhost. Anything else (ssh://, a remote tcp:// host) is another machine.
    static func isLocal(_ host: String) -> Bool {
        if host.hasPrefix("unix://") { return true }
        guard host.hasPrefix("tcp://"), let url = URL(string: host), let name = url.host() else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(name)
    }

    /// Images (now unused) and build cache, plus stopped containers only when asked for: a container's
    /// own files can hold data that isn't in a volume. Running containers, the images they use and
    /// volumes are never removed by these commands.
    static func pruneCommands(_ age: DockerAge, context: String, includeContainers: Bool) -> [[String]] {
        var commands: [[String]] = []
        // Containers first, so the images they held become unused and go in the same run.
        if includeContainers {
            commands.append(["container", "prune", "--force", "--filter", age.untilFilter])
        }
        commands.append(["image", "prune", "--all", "--force", "--filter", age.untilFilter])
        commands.append(["builder", "prune", "--force", "--filter", age.untilFilter])
        return commands.map { ["--context", context] + $0 }
    }

    static func prune(_ age: DockerAge, engine: DockerEngine, includeContainers: Bool, binary: URL, runner: Runner = run) -> DockerPruneResult {
        var result = DockerPruneResult()
        for arguments in pruneCommands(age, context: engine.context, includeContainers: includeContainers) {
            let step = "docker " + arguments.dropFirst(2).prefix(2).joined(separator: " ")
            let output = runner(binary, arguments, pruneTimeout)
            if output.status == 0 {
                result.reclaimed += reclaimedSpace(in: output.output)
            } else if output.status == timedOutStatus {
                result.failures.append("\(step): " + L("waktu habis", "timed out"))
            } else {
                let message = output.output.split(separator: "\n").last.map(String.init) ?? ""
                result.failures.append("\(step): \(message)")
            }
        }
        return result
    }

    // MARK: Parsing

    /// `{{.Name}}<tab>{{.Endpoints.docker.Host}}`, e.g. "desktop-linux\tunix:///Users/me/.docker/run/docker.sock".
    static func parseContext(_ output: String) -> (name: String, host: String)? {
        let line = output.split(separator: "\n").first.map(String.init) ?? ""
        let parts = line.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    /// One JSON object per line, e.g. `{"Type":"Images","TotalCount":"5","Size":"3.1GB","Reclaimable":"1.2GB (38%)"}`.
    static func parseUsage(_ output: String) -> DockerUsage? {
        var usage = DockerUsage()
        var found = false
        for row in jsonLines(output) {
            guard let type = row["Type"] as? String else { continue }
            let kind = DockerUsage.Kind(
                size: size(row["Size"] as? String ?? ""),
                reclaimable: size(row["Reclaimable"] as? String ?? ""),
                count: Int(row["TotalCount"] as? String ?? "") ?? (row["TotalCount"] as? Int ?? 0)
            )
            switch type {
            case "Images": usage.images = kind
            case "Containers": usage.containers = kind
            case "Build Cache": usage.buildCache = kind
            case "Local Volumes": usage.volumes = kind
            default: continue
            }
            found = true
        }
        return found ? usage : nil
    }

    /// `docker ps --format '{{json .}}'` rows; CreatedAt looks like "2026-09-01 10:20:30 +0700 WIB".
    static func parseContainers(_ output: String) -> [DockerContainer] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return jsonLines(output).compactMap { row in
            guard let id = row["ID"] as? String else { return nil }
            let created = (row["CreatedAt"] as? String).flatMap { text in
                formatter.date(from: text.split(separator: " ").prefix(3).joined(separator: " "))
            }
            return DockerContainer(id: id, name: row["Names"] as? String ?? String(id.prefix(12)),
                                   image: row["Image"] as? String ?? "", created: created)
        }
    }

    private static func jsonLines(_ output: String) -> [[String: Any]] {
        output.split(separator: "\n").compactMap { line in
            line.data(using: .utf8).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        }
    }

    /// Prune commands end with "Total reclaimed space: 1.2GB"; `builder prune` says "Total:\t1.2GB".
    static func reclaimedSpace(in output: String) -> Int64 {
        output.split(separator: "\n").reduce(0) { total, line in
            let text = line.trimmingCharacters(in: .whitespaces)
            for prefix in ["Total reclaimed space:", "Total:"] where text.hasPrefix(prefix) {
                return total + size(String(text.dropFirst(prefix.count)))
            }
            return total
        }
    }

    /// Docker writes sizes like "1.234GB", "980.5kB", "12MB (40%)" or "0B", in powers of 1000.
    static func size(_ text: String) -> Int64 {
        let value = text.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (unit, factor) in units where value.hasSuffix(unit) {
            guard let number = Double(value.dropLast(unit.count)) else { return 0 }
            return Int64((number * factor).rounded())
        }
        return 0
    }

    // MARK: Running

    /// Runs the CLI with its own folder on PATH, so Docker Desktop finds its helpers, and returns its
    /// exit status with stdout and stderr together. DOCKER_HOST and DOCKER_CONTEXT are dropped: the
    /// context checked as local is always passed explicitly. A command that outlives `timeout` is
    /// stopped and reported as `timedOutStatus`.
    static let run: Runner = { binary, arguments, timeout in
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["DOCKER_HOST"] = nil
        environment["DOCKER_CONTEXT"] = nil
        let folders = [binary.deletingLastPathComponent().path, "/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
        environment["PATH"] = (folders + [environment["PATH"] ?? ""]).joined(separator: ":")
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        // Read while it runs, so a chatty command can't block on a full pipe.
        let collected = Mutex(Data())
        let readDone = DispatchSemaphore(value: 0)
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async {
            let data = handle.readDataToEndOfFile()
            collected.withLock { $0 = data }
            readDone.signal()
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 5)
            _ = readDone.wait(timeout: .now() + 5)
            return (timedOutStatus, "timed out after \(Int(timeout)) seconds")
        }
        _ = readDone.wait(timeout: .now() + 5)
        return (process.terminationStatus, collected.withLock { String(decoding: $0, as: UTF8.self) })
    }
}
