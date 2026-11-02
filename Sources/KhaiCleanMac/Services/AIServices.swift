import Foundation
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Who gives the optional second opinion. Off unless the user picks one in Settings.
enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case off, onDevice, claudeCLI, anthropicAPI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: L("Mati", "Off")
        case .onDevice: L("Apple, di perangkat", "Apple, on device")
        case .claudeCLI: "Claude CLI"
        case .anthropicAPI: "Anthropic API"
        }
    }

    var detail: String {
        switch self {
        case .off:
            L("Tidak ada yang dikirim ke mana pun.", "Nothing is sent anywhere.")
        case .onDevice:
            L("Apple Foundation Models, sepenuhnya di Mac ini. Butuh macOS 26 dan Apple Intelligence.", "Apple Foundation Models, entirely on this Mac. Needs macOS 26 and Apple Intelligence.")
        case .claudeCLI:
            L("Memakai perintah claude yang sudah terpasang dan akunnya.", "Uses the claude command you have installed, with its account.")
        case .anthropicAPI:
            L("Memakai kunci API Anthropic milikmu, disimpan di Keychain.", "Uses your own Anthropic API key, kept in your Keychain.")
        }
    }
}

/// What the AI thinks of one item.
struct AIVerdict: Identifiable, Hashable, Sendable, Decodable {
    enum Kind: String, Sendable, Decodable { case safe, check, keep }

    let path: String
    let verdict: Kind
    let reason: String

    var id: String { path }
}

enum AIAnalysisError: Error, Equatable {
    case notConfigured, unavailable, refused, badAnswer, failed(String)

    var message: String {
        switch self {
        case .notConfigured: L("Pilih penyedia AI di Settings › AI dulu.", "Pick an AI provider in Settings › AI first.")
        case .unavailable: L("Penyedia AI ini tidak tersedia di Mac ini.", "This AI provider isn't available on this Mac.")
        case .refused: L("AI menolak menjawab permintaan ini.", "The AI declined to answer this request.")
        case .badAnswer: L("Jawaban AI tidak bisa dibaca. Coba lagi.", "The AI's answer couldn't be read. Try again.")
        case .failed(let detail): L("Analisis gagal: \(detail)", "Analysis failed: \(detail)")
        }
    }
}

/// An optional second opinion on what's safe to remove. Only each item's path (with the home folder
/// written as ~), size and last use are sent, never file contents, and at most ten items at a time.
/// The answer is advice: it never selects or removes anything by itself.
enum AIAnalyst {
    static let maxItems = 10
    static let model = "claude-opus-5-5"

    struct Input: Sendable {
        let path: String
        let size: Int64
        let lastUsed: Date?
        let context: String
    }

    static func inputs(_ items: [CleanItem], lastUsed: [URL: Date] = [:], context: String) -> [Input] {
        items.prefix(maxItems).map { Input(path: $0.url.abbreviatedPath, size: $0.size, lastUsed: lastUsed[$0.url], context: context) }
    }

    static var instructions: String { """
        You help a Mac user decide what to clean up. For each path, answer with one verdict:
        "safe" when removing it can't lose anything the user would miss (caches, build output, installers, copies that can be downloaded again),
        "check" when it depends on what the user still needs,
        "keep" when it's likely personal data, an app's settings or documents, or something that is hard to get back.
        When unsure, prefer "check" or "keep". Give a short reason (one sentence, plain language, at most 20 words) in \(AppSettings.shared.language.englishName).
        Answer only with JSON: {"items": [{"path": "...", "verdict": "safe|check|keep", "reason": "..."}]}, one entry per path, paths exactly as given.
        """ }

    static func prompt(_ inputs: [Input]) -> String {
        let lines = inputs.map { input in
            let used = input.lastUsed.map { " · last used \($0.formatted(.iso8601.year().month().day()))" } ?? ""
            return "- \(input.path) · \(input.size.formattedBytes)\(used)"
        }
        return "Found by: \(inputs.first?.context ?? "a cleanup scan")\n" + lines.joined(separator: "\n")
    }

    static var schema: [String: Any] { [
        "type": "object",
        "properties": [
            "items": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string"],
                        "verdict": ["type": "string", "enum": ["safe", "check", "keep"]],
                        "reason": ["type": "string"],
                    ],
                    "required": ["path", "verdict", "reason"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["items"],
        "additionalProperties": false,
    ] }

    static func analyze(_ inputs: [Input], provider: AIProvider) async throws -> [AIVerdict] {
        guard !inputs.isEmpty else { return [] }
        let prompt = prompt(inputs)
        let text: String
        switch provider {
        case .off: throw AIAnalysisError.notConfigured
        case .onDevice: text = try await onDevice(prompt)
        case .claudeCLI: text = try await claudeCLI(prompt)
        case .anthropicAPI: text = try await anthropicAPI(prompt)
        }
        return try parse(text, expected: Set(inputs.map(\.path)))
    }

    /// Reads the JSON object out of the answer (a CLI may wrap it in prose or a code fence) and keeps
    /// only verdicts for paths that were asked about.
    static func parse(_ text: String, expected: Set<String>) throws -> [AIVerdict] {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { throw AIAnalysisError.badAnswer }
        struct Answer: Decodable { let items: [AIVerdict] }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: Data(text[start...end].utf8)) else { throw AIAnalysisError.badAnswer }
        return answer.items.filter { expected.contains($0.path) }
    }

