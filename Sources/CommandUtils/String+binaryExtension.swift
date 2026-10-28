/// Add binary extension for the current platform.
extension String {
    #if os(Windows)
    /// The `.exe` extension for executables on Windows.
    public static let binaryExtension = ".exe"
    #else
    /// There is no file extension for executable binaries on this platform.
    public static let binaryExtension = ""
    #endif
}
