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
    /// Everything cleanup can shrink, to measure what a cleanup freed.
    var total: Int64 { images.size + containers.size + buildCache.size }
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

    /// Stopped containers created before the cutoff. Cleanup removes exactly these, by ID, and nothing
    /// that wasn't listed: a container with an unknown creation date never counts as old.
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
    static func state(binary: URL?, home: URL = .homeDirectory, runner: Runner = run) -> DockerState {
        guard let binary else { return .notInstalled }
        let context = runner(binary, ["context", "inspect", "--format", "{{.Name}}\t{{.Endpoints.docker.Host}}"], checkTimeout)
        if context.status == timedOutStatus { return .timedOut }
        guard context.status == 0, let (name, host) = parseContext(context.output) else { return .notLocal(context: "", host: "") }
        guard isLocal(host, home: home) else { return .notLocal(context: name, host: host) }

        let df = runner(binary, ["--context", name, "system", "df", "--format", "{{json .}}"], checkTimeout)
        if df.status == timedOutStatus { return .timedOut }
        guard df.status == 0, let usage = parseUsage(df.output) else { return .notRunning }

        let ps = runner(binary, ["--context", name, "ps", "--all", "--no-trunc",
                                 "--filter", "status=exited", "--filter", "status=created", "--filter", "status=dead",
                                 "--format", "{{json .}}"], checkTimeout)
        let stopped = ps.status == 0 ? parseContainers(ps.output) : []
        return .ready(DockerEngine(context: name, host: host, usage: usage, stoppedContainers: stopped))
    }

    /// The socket of an engine running on this Mac: Docker Desktop, OrbStack, Colima, Lima or Rancher Desktop,
    /// checked as written and with symlinks resolved. Any other socket may be a tunnel to a server
    /// (`ssh -L ~/prod.sock:/var/run/docker.sock`), and so may a TCP port on localhost, so neither counts.
    static func isLocal(_ host: String, home: URL = .homeDirectory) -> Bool {
        guard host.hasPrefix("unix://") else { return false }
        let path = String(host.dropFirst("unix://".count))
        guard path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return false }
        let resolved = URL(filePath: path).resolvingSymlinksInPath().path
        return isKnownSocket(path, home: home) && isKnownSocket(resolved, home: home)
    }

    private static func isKnownSocket(_ path: String, home: URL) -> Bool {
        let homePath = home.path
        let exact = ["/var/run/docker.sock", "/private/var/run/docker.sock"] + [
            ".docker/run/docker.sock", ".docker/desktop/docker.sock", ".orbstack/run/docker.sock", ".rd/docker.sock",
        ].map { "\(homePath)/\($0)" }
        if exact.contains(path) { return true }
        // ~/.colima/<profile>/docker.sock and ~/.lima/<instance>/sock/docker.sock
        let parts = path.split(separator: "/").map(String.init)
        let homeParts = home.pathComponents.dropFirst().map { $0 }
        guard parts.count > homeParts.count, Array(parts.prefix(homeParts.count)) == homeParts else { return false }
        let rest = Array(parts.dropFirst(homeParts.count))
        return (rest.count == 3 && rest[0] == ".colima" && rest[2] == "docker.sock")
            || (rest.count == 4 && rest[0] == ".lima" && rest[2] == "sock" && rest[3] == "docker.sock")
    }

    /// Dangling images and build cache, plus the stopped containers the user confirmed, by ID. Volumes,
    /// running containers and the images any container uses are never removed by these commands.
    static func pruneCommands(_ age: DockerAge, context: String, containers: [DockerContainer]) -> [[String]] {
        var commands: [[String]] = []
        // Containers first, so the images they held become unused and go in the same run. Without
        // --force, Docker refuses a container that was started again since it was listed.
        if !containers.isEmpty {
            commands.append(["container", "rm"] + containers.map(\.id))
        }
        // Untagged leftovers only: tagged images are removed one by one, see `pullableImages`.
        commands.append(["image", "prune", "--force", "--filter", age.untilFilter])
        commands.append(["builder", "prune", "--force", "--filter", age.untilFilter])
        return commands.map { ["--context", context] + $0 }
    }

    static func prune(_ age: DockerAge, engine: DockerEngine, containers: [DockerContainer], binary: URL,
                      now: Date = Date(), home: URL = .homeDirectory, runner: Runner = run) -> DockerPruneResult {
        var result = DockerPruneResult()
        let context = engine.context
        // The engine was checked when the card was shown, maybe hours ago: the context could point
        // somewhere else by now, so nothing runs unless it is still the same engine on this Mac.
        let current = runner(binary, ["context", "inspect", context, "--format", "{{.Name}}\t{{.Endpoints.docker.Host}}"], checkTimeout)
        guard current.status == 0, let found = parseContext(current.output), found.host == engine.host, isLocal(found.host, home: home) else {
            result.failures.append("docker context: " + L("engine sudah berubah sejak dicek, tidak ada yang dihapus",
                                                         "the engine changed since it was checked, nothing was removed"))
            return result
        }
        let before = usage(context: context, binary: binary, runner: runner)

        var commands = pruneCommands(age, context: context, containers: containers)
        let images = pullableImages(olderThan: age.cutoff(from: now), context: context, binary: binary, runner: runner)
        if !images.isEmpty {
            // After the containers, before the build cache. No --force: an image a container uses is refused.
            commands.insert(["--context", context, "image", "rm"] + images, at: commands.count - 1)
        }
        var parsed: Int64 = 0
        for arguments in commands {
            let step = "docker " + arguments.dropFirst(2).prefix(2).joined(separator: " ")
            let output = runner(binary, arguments, pruneTimeout)
            if output.status == 0 {
                parsed += reclaimedSpace(in: output.output)
            } else if output.status == timedOutStatus {
                result.failures.append("\(step): " + L("waktu habis", "timed out"))
            } else if let message = unexpectedError(in: output.output) {
                result.failures.append("\(step): \(message)")
            }
        }
        // `image rm` and `container rm` don't say how much they freed, so compare the totals.
        if let before, let after = usage(context: context, binary: binary, runner: runner) {
            result.reclaimed = max(0, before.total - after.total)
        } else {
            result.reclaimed = parsed
        }
        return result
    }

    private static func usage(context: String, binary: URL, runner: Runner) -> DockerUsage? {
        let df = runner(binary, ["--context", context, "system", "df", "--format", "{{json .}}"], checkTimeout)
        return df.status == 0 ? parseUsage(df.output) : nil
    }

    /// Tagged images created before the cutoff that came from a registry (they have a repo digest), as
    /// "repo:tag". Images built, committed or loaded on this Mac have none and can't be pulled again,
    /// so they are never offered.
    static func pullableImages(olderThan cutoff: Date, context: String, binary: URL, runner: Runner) -> [String] {
        let list = runner(binary, ["--context", context, "image", "ls", "--no-trunc", "--format", "{{json .}}"], checkTimeout)
        guard list.status == 0 else { return [] }
        let old = parseImages(list.output).filter { image in
            image.repository != "<none>" && image.tag != "<none>" && (image.created ?? .distantFuture) < cutoff
        }
        let ids = Array(Set(old.map(\.id))).sorted()
        guard !ids.isEmpty else { return [] }
        let inspect = runner(binary, ["--context", context, "image", "inspect", "--format", "{{.Id}}\t{{len .RepoDigests}}"] + ids, checkTimeout)
        guard inspect.status == 0 else { return [] }
        let pullable = Set(inspect.output.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.count == 2 && (Int(parts[1]) ?? 0) > 0 ? parts[0] : nil
        })
        return old.filter { pullable.contains($0.id) }.map { "\($0.repository):\($0.tag)" }
    }

    /// The last error Docker printed, leaving out "in use" refusals: those are the safety net working.
    static func unexpectedError(in output: String) -> String? {
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        let errors = lines.filter { $0.localizedCaseInsensitiveContains("error") }
        if !errors.isEmpty, errors.allSatisfy({ $0.contains("conflict") || $0.contains("is running") || $0.contains("is being used") }) {
            return nil
        }
        return errors.last ?? lines.last ?? ""
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
        jsonLines(output).compactMap { row in
            guard let id = row["ID"] as? String else { return nil }
            return DockerContainer(id: id, name: row["Names"] as? String ?? String(id.prefix(12)),
                                   image: row["Image"] as? String ?? "", created: date(row["CreatedAt"]))
        }
    }

    struct Image: Equatable, Sendable {
        let id: String
        let repository: String
        let tag: String
        let created: Date?
    }

    /// `docker image ls --no-trunc --format '{{json .}}'` rows, dated like containers.
    static func parseImages(_ output: String) -> [Image] {
        jsonLines(output).compactMap { row in
            guard let id = row["ID"] as? String else { return nil }
            return Image(id: id, repository: row["Repository"] as? String ?? "<none>", tag: row["Tag"] as? String ?? "<none>",
                         created: date(row["CreatedAt"]))
        }
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: text.split(separator: " ").prefix(3).joined(separator: " "))
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
        // `builder prune` goes to buildx's selected builder, which may be a remote or cloud one whatever
        // --context says. Each context has a builder of its own name on that engine: use it.
        environment["BUILDX_BUILDER"] = arguments.first == "--context" && arguments.count > 1 ? arguments[1] : nil
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
