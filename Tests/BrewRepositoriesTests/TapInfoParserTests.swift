import BrewCore
@testable import BrewRepositories
import Foundation
import Testing

struct TapInfoParserTests {
    @Test func `parses an installed third-party tap`() throws {
        let taps = try TapInfoParser.parse(Data(Self.sample.utf8))

        let tap = try #require(taps.first { $0.name == "anomalyco/tap" })
        #expect(tap.remote == URL(string: "https://github.com/anomalyco/homebrew-tap"))
        #expect(!tap.isOfficial)
        #expect(!tap.isTrusted)
        #expect(!tap.isPrivate)
        #expect(tap.formulaNames == ["opencode", "sst"])
        #expect(tap.caskTokens == ["hex"])
        #expect(tap.lastCommit == "2 days ago")
    }

    @Test func `official taps are flagged`() throws {
        let taps = try TapInfoParser.parse(Data(Self.sample.utf8))

        let core = try #require(taps.first { $0.name == "homebrew/core" })
        #expect(core.isOfficial)
        #expect(core.isTrusted)
    }

    @Test func `taps are sorted with third-party first, then by name`() throws {
        let taps = try TapInfoParser.parse(Data(Self.sample.utf8))

        #expect(taps.map(\.name) == ["anomalyco/tap", "homebrew/core"])
    }

    @Test func `missing optional fields do not reject the tap`() throws {
        let json = #"[{"name": "someone/tools", "installed": true}]"#

        let taps = try TapInfoParser.parse(Data(json.utf8))

        #expect(taps.map(\.name) == ["someone/tools"])
        #expect(taps.first?.remote == nil)
        #expect(taps.first?.formulaNames == [])
    }

    @Test func `uninstalled entries are skipped`() throws {
        let json = #"[{"name": "someone/tools", "installed": false}]"#

        #expect(try TapInfoParser.parse(Data(json.utf8)).isEmpty)
    }

    @Test func `malformed output is an error`() {
        #expect(throws: (any Error).self) {
            try TapInfoParser.parse(Data("not json".utf8))
        }
    }

    private static let sample = """
    [
      {
        "name": "homebrew/core", "user": "homebrew", "repo": "core", "installed": true,
        "official": true, "trusted": true, "formula_names": [], "cask_tokens": [],
        "remote": "https://github.com/Homebrew/homebrew-core", "private": false, "last_commit": null
      },
      {
        "name": "anomalyco/tap", "user": "anomalyco", "repo": "tap", "installed": true,
        "official": false, "trusted": false,
        "formula_names": ["anomalyco/tap/opencode", "anomalyco/tap/sst"],
        "cask_tokens": ["anomalyco/tap/hex"],
        "remote": "https://github.com/anomalyco/homebrew-tap", "custom_remote": false,
        "private": false, "HEAD": "53c6813", "last_commit": "2 days ago", "branch": "master",
        "unknown_future_key": 42
      }
    ]
    """
}
