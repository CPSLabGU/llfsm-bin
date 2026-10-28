import ArgumentParser
import Foundation
import ProcessTree

#if os(Windows)
import WinSDK
#endif

/// A command that delegates to a system binary.
public protocol SystemDelegator {
    /// Execute the delegate command.
    func executeCommand(name: String, arguments: [String]) throws

    /// Find the binary path for the delegate command.
    func findExecutable(named name: String) -> URL?
}

/// Add default implementations for the `SystemDelegator` protocol methods.
extension SystemDelegator {
    /// Find and execute the binary, shutting down its process tree when interrupted.
    public func executeCommand(name: String, arguments: [String]) throws {
        guard let executableURL = self.findExecutable(named: name) else {
            throw ValidationError(
                "Could not find '\(name)' on PATH. "
                    + "Have you installed the llfsm binary and added it to your PATH?"
            )
        }
        var exitStatus: Int32 = 0
        let errorCode = executableURL.path.withCString { executable in
            withCStringArguments(arguments) { argumentPointers in
                argumentPointers.withUnsafeBufferPointer { buffer in
                    process_tree_run(
                        executable,
                        buffer.baseAddress,
                        2_000,
                        &exitStatus
                    )
                }
            }
        }
        guard errorCode == 0 else {
            throw NSError(
                domain: "ProcessTree",
                code: Int(errorCode),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not execute '\(executableURL.path)': \(systemErrorMessage(for: errorCode))"
                ]
            )
        }
        guard exitStatus == EXIT_SUCCESS else {
            throw ExitCode(exitStatus)
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

/// Translate a platform error returned by `process_tree_run` into a readable message.
///
/// POSIX platforms return `errno` values, whereas Windows returns Win32 error codes.
private func systemErrorMessage(for code: Int32) -> String {
    #if os(Windows)
    var buffer = [WCHAR](repeating: 0, count: 1024)
    let length = FormatMessageW(
        DWORD(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS),
        nil,
        DWORD(code),
        0,
        &buffer,
        DWORD(buffer.count),
        nil
    )
    guard length > 0 else {
        return "Unknown error \(code)"
    }
    return String(decoding: buffer.prefix(Int(length)), as: UTF16.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    #else
    return String(cString: strerror(code))
    #endif
}

/// Executes the given closure with the C string representations of the provided arguments.
private func withCStringArguments<Result>(
    _ arguments: [String],
    at index: Int = 0,
    pointers: [UnsafePointer<CChar>?] = [],
    body: ([UnsafePointer<CChar>?]) -> Result
) -> Result {
    guard index < arguments.count else {
        return body(pointers + [nil])
    }
    return arguments[index]
        .withCString { argument in
            withCStringArguments(
                arguments,
                at: index + 1,
                pointers: pointers + [argument],
                body: body
            )
        }
}
