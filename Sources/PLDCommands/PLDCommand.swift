import ArgumentParser
import CommandUtils
import Foundation

/// The `pld` sub-command invoked from the `llfsm` binary.
public struct PLDCommand: ParsableCommand, SystemDelegator {

    /// The command configuration for the `pld` sub-command.
    public static let configuration = CommandConfiguration(
        commandName: "pld",
        abstract: "Perform operations for LLFSMs deploying to Programmable Logic Devices (PLDs).",
        usage: PLDSubCommand.allCases.map { "pld \($0.rawValue)" }.joined(separator: "\n")
    )

    /// The sub-command to execute.
    @Argument(help: "The sub-command to execute.")
    var command: PLDSubCommand

    /// The arguments of the sub-command.
    @Argument(help: "The sub-command arguments.")
    var arguments: [String]

    /// Default init.
    public init() {}

    /// Delegate to an existing binary.
    public func run() throws {
        try executeCommand(
            name: "llfsm-\(command.rawValue)\(String.binaryExtension)",
            arguments: self.arguments
        )
    }
}

/// The supported sub-commands for the `llfsm pld` invocation.
public enum PLDSubCommand: String, ExpressibleByArgument, CaseIterable, Equatable, Hashable, Codable, Sendable
{
    /// Delegate to `llfsm-generate`.
    case generate

    /// Delegate to `llfsm-verify`.
    case verify
}
