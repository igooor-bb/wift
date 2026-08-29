import Dispatch
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// The result of a command whose standard output and standard error were captured.
public struct CommandOutput: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// A nonzero result reported by `checkRun`.
public struct CommandFailure: Error, Sendable, CustomStringConvertible {
    public let executable: String
    public let arguments: [String]
    public let status: Int32

    public init(executable: String, arguments: [String], status: Int32) {
        self.executable = executable
        self.arguments = arguments
        self.status = status
    }

    public var description: String {
        "command failed with status \(status): \(([executable] + arguments).joined(separator: " "))"
    }
}

/// An executable that could not be found on `PATH` or at the supplied path.
public struct ExecutableNotFoundError: Error, Sendable, CustomStringConvertible {
    public let executable: String

    public init(executable: String) {
        self.executable = executable
    }

    public var description: String {
        "executable not found: \(executable)"
    }
}

/// Runs a command while inheriting standard streams, the environment, and working directory.
@discardableResult
public func run(_ executable: String, _ arguments: String...) throws -> Int32 {
    try run(executable, arguments: arguments)
}

/// Runs a command while inheriting standard streams, the environment, and working directory.
@discardableResult
public func run(_ executable: String, arguments: [String]) throws -> Int32 {
    let process = try configuredProcess(executable, arguments: arguments)
    process.standardInput = FileHandle.standardInput
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    return exitStatus(of: process)
}

/// Runs a command and throws `CommandFailure` when it exits unsuccessfully.
public func checkRun(_ executable: String, _ arguments: String...) throws {
    let status = try run(executable, arguments: arguments)
    guard status == 0 else {
        throw CommandFailure(executable: executable, arguments: arguments, status: status)
    }
}

/// Runs a command and captures stdout and stderr concurrently without trimming either stream.
public func capture(_ executable: String, _ arguments: String...) throws -> CommandOutput {
    let process = try configuredProcess(executable, arguments: arguments)
    let standardOutput = Pipe()
    let standardError = Pipe()
    let outputBuffer = LockedData()
    let errorBuffer = LockedData()
    let readers = DispatchGroup()
    process.standardInput = FileHandle.standardInput
    process.standardOutput = standardOutput
    process.standardError = standardError
    try process.run()
    readToEnd(standardOutput.fileHandleForReading, into: outputBuffer, group: readers)
    readToEnd(standardError.fileHandleForReading, into: errorBuffer, group: readers)
    process.waitUntilExit()
    readers.wait()
    return CommandOutput(
        status: exitStatus(of: process),
        stdout: String(decoding: outputBuffer.value, as: UTF8.self), // swiftlint:disable:this optional_data_string_conversion
        stderr: String(decoding: errorBuffer.value, as: UTF8.self) // swiftlint:disable:this optional_data_string_conversion
    )
}

/// Finds an executable using `PATH`, or validates a path when the name contains `/`.
public func which(_ executable: String) -> URL? {
    if executable.contains("/") {
        return executableURL(at: executable)
    }
    for directory in ProcessInfo.processInfo.environment["PATH", default: ""]
        .split(separator: ":", omittingEmptySubsequences: false)
    {
        let base = directory.isEmpty ? FileManager.default.currentDirectoryPath : String(directory)
        let candidate = URL(fileURLWithPath: base).appendingPathComponent(executable).path
        if let url = executableURL(at: candidate) {
            return url
        }
    }
    return nil
}

/// Writes a line to standard error.
public func eprint(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

/// Writes a line to standard error and terminates with the requested status.
public func die(_ message: String, status: Int32 = 1) -> Never {
    eprint(message)
    exit(status)
}

/// Information about the source script currently being executed.
public enum Script {
    /// The canonical path of the original source script.
    public static var path: URL {
        URL(fileURLWithPath: CommandLine.arguments[0])
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    /// The directory containing the original source script.
    public static var directory: URL {
        path.deletingLastPathComponent()
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data {
        lock.withLock { storage }
    }

    func append(_ data: Data) {
        lock.withLock { storage.append(data) }
    }
}

private func configuredProcess(_ executable: String, arguments: [String]) throws -> Process {
    guard let executableURL = which(executable) else {
        throw ExecutableNotFoundError(executable: executable)
    }
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    return process
}

private func executableURL(at path: String) -> URL? {
    guard FileManager.default.isExecutableFile(atPath: path) else {
        return nil
    }
    return URL(fileURLWithPath: path)
        .standardizedFileURL
        .resolvingSymlinksInPath()
}

private func exitStatus(of process: Process) -> Int32 {
    if process.terminationReason == .uncaughtSignal {
        return 128 + process.terminationStatus
    }
    return process.terminationStatus
}

private func readToEnd(_ handle: FileHandle, into buffer: LockedData, group: DispatchGroup) {
    group.enter()
    handle.readabilityHandler = { readable in
        let data = readable.availableData
        if data.isEmpty {
            readable.readabilityHandler = nil
            group.leave()
        } else {
            buffer.append(data)
        }
    }
}
