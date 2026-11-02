import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct AIAnalysisTests {
    @Test func onlyPathsSizesAndDatesAreSent() throws {
        let item = CleanItem(url: URL.homeDirectory.appending(path: "Downloads/movie.mov"), size: 2_000_000_000)
        let inputs = AIAnalyst.inputs(Array(repeating: item, count: 14), context: "Large Files")
        #expect(inputs.count == AIAnalyst.maxItems)
        #expect(inputs.first?.path == "~/Downloads/movie.mov")

        let request = try AIAnalyst.request(AIAnalyst.prompt(inputs), apiKey: "test-key")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["fallbacks"] as? String == "default")
        let format = (body["output_config"] as? [String: Any])?["format"] as? [String: Any]
        #expect(format?["type"] as? String == "json_schema")
        let prompt = ((body["messages"] as? [[String: Any]])?.first?["content"] as? String) ?? ""
        #expect(!prompt.contains(URL.homeDirectory.path))
    }

    @Test func parsesAnswersAndDropsUnknownPaths() throws {
        let text = """
        Here you go:
        ```json
        {"items": [{"path": "~/a", "verdict": "safe", "reason": "Cache."},
                   {"path": "/etc/passwd", "verdict": "safe", "reason": "Invented."}]}
        ```
        """
        let verdicts = try AIAnalyst.parse(text, expected: ["~/a", "~/b"])
        #expect(verdicts.map(\.path) == ["~/a"])
        #expect(verdicts.first?.verdict == .safe)
        #expect(throws: AIAnalysisError.badAnswer) { try AIAnalyst.parse("no json", expected: []) }
    }

    @Test func refusalsAndErrorsAreReported() {
        let refusal = Data(#"{"stop_reason": "refusal", "content": []}"#.utf8)
        #expect(throws: AIAnalysisError.refused) { try AIAnalyst.text(fromMessage: refusal, status: 200) }
        let error = Data(#"{"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}}"#.utf8)
        #expect(throws: AIAnalysisError.failed("invalid x-api-key")) { try AIAnalyst.text(fromMessage: error, status: 401) }
        let ok = Data(#"{"stop_reason": "end_turn", "content": [{"type": "thinking", "thinking": ""}, {"type": "text", "text": "{\"items\": []}"}]}"#.utf8)
        #expect((try? AIAnalyst.text(fromMessage: ok, status: 200)) == #"{"items": []}"#)
    }

    @Test func providerIsOffByDefault() {
        #expect(AIProvider(rawValue: "") == nil)
        #expect(AIProvider.allCases.first == .off)
    }
}

@Suite struct ClaudeCLITests {
    @Test func findsClaudeInstalledThroughNvm() throws {
        let temp = try TempFolder()
        let old = temp.url.appending(path: ".nvm/versions/node/v18.20.0/bin/claude").path
        let new = temp.url.appending(path: ".nvm/versions/node/v22.11.0/bin/claude").path
        try temp.folder(".nvm/versions/node/v18.20.0/bin")
        try temp.folder(".nvm/versions/node/v22.11.0/bin")
        // The newest Node version wins; Homebrew's copy still comes first when there is one.
        #expect(AIAnalyst.claudeBinary(home: temp.url, exists: { $0 == old || $0 == new }) == new)
        #expect(AIAnalyst.claudeBinary(home: temp.url, exists: { $0 == "/opt/homebrew/bin/claude" || $0 == new }) == "/opt/homebrew/bin/claude")
        #expect(AIAnalyst.claudeBinary(home: temp.url, exists: { _ in false }) == nil)
    }

    @Test func aStoppedProcessEndsAsSoonAsItStarts() throws {
        let running = RunningProcess()
        running.stop()
        let started = Date()
        let output = StartupScanner.run("/bin/sleep", ["30"], timeout: 60, onStart: running.started)
        #expect(output == nil)
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func everyAppLanguageHasAnAnswerLanguage() {
        #expect(AppLanguage.japanese.englishName == "Japanese")
        #expect(Set(AppLanguage.allCases.map(\.englishName)).count == AppLanguage.allCases.count)
    }
}
