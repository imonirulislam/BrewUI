//
//  BrewTapsRepository.swift
//  BrewRepositories
//

import BrewCLI
import BrewCore
import BrewRepositoryInterfaces
import Foundation
import Observation
import OSLog

private let tapsRepositoryLogger = Logger(subsystem: "Homebrew.BrewUI", category: "BrewTapsRepository")

/// Runs `brew tap-info --installed --json`, which reads local tap clones and never touches the network.
@Observable
@MainActor
public final class BrewTapsRepository: TapsRepository {
    public private(set) var state: LoadState<[BrewTap], any Error> = .loading

    @ObservationIgnored private let commandRunner: any BrewCommandRunning
    @ObservationIgnored private let locator: any BrewExecutableLocating

    public init(executionContext: BrewCommandExecutionContext) {
        commandRunner = executionContext.commandRunner
        locator = executionContext.locator
    }

    public func load(forceRefresh: Bool) async {
        guard forceRefresh || state.value == nil else {
            return
        }
        let hadCached = state.value != nil
        if !hadCached {
            state = .loading
        }
        do {
            state = try await .loaded(fetch())
        } catch is CancellationError {
            return
        } catch {
            if hadCached {
                tapsRepositoryLogger.error("brew tap-info revalidation failed: \(error.localizedDescription, privacy: .public)")
            } else {
                state = .failed(error)
            }
        }
    }

    private func fetch() async throws -> [BrewTap] {
        let brew = try locator.findBrewExecutable()
        let output = try await commandRunner.run(executableURL: brew, arguments: ["tap-info", "--installed", "--json"])
        guard output.terminationStatus == 0 else {
            throw BrewCommandError.failed(exitCode: output.terminationStatus, stderr: output.standardError)
        }
        return try TapInfoParser.parse(Data(output.standardOutput.utf8))
    }
}
