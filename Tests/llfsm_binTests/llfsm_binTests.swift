import ArgumentParser
import llfsm_bin
import PLDCommands
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
}
