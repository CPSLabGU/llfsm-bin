import ArgumentParser
import CommandUtils
import Foundation
import ProcessTree
import Testing

#if os(Linux)
import Glibc
#elseif canImport(Darwin)
import Darwin
#elseif os(Windows)
import WinSDK
#endif

/// Test suite for ``SystemDelegator``.
@Suite(.serialized)
struct SystemDelegatorTests {
    /// Test that the command returns normally when the delegate succeeds.
    @Test
    func returnsNormallyWhenDelegateSucceeds() throws {
        let delegator = TestDelegator(executable: shellExecutable())
        try delegator.executeCommand(name: "fixture", arguments: shellArguments("exit 0"))
    }

    /// Test that the command throws the correct exit status when the delegate fails.
    @Test
    func preservesDelegateExitStatus() {
        let delegator = TestDelegator(executable: shellExecutable())
        do {
            try delegator.executeCommand(name: "fixture", arguments: shellArguments("exit 23"))
            Issue.record("Expected delegate exit status 23 to be thrown")
        } catch let exitCode as ExitCode {
            #expect(exitCode.rawValue == 23)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// Test that the command reports a missing executable correctly.
    @Test
    func preservesMissingExecutableDiagnostic() {
        let delegator = TestDelegator(executable: nil)
        do {
            try delegator.executeCommand(name: "missing", arguments: [])
            Issue.record("Expected missing executable to be reported")
        } catch {
            #expect(String(describing: error).contains("Could not find 'missing' on PATH"))
        }
    }

    #if os(Windows)
    /// Test that the command reports a Windows system message when the delegate cannot launch.
    @Test
    func reportsWindowsSystemMessageWhenDelegateCannotLaunch() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let missingExecutable = temporaryDirectory.appendingPathComponent("does-not-exist.exe")
        let delegator = TestDelegator(executable: missingExecutable)

        do {
            try delegator.executeCommand(name: "missing", arguments: [])
            Issue.record("Expected CreateProcessW to report a missing executable")
        } catch let error as NSError {
            #expect(error.code == Int(ERROR_FILE_NOT_FOUND))
            #expect(error.localizedDescription.contains("The system cannot find the file specified."))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    #endif

    #if os(Linux) || canImport(Darwin)
    /// Test that the command gracefully stops the process group after receiving an interrupt signal.
    @Test
    func gracefullyStopsProcessGroupAfterInterrupt() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let grandchildPIDFile = temporaryDirectory.appendingPathComponent("grandchild.pid")
        let script =
            "sleep 60 & echo $! > \"\(grandchildPIDFile.path)\"; wait"
        let delegator = TestDelegator(executable: URL(fileURLWithPath: "/bin/sh"))
        scheduleSignal(SIGINT, afterFileAppears: grandchildPIDFile)

        do {
            try delegator.executeCommand(name: "fixture", arguments: ["-c", script])
            Issue.record("Expected the interrupted delegate to return a non-zero status")
        } catch let exitCode as ExitCode {
            #expect(exitCode.rawValue == SIGTERM)
        }

        let grandchildPID = try readPID(from: grandchildPIDFile)
        #expect(waitUntilProcessStops(grandchildPID))
    }

    /// Test that the command force stops the process group after the grace period.
    @Test
    func forceStopsProcessGroupAfterGracePeriod() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let grandchildPIDFile = temporaryDirectory.appendingPathComponent("grandchild.pid")
        let script =
            "trap '' TERM; " + "(trap '' TERM; while :; do sleep 1; done) & "
            + "echo $! > \"\(grandchildPIDFile.path)\"; wait"
        let delegator = TestDelegator(executable: URL(fileURLWithPath: "/bin/sh"))
        scheduleSignal(SIGTERM, afterFileAppears: grandchildPIDFile)

        do {
            try delegator.executeCommand(name: "fixture", arguments: ["-c", script])
            Issue.record("Expected the terminated delegate to return a non-zero status")
        } catch let exitCode as ExitCode {
            #expect(exitCode.rawValue == SIGKILL)
        }

        let grandchildPID = try readPID(from: grandchildPIDFile)
        #expect(waitUntilProcessStops(grandchildPID))
    }
    #endif

    #if os(Windows)
    /// Test that the command gracefully stops the Windows job after receiving a Ctrl-Break signal.
    @Test
    func gracefullyStopsWindowsJobAfterCtrlBreak() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let grandchildPIDFile = temporaryDirectory.appendingPathComponent("grandchild.pid")
        let script =
            "$child = Start-Process -FilePath $env:ComSpec "
            + "-ArgumentList '/c ping -t 127.0.0.1 > nul' -PassThru -NoNewWindow; "
            + "[IO.File]::WriteAllText('\(grandchildPIDFile.path)', [string]$child.Id); "
            + "Wait-Process -Id $child.Id"
        let delegator = TestDelegator(executable: powershellExecutable())
        scheduleConsoleBreak(afterFileAppears: grandchildPIDFile)

        do {
            try delegator.executeCommand(
                name: "fixture",
                arguments: ["-NoProfile", "-NonInteractive", "-Command", script]
            )
        } catch is ExitCode {
        }

        let grandchildPID = try readWindowsPID(from: grandchildPIDFile)
        #expect(waitUntilWindowsProcessStops(grandchildPID))
    }

