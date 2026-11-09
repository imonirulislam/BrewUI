@testable import BrewAssistantCloud
import BrewAssistantCore
import BrewCore
import Foundation
import Testing

struct AnthropicProviderTests {
    @Test func `requests carry the key, API version, fallback beta and a JSON schema`() async throws {
        let transport = StubTransport(body: Self.message(text: #"{"terms":["ffmpeg"]}"#))
        let model = try AnthropicPackageSuggestionModel(apiKey: "sk-test", model: "claude-opus-5-5", baseURL: Self.base(), transport: transport)

        _ = try await model.searchTerms(for: "convert videos")

        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let body = try Self.json(request)
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["fallbacks"] as? String == "default")
        let output = try #require(body["output_config"] as? [String: Any])
        #expect(output["effort"] as? String == "low")
        #expect((output["format"] as? [String: Any])?["type"] as? String == "json_schema")
    }

    @Test func `the JSON answer is read from the text block, skipping thinking`() async throws {
        let transport = StubTransport(body: Self.message(text: #"{"picks":[{"name":"ffmpeg","reason":"Converts video"}]}"#))
        let model = try AnthropicPackageSuggestionModel(apiKey: "k", model: "m", baseURL: Self.base(), transport: transport)

        let picks = try await model.choose(for: "convert videos", from: [])

        #expect(picks == [ModelPick(name: "ffmpeg", reason: "Converts video")])
    }

    @Test func `a refusal is reported before content is read`() async throws {
        let transport = StubTransport(body: #"{"content":[],"stop_reason":"refusal"}"#)
        let model = try AnthropicPackageSuggestionModel(apiKey: "k", model: "m", baseURL: Self.base(), transport: transport)

        await #expect(throws: AssistantError.refusal) {
            try await model.searchTerms(for: "x")
        }
    }

    @Test(arguments: [(401, AssistantError.unauthorized), (403, .unauthorized), (429, .rateLimited)])
    func `HTTP failures map to assistant errors`(status: Int, expected: AssistantError) async throws {
        let transport = StubTransport(status: status, body: #"{"error":{"message":"nope"}}"#)
        let model = try AnthropicPackageSuggestionModel(apiKey: "k", model: "m", baseURL: Self.base(), transport: transport)

        await #expect(throws: expected) {
            try await model.searchTerms(for: "x")
        }
    }

    @Test func `other HTTP failures keep the server's message`() async throws {
        let transport = StubTransport(status: 529, body: #"{"error":{"message":"Overloaded"}}"#)
        let model = try AnthropicPackageSuggestionModel(apiKey: "k", model: "m", baseURL: Self.base(), transport: transport)

        await #expect(throws: AssistantError.generationFailed("Claude returned HTTP 529: Overloaded")) {
            try await model.searchTerms(for: "x")
        }
    }

    @Test func `a missing key needs configuration and sends nothing`() async throws {
        let transport = StubTransport(body: "{}")
        let model = try AnthropicPackageSuggestionModel(apiKey: "", model: "m", baseURL: Self.base(), transport: transport)

        #expect(model.availability == .needsConfiguration)
        await #expect(throws: AssistantError.unavailable(.needsConfiguration)) {
            try await model.searchTerms(for: "x")
        }
        #expect(await transport.requests.isEmpty)
    }

    static func base() throws -> URL {
        try testURL("https://api.anthropic.com/v1")
    }

    static func message(text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"\#(escaped)"}],"stop_reason":"end_turn"}"#
    }

    static func json(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

struct OpenAICompatibleProviderTests {
    @Test func `requests go to chat completions with a strict schema and bearer key`() async throws {
        let transport = StubTransport(body: Self.completion(content: #"{"terms":["ffmpeg"]}"#))
        let model = try OpenAICompatiblePackageSuggestionModel(
            apiKey: "sk-openai", model: "some-model", baseURL: testURL("https://api.openai.com/v1"),
            providerName: "OpenAI", transport: transport,
        )

        #expect(try await model.searchTerms(for: "convert videos") == ["ffmpeg"])

        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-openai")
        let body = try AnthropicProviderTests.json(request)
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect((format["json_schema"] as? [String: Any])?["strict"] as? Bool == true)
    }

    @Test func `local servers are called without an authorization header`() async throws {
        let transport = StubTransport(body: Self.completion(content: #"{"terms":[]}"#))
        let model = try OpenAICompatiblePackageSuggestionModel(
            apiKey: nil, model: "llama3.2", baseURL: testURL("http://localhost:11434/v1"),
            providerName: "localhost", transport: transport,
        )

        _ = try await model.searchTerms(for: "x")

        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
    }

    @Test func `a refusal message is reported`() async throws {
        let transport = StubTransport(body: #"{"choices":[{"message":{"content":null,"refusal":"No"},"finish_reason":"stop"}]}"#)
        let model = try OpenAICompatiblePackageSuggestionModel(
            apiKey: nil, model: "m", baseURL: testURL("http://localhost:1/v1"), providerName: "local", transport: transport,
        )

        await #expect(throws: AssistantError.refusal) {
            try await model.searchTerms(for: "x")
        }
    }

    @Test func `an answer that is not the schema is an error, not a guess`() async throws {
        let transport = StubTransport(body: Self.completion(content: "Sure! Try ffmpeg."))
        let model = try OpenAICompatiblePackageSuggestionModel(
            apiKey: nil, model: "m", baseURL: testURL("http://localhost:1/v1"), providerName: "local", transport: transport,
        )

        await #expect(throws: AssistantError.generationFailed("local returned an answer that was not the expected JSON")) {
            try await model.searchTerms(for: "x")
        }
    }

    static func completion(content: String) -> String {
        let escaped = content.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"choices":[{"message":{"content":"\#(escaped)"},"finish_reason":"stop"}]}"#
    }
}

struct AssistantSettingsTests {
    @Test func `on-device is the default and needs nothing`() throws {
        let settings = try AssistantSettings(defaults: Self.freshSuite().defaults)

        #expect(settings.provider == .onDevice)
        #expect(settings.isConfigured(apiKey: nil))
    }

    @Test func `the Claude provider defaults its model but needs a key`() {
        let settings = AssistantSettings(provider: .anthropic)

        #expect(settings.effectiveModel == "claude-opus-5-5")
        #expect(!settings.isConfigured(apiKey: nil))
        #expect(settings.isConfigured(apiKey: "sk-ant"))
    }

    @Test func `the OpenAI provider needs a model as well as a key`() {
        #expect(!AssistantSettings(provider: .openAI).isConfigured(apiKey: "sk"))
        #expect(AssistantSettings(provider: .openAI, model: "some-model").isConfigured(apiKey: "sk"))
    }

    @Test(arguments: ["", "localhost:11434", "ftp://host/v1", "not a url"])
    func `compatible servers need an http or https address`(address: String) {
        #expect(!AssistantSettings(provider: .openAICompatible, model: "m", baseURL: address).isConfigured(apiKey: nil))
    }

    @Test func `a compatible server with an address and model needs no key`() {
        let settings = AssistantSettings(provider: .openAICompatible, model: "llama3.2", baseURL: "http://localhost:11434/v1")

        #expect(settings.isConfigured(apiKey: nil))
    }

    @Test func `settings round-trip and each provider remembers its model`() throws {
        let defaults = try Self.freshSuite().defaults
        AssistantSettings(provider: .openAI, model: "model-a").save(to: defaults)
        AssistantSettings(provider: .anthropic, model: "claude-sonnet-5-5").save(to: defaults)

        #expect(AssistantSettings(defaults: defaults).model == "claude-sonnet-5-5")
        #expect(AssistantSettings.model(for: .openAI, in: defaults) == "model-a")
    }

    static func freshSuite() throws -> (name: String, defaults: UserDefaults) {
        let name = "BrewAssistantCloudTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return (name, defaults)
    }
}

struct ConfiguredModelTests {
    @Test func `the on-device model answers when it is chosen`() async throws {
        let suite = try AssistantSettingsTests.freshSuite()
        let model = ConfiguredPackageSuggestionModel(onDevice: FixedModel(), credentials: MemoryCredentials(), defaultsSuiteName: suite.name)

        #expect(try await model.searchTerms(for: "x") == ["on-device"])
    }

    @Test func `a cloud provider without a key needs configuration`() throws {
        let suite = try AssistantSettingsTests.freshSuite()
        AssistantSettings(provider: .anthropic).save(to: suite.defaults)
        let model = ConfiguredPackageSuggestionModel(onDevice: FixedModel(), credentials: MemoryCredentials(), defaultsSuiteName: suite.name)

        #expect(model.availability == .needsConfiguration)
    }

    @Test func `a configured cloud provider is used instead of the on-device model`() async throws {
        let suite = try AssistantSettingsTests.freshSuite()
        AssistantSettings(provider: .anthropic).save(to: suite.defaults)
        let credentials = MemoryCredentials()
        try credentials.setAPIKey("sk-ant", for: .anthropic)
        let transport = StubTransport(body: AnthropicProviderTests.message(text: #"{"terms":["cloud"]}"#))
        let model = ConfiguredPackageSuggestionModel(
            onDevice: FixedModel(), credentials: credentials, defaultsSuiteName: suite.name, transport: transport,
        )

        #expect(model.availability == .available)
        #expect(try await model.searchTerms(for: "x") == ["cloud"])
    }
}

private actor StubTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private let status: Int
    private let body: String

    init(status: Int = 200, body: String) {
        self.status = status
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else {
            throw URLError(.badURL)
        }
        return (Data(body.utf8), response)
    }
}

private struct FixedModel: PackageSuggestionModel {
    var availability: AssistantAvailability {
        .available
    }

    func searchTerms(for _: String) async throws -> [String] {
        ["on-device"]
    }

    func choose(for _: String, from _: [SuggestionCandidate]) async throws -> [ModelPick] {
        []
    }
}

// `keys` is only touched inside `lock`, so concurrent reads and writes are serialised.
// swiftlint:disable:next unchecked_sendable
private final class MemoryCredentials: AssistantCredentialStoring, @unchecked Sendable {
    private var keys: [AssistantProvider: String] = [:]
    private let lock = NSLock()

    func apiKey(for provider: AssistantProvider) -> String? {
        lock.withLock { keys[provider] }
    }

    func setAPIKey(_ key: String?, for provider: AssistantProvider) throws {
        lock.withLock { keys[provider] = key }
    }
}

private func testURL(_ string: String) throws -> URL {
    guard let url = URL(string: string) else {
        throw URLError(.badURL)
    }
    return url
}
