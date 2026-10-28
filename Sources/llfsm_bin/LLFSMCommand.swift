import ArgumentParser
import PLDCommands

/// The `llfsm` binary entrypoint.
public struct LLFSMCommand: ParsableCommand {
    /// The command configuration for the `llfsm` binary.
    public static let configuration = CommandConfiguration(
        commandName: "llfsm",
        abstract: "Perform operations on Logic-Labelled Finite-State Machines (LLFSMs)",
        version: "0.1.0",
        subcommands: [PLDCommand.self]
    )

    /// Default init.
    public init() {}
}
