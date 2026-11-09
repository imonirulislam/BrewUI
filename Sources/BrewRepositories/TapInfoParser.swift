//
//  TapInfoParser.swift
//  BrewRepositories
//

import BrewCore
import Foundation

/// Decodes `brew tap-info --installed --json`. Unknown keys are ignored and optional fields default,
/// but output that is not a JSON array of objects with a `name` is an error.
enum TapInfoParser {
    static func parse(_ data: Data) throws -> [BrewTap] {
        try JSONDecoder().decode([TapInfoJSON].self, from: data)
            .filter { $0.installed ?? true }
            .map(\.tap)
            .sorted { lhs, rhs in
                if lhs.isOfficial != rhs.isOfficial {
                    return !lhs.isOfficial
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}

private struct TapInfoJSON: Decodable {
    let name: String
    let installed: Bool?
    let official: Bool?
    let trusted: Bool?
    let isPrivate: Bool?
    let remote: String?
    let formulaNames: [String]?
    let caskTokens: [String]?
    let lastCommit: String?

    enum CodingKeys: String, CodingKey {
        case name, installed, official, trusted, remote
        case isPrivate = "private"
        case formulaNames = "formula_names"
        case caskTokens = "cask_tokens"
        case lastCommit = "last_commit"
    }

    var tap: BrewTap {
        BrewTap(
            name: name,
            remote: remote.flatMap(URL.init(string:)),
            isOfficial: official ?? false,
            isTrusted: trusted ?? false,
            isPrivate: isPrivate ?? false,
            formulaNames: (formulaNames ?? []).map(Self.shortName),
            caskTokens: (caskTokens ?? []).map(Self.shortName),
            lastCommit: lastCommit,
        )
    }

    private static func shortName(_ qualified: String) -> String {
        qualified.split(separator: "/").last.map(String.init) ?? qualified
    }
}
