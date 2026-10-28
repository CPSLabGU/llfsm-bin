import CommandUtils
import Foundation

/// A Mock System Delegator.
struct TestDelegator: SystemDelegator {
    /// The executable URL to be returned by the mock delegator.
    let executable: URL?

    /// Finds the executable with the given name.
    func findExecutable(named name: String) -> URL? {
        executable
    }
}