    // MARK: Apple, on device

    static var isOnDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return SystemLanguageModel.default.availability == .available }
        #endif
        return false
    }

    private static func onDevice(_ prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            guard SystemLanguageModel.default.availability == .available else { throw AIAnalysisError.unavailable }
            let session = LanguageModelSession(instructions: instructions)
            do {
                return try await session.respond(to: prompt).content
            } catch {
                throw AIAnalysisError.failed(error.localizedDescription)
            }
        }
        #endif
        throw AIAnalysisError.unavailable
    }

    // MARK: Claude CLI

    /// The native installer's places, Homebrew, and the usual npm setups: a custom npm prefix,
    /// Volta, Bun, and each Node version nvm manages (newest first).
    static func claudeBinary(home: URL = .homeDirectory, exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        let nvm = ((try? FileManager.default.contentsOfDirectory(atPath: home.appending(path: ".nvm/versions/node").path)) ?? [])
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { home.appending(path: ".nvm/versions/node/\($0)/bin/claude").path }
        let candidates = [home.appending(path: ".claude/local/claude").path, home.appending(path: ".local/bin/claude").path,
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude", home.appending(path: ".npm-global/bin/claude").path,
                          home.appending(path: ".volta/bin/claude").path, home.appending(path: ".bun/bin/claude").path] + nvm
        return candidates.first(where: exists)
    }

    private static func claudeCLI(_ prompt: String) async throws -> String {
        guard let binary = claudeBinary() else { throw AIAnalysisError.unavailable }
        let full = instructions + "\n\n" + prompt
        // No tools: the CLI only answers from the text it's given.
        // An npm install is a `#!/usr/bin/env node` script, and an app's PATH has no Homebrew or npm folders.
        var environment = ProcessInfo.processInfo.environment
        let folders = [URL(filePath: binary).deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
        environment["PATH"] = (folders + [environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        // Closing the sheet cancels this task; the CLI is stopped then instead of running on for minutes.
        let running = RunningProcess()
        let output = await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) { [environment] in
                StartupScanner.run(binary, ["-p", full, "--output-format", "json", "--tools", ""], timeout: 180,
                                   environment: environment, onStart: running.started)
            }.value
        } onCancel: {
            running.stop()
        }
        try Task.checkCancellation()
        guard let output else { throw AIAnalysisError.failed(L("perintah claude tidak berhasil", "the claude command didn't succeed")) }
        // `--output-format json` wraps the answer as {"result": "..."}.
        if let data = output.data(using: .utf8),
           let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = wrapper["result"] as? String {
            return result
        }
        return output
    }

    // MARK: Anthropic API

    static func request(_ prompt: String, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        // On a safety decline the API retries on Anthropic's recommended fallback model by itself.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "system": instructions,
            // A short classification: low effort is plenty.
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "messages": [["role": "user", "content": prompt]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func anthropicAPI(_ prompt: String) async throws -> String {
        guard let key = APIKeyStore.read(), !key.isEmpty else { throw AIAnalysisError.notConfigured }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request(prompt, apiKey: key))
        } catch {
            throw AIAnalysisError.failed(error.localizedDescription)
        }
        return try text(fromMessage: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// The text of a Messages API response, after checking for errors and refusals.
    static func text(fromMessage data: Data, status: Int) throws -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            throw AIAnalysisError.failed(message)
        }
        if json["stop_reason"] as? String == "refusal" { throw AIAnalysisError.refused }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AIAnalysisError.badAnswer }
        return text
    }
}

/// A process that may be stopped from another thread, even before it has started.
final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isStopped = false

    func started(_ process: Process) {
        lock.withLock {
            self.process = process
            if isStopped { process.terminate() }
        }
    }

    func stop() {
        lock.withLock {
            isStopped = true
            process?.terminate()
        }
    }
}

/// The user's Anthropic API key, in the login Keychain. It never goes into preferences or logs.
enum APIKeyStore {
    private static var service: String { "\(AppInfo.bundleID).anthropic-api-key" }
    private static let account = "default"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static var hasKey: Bool { read()?.isEmpty == false }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