    /// Test that the command force stops the Windows job after the grace period.
    @Test
    func forceStopsWindowsJobAfterGracePeriod() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let grandchildPIDFile = temporaryDirectory.appendingPathComponent("grandchild.pid")
        let grandchildScript = temporaryDirectory.appendingPathComponent("grandchild.ps1")
        try """
        Add-Type -TypeDefinition @'
        using System;
        using System.Runtime.InteropServices;
        public static class ProcessTreeTestHandler {
            public delegate bool HandlerRoutine(uint controlType);
            private static HandlerRoutine handler = Handle;
            [DllImport("kernel32.dll")]
            private static extern bool SetConsoleCtrlHandler(HandlerRoutine handler, bool add);
            private static bool Handle(uint controlType) {
                return controlType == 0 || controlType == 1;
            }
            public static void Install() {
                SetConsoleCtrlHandler(handler, true);
            }
        }
        '@
        [ProcessTreeTestHandler]::Install()
        while ($true) { Start-Sleep -Seconds 1 }
        """
        .write(to: grandchildScript, atomically: true, encoding: .utf8)
        let script =
            "$child = Start-Process -FilePath \"$PSHOME\\powershell.exe\" "
            + "-ArgumentList ('-NoProfile -File \"\(grandchildScript.path)\"') " + "-PassThru -NoNewWindow; "
            + "[IO.File]::WriteAllText('\(grandchildPIDFile.path)', [string]$child.Id); "
            + "while ($true) { Start-Sleep -Seconds 1 }"
        let delegator = TestDelegator(executable: powershellExecutable())
        scheduleConsoleBreak(afterFileAppears: grandchildPIDFile)
        let start = Date()

        do {
            try delegator.executeCommand(
                name: "fixture",
                arguments: ["-NoProfile", "-NonInteractive", "-Command", script]
            )
            Issue.record("Expected the Windows Job Object to terminate the delegate")
        } catch is ExitCode {
        }

        #expect(Date().timeIntervalSince(start) >= 1.5)
        let grandchildPID = try readWindowsPID(from: grandchildPIDFile)
        #expect(waitUntilWindowsProcessStops(grandchildPID))
    }
    #endif
}

/// Returns the URL of the shell executable for the current platform.
private func shellExecutable() -> URL {
    #if os(Windows)
    let systemDirectory = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
    return URL(fileURLWithPath: systemDirectory).appendingPathComponent("System32/cmd.exe")
    #else
    return URL(fileURLWithPath: "/bin/sh")
    #endif
}

/// Returns the shell arguments for executing the given command on the current platform.
private func shellArguments(_ command: String) -> [String] {
    #if os(Windows)
    ["/c", command]
    #else
    ["-c", command]
    #endif
}

#if os(Windows)
/// Returns the URL of the PowerShell executable on Windows.
private func powershellExecutable() -> URL {
    let systemDirectory = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
    return URL(fileURLWithPath: systemDirectory)
        .appendingPathComponent("System32/WindowsPowerShell/v1.0/powershell.exe")
}

/// Creates a temporary directory for the test and returns its URL.
private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ProcessTreeTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Schedules a graceful shutdown request after the specified file appears.
///
/// This avoids `GenerateConsoleCtrlEvent`, which would broadcast to every process on the console.
private func scheduleConsoleBreak(afterFileAppears file: URL) {
    DispatchQueue.global()
        .async {
            let deadline = Date().addingTimeInterval(10)
            while !FileManager.default.fileExists(atPath: file.path), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard FileManager.default.fileExists(atPath: file.path) else {
                return
            }
            process_tree_request_shutdown()
        }
}

/// Reads the Windows process ID from the specified file.
private func readWindowsPID(from file: URL) throws -> DWORD {
    let value = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let processID = DWORD(value) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return processID
}

/// Waits until the Windows process with the given ID stops or the timeout is reached.
private func waitUntilWindowsProcessStops(_ processID: DWORD) -> Bool {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, processID) {
            defer { CloseHandle(process) }
            var exitCode: DWORD = 0
            if GetExitCodeProcess(process, &exitCode), exitCode != DWORD(259) {
                return true
            }
        } else {
            return true
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return false
}
#elseif os(Linux) || canImport(Darwin)
/// Creates a temporary directory for the test and returns its URL.
private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ProcessTreeTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Schedules the specified signal to be sent to the current process after the specified file appears.
private func scheduleSignal(_ signal: Int32, afterFileAppears file: URL) {
    let processID = getpid()
    DispatchQueue.global()
        .async {
            let deadline = Date().addingTimeInterval(10)
            while !FileManager.default.fileExists(atPath: file.path), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard FileManager.default.fileExists(atPath: file.path) else {
                return
            }
            _ = kill(processID, signal)
        }
}

/// Reads the process ID from the specified file.
private func readPID(from file: URL) throws -> pid_t {
    let value = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let processID = pid_t(value) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return processID
}

/// Waits until the process with the given ID stops or the timeout is reached.
private func waitUntilProcessStops(_ processID: pid_t) -> Bool {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        #if os(Linux)
        if let status = try? String(contentsOfFile: "/proc/\(processID)/stat", encoding: .utf8),
            status.split(separator: " ").dropFirst(2).first == "Z"
        {
            return true
        }
        #endif
        if kill(processID, 0) == -1 && errno == ESRCH {
            return true
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return false
}
#endif
