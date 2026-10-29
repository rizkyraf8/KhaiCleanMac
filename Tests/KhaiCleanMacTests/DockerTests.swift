import Foundation
import Synchronization
import Testing
@testable import KhaiCleanMac

/// A stand-in for the docker CLI that records what it was asked to do. The real one is never run in tests.
private final class FakeDocker: Sendable {
    let calls = Mutex<[[String]]>([])
    let answer: @Sendable ([String]) -> (Int32, String)

    init(answer: @escaping @Sendable ([String]) -> (Int32, String)) {
        self.answer = answer
    }

    var runner: DockerCleaner.Runner {
        { _, arguments, _ in
            self.calls.withLock { $0.append(arguments) }
            return self.answer(arguments)
        }
    }

    var recorded: [[String]] { calls.withLock { $0 } }
}

@Suite struct DockerTests {
    private let binary = URL(filePath: "/usr/local/bin/docker")
    private let localContext = "desktop-linux\tunix:///Users/me/.docker/run/docker.sock"

    private let df = """
    {"Active":"2","Reclaimable":"1.234GB (40%)","Size":"3.1GB","TotalCount":"5","Type":"Images"}
    {"Active":"1","Reclaimable":"12.5MB (90%)","Size":"13MB","TotalCount":"3","Type":"Containers"}
    {"Active":"1","Reclaimable":"0B (0%)","Size":"2.5GB","TotalCount":"2","Type":"Local Volumes"}
    {"Active":"0","Reclaimable":"980.5kB","Size":"980.5kB","TotalCount":"7","Type":"Build Cache"}
    """

    private let ps = """
    {"CreatedAt":"2026-07-01 09:00:00 +0700 WIB","ID":"aaa111","Image":"postgres:16","Names":"postgres-dev","Status":"Exited (0) 2 days ago"}
    {"CreatedAt":"2026-10-28 09:00:00 +0700 WIB","ID":"bbb222","Image":"redis:7","Names":"redis-test","Status":"Created"}
    """

    private func engine(_ containers: [DockerContainer] = []) -> DockerEngine {
        DockerEngine(context: "desktop-linux", host: "unix:///Users/me/.docker/run/docker.sock",
                     usage: DockerUsage(), stoppedContainers: containers)
    }

    // MARK: Reading

    @Test func readsDiskUsageButLeavesVolumesOut() throws {
        let usage = try #require(DockerCleaner.parseUsage(df))
        #expect(usage.images == DockerUsage.Kind(size: 3_100_000_000, reclaimable: 1_234_000_000, count: 5))
        #expect(usage.containers.reclaimable == 12_500_000)
        #expect(usage.buildCache.reclaimable == 980_500)
        #expect(usage.volumes.size == 2_500_000_000)
        #expect(usage.reclaimable == 1_234_000_000 + 12_500_000 + 980_500, "Volumes are never cleaned")
    }

    @Test func readsDockerSizes() {
        #expect(DockerCleaner.size("0B") == 0)
        #expect(DockerCleaner.size("1.5GB") == 1_500_000_000)
        #expect(DockerCleaner.size("12MB (40%)") == 12_000_000)
        #expect(DockerCleaner.size(" 980.5kB") == 980_500)
        #expect(DockerCleaner.size("nonsense") == 0)
    }

    @Test func readsStoppedContainersWithTheirCreationDate() throws {
        let containers = DockerCleaner.parseContainers(ps)
        #expect(containers.map(\.name) == ["postgres-dev", "redis-test"])
        let created = try #require(containers[0].created)
        #expect(created == ISO8601DateFormatter().date(from: "2026-07-01T02:00:00Z"))
    }

    @Test func agesBecomeHoursInTheUntilFilter() {
        #expect(DockerAge.days7.untilFilter == "until=168h")
        #expect(DockerAge.days30.untilFilter == "until=720h")
        #expect(DockerAge.days60.untilFilter == "until=1440h")
    }

