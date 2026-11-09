//
//  BrewTap.swift
//  BrewCore
//

import Foundation

/// An installed tap as `brew tap-info --installed --json` reports it.
public struct BrewTap: Equatable, Hashable, Identifiable, Sendable {
    public let name: String
    public let remote: URL?
    public let isOfficial: Bool
    public let isTrusted: Bool
    public let isPrivate: Bool
    /// Short names, without the `user/repo/` prefix brew reports.
    public let formulaNames: [String]
    public let caskTokens: [String]
    public let lastCommit: String?

    public var id: String {
        name
    }

    public init(
        name: String,
        remote: URL?,
        isOfficial: Bool,
        isTrusted: Bool,
        isPrivate: Bool,
        formulaNames: [String],
        caskTokens: [String],
        lastCommit: String?,
    ) {
        self.name = name
        self.remote = remote
        self.isOfficial = isOfficial
        self.isTrusted = isTrusted
        self.isPrivate = isPrivate
        self.formulaNames = formulaNames
        self.caskTokens = caskTokens
        self.lastCommit = lastCommit
    }

    /// `user/repo` with both parts made of the characters GitHub and brew accept.
    public static func isValidName(_ name: String) -> Bool {
        name.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*/) != nil
    }
}

public extension BrewCommands {
    static func tap(name: String) -> BrewCommand {
        BrewCommand(operationKind: .tapManagement, arguments: ["tap", name])
    }

    static func untap(name: String) -> BrewCommand {
        BrewCommand(operationKind: .tapManagement, arguments: ["untap", name])
    }
}

public extension BrewOperationID {
    static func tapManagement(_ command: BrewCommand) -> BrewOperationID {
        .maintenance(token: command.arguments.joined(separator: ":"), displayCommand: command.displayCommand)
    }
}
