import ArgumentParser
import Foundation
import GeneratorCommands
import LLFSMVerifyCommands

/// The `pld` sub-command invoked from the `llfsm` binary.
public struct PLDCommand: ParsableCommand {

    /// The command configuration for the `pld` sub-command.
    public static let configuration = CommandConfiguration(
        commandName: "fpga",
        abstract:
            "Perform operations for LLFSMs deploying to Programmable Logic Devices such as FPGAs.",
        subcommands: [
            PLDGenerateCommand.self,
            PLDVerifyCommand.self,
        ]
    )

    /// Default init.
    public init() {}
}

/// Renamed wrapper around `LLFSMGenerate`.
struct PLDGenerateCommand: ParsableCommand {

    /// The configuration of the `LLFSMGenerate` command.
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: LLFSMGenerate.configuration.abstract,
        version: LLFSMGenerate.configuration.version,
        subcommands: LLFSMGenerate.configuration.subcommands
    )
}

/// Renamed wrapper around `LLFSMVerify`.
struct PLDVerifyCommand: ParsableCommand {

    /// The configuration of the `LLFSMVerify` command.
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: LLFSMVerify.configuration.abstract,
        version: LLFSMVerify.configuration.version,
    )

    /// The ``LLFSMVerify`` arguments.
    @OptionGroup var verify: LLFSMVerify

    /// Delegate to ``LLFSMVerify.run``.
    func run() throws {
        try verify.run()
    }
}