    // MARK: Only this Mac

    @Test func onlyEnginesOnThisMacCount() {
        #expect(DockerCleaner.isLocal("unix:///Users/me/.docker/run/docker.sock"))
        #expect(DockerCleaner.isLocal("unix:///Users/me/.orbstack/run/docker.sock"))
        #expect(DockerCleaner.isLocal("tcp://127.0.0.1:2375"))
        #expect(DockerCleaner.isLocal("tcp://localhost:2376"))
        #expect(!DockerCleaner.isLocal("ssh://deploy@prod.example.com"))
        #expect(!DockerCleaner.isLocal("tcp://10.0.0.5:2376"))
        #expect(!DockerCleaner.isLocal("tcp://localhost.example.com:2376"))
        #expect(!DockerCleaner.isLocal(""))
    }

    @Test func aRemoteContextIsRefusedBeforeAnythingElseRuns() {
        let fake = FakeDocker { arguments in
            arguments.first == "context" ? (0, "production\tssh://deploy@prod.example.com\n") : (0, df)
        }
        #expect(DockerCleaner.state(binary: binary, runner: fake.runner)
                == .notLocal(context: "production", host: "ssh://deploy@prod.example.com"))
        #expect(fake.recorded.count == 1, "Nothing is asked of a remote engine, not even its sizes")
    }

    @Test func anUnreadableContextIsRefusedToo() {
        let fake = FakeDocker { _ in (1, "unknown command") }
        #expect(DockerCleaner.state(binary: binary, runner: fake.runner) == .notLocal(context: "", host: ""))
    }

    @Test func everyCommandNamesTheCheckedContext() {
        let fake = FakeDocker { arguments in
            switch arguments.first {
            case "context": (0, localContext)
            default: arguments.contains("df") ? (0, df) : (0, ps)
            }
        }
        guard case .ready(let engine) = DockerCleaner.state(binary: binary, runner: fake.runner) else {
            Issue.record("Expected a local engine")
            return
        }
        #expect(engine.context == "desktop-linux")
        #expect(engine.stoppedContainers.count == 2)
        #expect(fake.recorded.dropFirst().allSatisfy { $0.prefix(2) == ["--context", "desktop-linux"] })
    }

    @Test func tellsInstalledStoppedAndStuckApart() {
        #expect(DockerCleaner.state(binary: nil) == .notInstalled)
        let stopped = FakeDocker { arguments in
            arguments.first == "context" ? (0, "default\tunix:///var/run/docker.sock") : (1, "Cannot connect to the Docker daemon")
        }
        #expect(DockerCleaner.state(binary: binary, runner: stopped.runner) == .notRunning)
        let stuck = FakeDocker { arguments in
            arguments.first == "context" ? (0, "default\tunix:///var/run/docker.sock") : (DockerCleaner.timedOutStatus, "")
        }
        #expect(DockerCleaner.state(binary: binary, runner: stuck.runner) == .timedOut)
    }

    // MARK: Pruning

    @Test func containersAreLeftAloneUnlessAskedFor() {
        let commands = DockerCleaner.pruneCommands(.days30, context: "desktop-linux", includeContainers: false)
        #expect(commands.map { $0.dropFirst(2).prefix(2).joined(separator: " ") } == ["image prune", "builder prune"])
        let withContainers = DockerCleaner.pruneCommands(.days30, context: "desktop-linux", includeContainers: true)
        #expect(withContainers.first?.dropFirst(2).prefix(2).joined(separator: " ") == "container prune", "Containers go first")
        #expect(withContainers.allSatisfy { $0.prefix(2) == ["--context", "desktop-linux"] && $0.contains("until=720h") })
        #expect(!withContainers.flatMap { $0 }.contains("volume") && !withContainers.flatMap { $0 }.contains("--volumes"))
    }

    @Test func addsUpWhatEachStepReclaimed() {
        let fake = FakeDocker { arguments in
            switch arguments[2] {
            case "container": (0, "Deleted Containers:\nabc\n\nTotal reclaimed space: 12.5MB\n")
            case "image": (0, "Deleted Images:\nsha256:1\n\nTotal reclaimed space: 1.2GB\n")
            default: (0, "ID\t\tRECLAIMABLE\tSIZE\nxyz\ttrue\t500MB\nTotal:\t500MB\n")
            }
        }
        let result = DockerCleaner.prune(.days7, engine: engine(), includeContainers: true, binary: binary, runner: fake.runner)
        #expect(result == DockerPruneResult(reclaimed: 12_500_000 + 1_200_000_000 + 500_000_000, failures: []))
    }

    @Test func aFailedOrStuckStepIsReportedAndTheRestStillRuns() {
        let fake = FakeDocker { arguments in
            switch arguments[2] {
            case "image": (1, "Error response from daemon: a prune operation is already running")
            case "builder": (DockerCleaner.timedOutStatus, "")
            default: (0, "Total reclaimed space: 1MB")
            }
        }
        let result = DockerCleaner.prune(.days30, engine: engine(), includeContainers: true, binary: binary, runner: fake.runner)
        #expect(result.reclaimed == 1_000_000)
        #expect(result.failures.count == 2)
        #expect(result.failures.first?.contains("already running") == true)
        #expect(fake.recorded.count == 3)
    }

    @Test func containersOlderThanTheAgeAreThoseCreatedBeforeIt() {
        let now = Date()
        let old = DockerContainer(id: "1", name: "old", image: "x", created: now.addingTimeInterval(-40 * 86_400))
        let new = DockerContainer(id: "2", name: "new", image: "x", created: now.addingTimeInterval(-2 * 86_400))
        let unknown = DockerContainer(id: "3", name: "unknown", image: "x", created: nil)
        let engine = engine([old, new, unknown])
        #expect(engine.containers(olderThan: .days30, now: now).map(\.name) == ["old"], "An unknown date never counts as old")
        #expect(engine.containers(olderThan: .days7, now: now).map(\.name) == ["old"])
    }

    @Test func eachCleanupLeavesOneHistoryLine() {
        let report = DeveloperModel.dockerHistory(DockerPruneResult(reclaimed: 2_000_000_000), engine: engine(), age: .days30,
                                                  containers: [DockerContainer(id: "1", name: "db", image: "x", created: nil)])
        #expect(report.permanent)
        #expect(report.removed.count == 1)
        #expect(report.removed.first?.trashedPath == nil, "Nothing can be restored from Docker")
        #expect(report.movedSize == 2_000_000_000)
        #expect(DeveloperModel.dockerHistory(DockerPruneResult(), engine: engine(), age: .days30, containers: []).removed.isEmpty,
                "A cleanup that freed nothing isn't logged")
    }

    // MARK: Finding the CLI

    @Test func findsTheCLIWhereverItWasInstalled() {
        let home = URL(filePath: "/Users/someone")
        #expect(DockerCleaner.binary(home: home) { $0 == "/Users/someone/.orbstack/bin/docker" }?.path == "/Users/someone/.orbstack/bin/docker")
        #expect(DockerCleaner.binary(home: home) { $0 == "/Applications/Docker.app/Contents/Resources/bin/docker" } != nil)
        #expect(DockerCleaner.binary(home: home) { _ in false } == nil)
    }

    /// The real runner, on a harmless system command: a command that outlives its timeout is stopped.
    @Test func aCommandThatHangsIsStopped() {
        let start = Date()
        let result = DockerCleaner.run(URL(filePath: "/bin/sleep"), ["30"], 1)
        #expect(result.status == DockerCleaner.timedOutStatus)
        #expect(Date().timeIntervalSince(start) < 10)
        let quick = DockerCleaner.run(URL(filePath: "/bin/echo"), ["hello"], 5)
        #expect(quick.status == 0 && quick.output == "hello\n")
    }
}
