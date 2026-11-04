import ArgumentParser
import GeneratorCommands
import llfsm_bin
import LLFSMVerifyCommands
@testable import PLDCommands
import Testing

/// Tests for the LLFSM command.
@Suite
struct LLFSMTests {

    /// The root command finds the fpga commands.
    @Test
    func testFPGADelegation() throws {
        var command = try LLFSMCommand.parseAsRoot(["fpga"])
        // A command group without a `run` implementation requests its own help.
        let error = try #require(throws: (any Error).self) { try command.run() }
        #expect(LLFSMCommand.message(for: error) == LLFSMCommand.helpMessage(for: PLDCommand.self))
    }

    /// The fpga command finds the generate commands.
    @Test
    func testFPGAGenerateDelegation() throws {
        var command = try LLFSMCommand.parseAsRoot(["fpga", "generate"])
        let error = try #require(throws: (any Error).self) { try command.run() }
        #expect(LLFSMCommand.message(for: error) == LLFSMCommand.helpMessage(for: PLDGenerateCommand.self))
    }

    /// The fpga command finds the verify command.
    @Test
    func testFPGAVerifyDelegation() throws {
        // `verify` has required arguments, so help must be requested explicitly.
        var command = try LLFSMCommand.parseAsRoot(["fpga", "verify", "--help"])
        let error = try #require(throws: (any Error).self) { try command.run() }
        #expect(LLFSMCommand.message(for: error) == LLFSMCommand.helpMessage(for: PLDVerifyCommand.self))
    }

}
