import ArgumentParser
import Foundation

/// A command that delegates to a system binary.
public protocol SystemDelegator {
    /// Execute the delegate command.
    func executeCommand(name: String, arguments: [String]) throws

    /// Find the binary path for the delegate command.
    func findExecutable(named name: String) -> URL?
}

/// Add default implementations for the `SystemDelegator` protocol methods.
extension SystemDelegator {
    /// Find and execute the binary with the given name.
    public func executeCommand(name: String, arguments: [String]) throws {
        guard let executableURL = self.findExecutable(named: name) else {
            throw ValidationError(
                "Could not find '\(name)' on PATH. "
                    + "Have you installed the llfsm binary and added it to your PATH?"
            )
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == EXIT_SUCCESS else {
            throw ExitCode(process.terminationStatus)
        }
    }

    /// Find the path to the executable with the given name.
    public func findExecutable(named name: String) -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let pathValue =
            environment.first {
                $0.key.caseInsensitiveCompare("PATH") == .orderedSame
            }?
            .value ?? ""
        #if os(Windows)
        let pathSeparator: Character = ";"
        #else
        let pathSeparator: Character = ":"
        #endif
        let fileManager = FileManager.default
        for directory in pathValue.split(separator: pathSeparator, omittingEmptySubsequences: false) {
            let directoryPath =
                directory.isEmpty
                ? fileManager.currentDirectoryPath
                : String(directory)
            let candidateURL = URL(fileURLWithPath: directoryPath)
                .appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory),
                !isDirectory.boolValue
            {
                return candidateURL
            }
        }
        return nil
    }
}
