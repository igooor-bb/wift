import Dispatch
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// The reason a child process stopped running.
///
/// Use ``succeeded`` for checked execution or ``exitCode`` when forwarding a
/// shell-compatible status to another process.
@frozen
public enum Termination: Sendable, Equatable {
    /// The process exited normally with an exit status.
    case exited(Int32)

    /// The process was terminated by a signal.
    case signaled(Int32)

    /// A Boolean value that indicates whether the process exited with status zero.
    @inlinable
    public var succeeded: Bool {
        self == .exited(0)
    }

    /// A shell-compatible exit status.
    ///
    /// A normal exit returns its status unchanged. A signal termination returns
    /// `128 + signal`.
    @inlinable
    public var exitCode: Int32 {
        switch self {
        case let .exited(status): status

        case let .signaled(signal): 128 + signal
        }
    }
}

/// The termination and captured output of a command.
///
/// Obtain a result with `Command.result(limit:)` when a nonzero exit status
/// should be inspected instead of thrown as an error.
@frozen
public struct ExecutionResult: Sendable {
    /// How the command terminated.
    public let termination: Termination
    /// Captured standard output, or empty data if the stream was not captured.
    public let stdout: Data
    /// Captured standard error, or empty data if the stream was not captured.
    public let stderr: Data

    /// A Boolean value that indicates whether the command exited with status zero.
    @inlinable
    public var succeeded: Bool {
        termination.succeeded
    }

    /// Standard output decoded as UTF-8.
    ///
    /// Malformed byte sequences are replaced with the Unicode replacement character.
    public var stdoutText: String {
        decodeUTF8(stdout)
    }

    /// Standard error decoded as UTF-8.
    ///
    /// Malformed byte sequences are replaced with the Unicode replacement character.
    public var stderrText: String {
        decodeUTF8(stderr)
    }

    fileprivate init(termination: Termination, stdout: Data = Data(), stderr: Data = Data()) {
        self.termination = termination
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// The ordered results of every command in a pipeline.
///
/// Stage order matches the order in which commands were supplied to
/// ``Command/pipe(to:)`` and ``Pipeline/pipe(to:)``.
@frozen
public struct PipelineResult: Sendable {
    /// Results in the same order as the pipeline commands.
    public let stages: [ExecutionResult]

    /// A Boolean value that indicates whether every stage exited with status zero.
    public var succeeded: Bool {
        stages.allSatisfy(\.succeeded)
    }

    /// Captured standard output from the final stage, if any.
    public var stdout: Data {
        stages.last?.stdout ?? Data()
    }

    /// Captured standard error from all stages, concatenated in stage order.
    public var stderr: Data {
        stages.reduce(into: Data()) { $0.append($1.stderr) }
    }

    /// Final standard output decoded as UTF-8.
    ///
    /// Malformed byte sequences are replaced with the Unicode replacement character.
    public var stdoutText: String {
        decodeUTF8(stdout)
    }

    /// Combined standard error decoded as UTF-8.
    ///
    /// Malformed byte sequences are replaced with the Unicode replacement character.
    public var stderrText: String {
        decodeUTF8(stderr)
    }

    fileprivate init(stages: [ExecutionResult]) {
        self.stages = stages
    }
}

/// A per-stream bound on captured output.
///
/// The limit applies independently to standard output and standard error.
public struct CaptureLimit: Sendable, Equatable {
    /// The default per-stream limit of 16 MiB.
    public static let `default` = CaptureLimit(byteCount: 16 * 1024 * 1024)
    /// An unbounded capture intended for output whose size is trusted.
    public static let unlimited = CaptureLimit(byteCount: nil)

    fileprivate let byteCount: Int?

    /// Creates a per-stream byte limit.
    ///
    /// Negative values are clamped to zero.
    ///
    /// - Parameter byteCount: The maximum number of bytes to retain from each stream.
    /// - Returns: A capture limit with a nonnegative byte count.
    public static func bytes(_ byteCount: Int) -> CaptureLimit {
        CaptureLimit(byteCount: max(0, byteCount))
    }
}

/// A source for a command's standard input.
public enum CommandInput: Sendable {
    /// Inherit the script's standard input.
    case inherit
    /// Read from `/dev/null`.
    case null
    /// Read the UTF-8 bytes of a string.
    case string(String)
    /// Read the supplied data.
    case data(Data)
    /// Read from a file.
    case file(URL)
}

/// A destination for a command's standard output or standard error.
public enum CommandOutput: Sendable {
    /// Inherit the matching stream from the script.
    case inherit
    /// Write to `/dev/null`.
    case discard
    /// Capture data in the returned result up to a per-stream limit.
    case capture(CaptureLimit = .default)
    /// Write to a file, truncating it unless `append` is `true`.
    case file(URL, append: Bool = false)
    /// Send standard error to the same destination as standard output.
    ///
    /// Use this case only with ``Command/error(_:)``.
    case mergedWithStandardOutput
}

/// A captured stream that exceeded its configured limit.
@frozen
public enum CapturedStream: String, Sendable {
    /// Standard output.
    case stdout
    /// Standard error.
    case stderr
}

/// An error produced while configuring, launching, capturing, or checking commands.
public enum CommandError: Error, Sendable, CustomStringConvertible {
    /// No executable was found at the supplied path or on `PATH`.
    case executableNotFound(String)
    /// The operating system refused to launch a command.
    ///
    /// - Parameters:
    ///   - command: The rendered command that failed to launch.
    ///   - reason: The underlying launch failure description.
    case launchFailed(command: String, reason: String)
    /// An input or output resource could not be prepared.
    ///
    /// - Parameters:
    ///   - command: The rendered command whose I/O setup failed.
    ///   - reason: The underlying I/O failure description.
    case ioFailed(command: String, reason: String)
    /// Commands or redirections cannot form a valid pipeline.
    case invalidPipeline(String)
    /// A checked command terminated unsuccessfully.
    ///
    /// - Parameters:
    ///   - command: The rendered command that failed.
    ///   - result: The command's termination and captured output.
    case unsuccessful(command: String, result: ExecutionResult)
    /// At least one checked pipeline stage terminated unsuccessfully.
    ///
    /// - Parameters:
    ///   - commands: Rendered commands in pipeline order.
    ///   - result: The result of every pipeline stage.
    case pipelineFailed(commands: [String], result: PipelineResult)
    /// A captured stream produced more data than its configured limit.
    ///
    /// - Parameters:
    ///   - command: The rendered command that exceeded the limit.
    ///   - stream: The stream that exceeded the limit.
    ///   - limit: The configured limit in bytes.
    case outputLimitExceeded(command: String, stream: CapturedStream, limit: Int)

    /// A concise diagnostic suitable for standard error.
    public var description: String {
        switch self {
        case let .executableNotFound(executable):
            return "executable not found: \(executable)"

        case let .launchFailed(command, reason):
            return "unable to launch \(command): \(reason)"

        case let .ioFailed(command, reason):
            return "unable to configure I/O for \(command): \(reason)"

        case let .invalidPipeline(reason):
            return "invalid pipeline: \(reason)"

        case let .unsuccessful(command, result):
            return "command failed with status \(result.termination.exitCode): \(command)"

        case let .pipelineFailed(commands, result):
            let statuses = result.stages.map { String($0.termination.exitCode) }.joined(separator: ",")
            return "pipeline failed with statuses [\(statuses)]: \(commands.joined(separator: " -> "))"

        case let .outputLimitExceeded(command, stream, limit):
            return "\(stream.rawValue) exceeded \(limit) bytes: \(command)"
        }
    }
}

/// An immutable description of a process invocation.
///
/// A command passes every argument directly to the executable and never invokes
/// a shell implicitly. Build commands with `cmd(_:_:)` or
/// ``cmd(_:arguments:)``, apply value modifiers, and finish with an execution
/// method such as `run()`, `text(limit:)`, or `result(limit:)`.
///
/// ```swift
/// let branch = try cmd("git", "branch", "--show-current")
///     .inDirectory(repository)
///     .environment(["LC_ALL": "C"])
///     .text()
/// ```
public struct Command: Sendable, CustomStringConvertible {
    /// The executable name or path.
    public let executable: String
    /// Arguments passed directly to the executable.
    public let arguments: [String]

    fileprivate var workingDirectory: URL?
    fileprivate var environmentUpdates: [String: String?]
    fileprivate var inheritsEnvironment: Bool
    fileprivate var standardInput: CommandInput
    fileprivate var standardOutput: CommandOutput
    fileprivate var standardError: CommandOutput

    fileprivate init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
        workingDirectory = nil
        environmentUpdates = [:]
        inheritsEnvironment = true
        standardInput = .inherit
        standardOutput = .inherit
        standardError = .inherit
    }

    /// A diagnostic representation that quotes arguments without evaluating them.
    public var description: String {
        ([executable] + arguments).map(renderArgument).joined(separator: " ")
    }

    /// Returns a command that runs in a working directory.
    ///
    /// - Parameter directory: The working directory for the child process.
    /// - Returns: A modified copy of this command.
    public func inDirectory(_ directory: URL) -> Command {
        modifying { $0.workingDirectory = directory }
    }

    /// Returns a command with environment changes.
    ///
    /// A `nil` value removes the corresponding variable. Pass `false` for
    /// `inherit` to start from an empty environment.
    ///
    /// - Parameters:
    ///   - updates: Variables to add, replace, or remove.
    ///   - inherit: Whether to begin with the script's inherited environment.
    /// - Returns: A modified copy of this command.
    public func environment(_ updates: [String: String?], inherit: Bool = true) -> Command {
        modifying {
            $0.environmentUpdates = updates
            $0.inheritsEnvironment = inherit
        }
    }

    /// Returns a command with the supplied standard input.
    ///
    /// - Parameter input: The source connected to standard input.
    /// - Returns: A modified copy of this command.
    public func input(_ input: CommandInput) -> Command {
        modifying { $0.standardInput = input }
    }

    /// Returns a command with the supplied standard output destination.
    ///
    /// - Parameter output: The destination connected to standard output.
    /// - Returns: A modified copy of this command.
    public func output(_ output: CommandOutput) -> Command {
        modifying { $0.standardOutput = output }
    }

    /// Returns a command with the supplied standard error destination.
    ///
    /// - Parameter output: The destination connected to standard error.
    /// - Returns: A modified copy of this command.
    public func error(_ output: CommandOutput) -> Command {
        modifying { $0.standardError = output }
    }

    /// Connects this command's standard output to another command's standard input.
    ///
    /// - Parameter command: The next command in the pipeline.
    /// - Returns: A two-stage pipeline.
    public func pipe(to command: Command) -> Pipeline {
        Pipeline(commands: [self, command])
    }

    /// Runs the command synchronously and checks its termination.
    ///
    /// Standard input, output, and error are inherited unless explicitly redirected.
    ///
    /// - Throws: ``CommandError`` if setup or launch fails, or if the command
    ///   doesn't exit successfully.
    public func run() throws {
        let result = try ExecutionEngine.execute(commands: [self])[0]
        try check(result)
    }

    /// Runs the command asynchronously and checks its termination.
    ///
    /// Cancelling the current task terminates and reaps the child process.
    ///
    /// - Throws: ``CommandError`` if setup, launch, or checked execution fails;
    ///   `CancellationError` if the task is cancelled.
    public func run() async throws {
        let result = try await ExecutionEngine.executeAsync(commands: [self])[0]
        try check(result)
    }

    /// Runs the command synchronously without checking its exit status.
    ///
    /// - Returns: The reason the child process terminated.
    /// - Throws: ``CommandError`` if setup or launch fails.
    public func status() throws -> Termination {
        try ExecutionEngine.execute(commands: [self])[0].termination
    }

    /// Runs the command asynchronously without checking its exit status.
    ///
    /// Cancelling the current task terminates and reaps the child process.
    ///
    /// - Returns: The reason the child process terminated.
    /// - Throws: ``CommandError`` if setup or launch fails; `CancellationError`
    ///   if the task is cancelled.
    public func status() async throws -> Termination {
        try await ExecutionEngine.executeAsync(commands: [self])[0].termination
    }

    /// Runs the command synchronously and captures inherited output streams.
    ///
    /// A nonzero exit status is returned in the result and doesn't throw.
    /// Explicit file, discard, and merge destinations remain unchanged.
    ///
    /// - Parameter limit: The maximum bytes retained from each captured stream.
    /// - Returns: The termination and captured output of the command.
    /// - Throws: ``CommandError`` if setup, launch, or capture fails.
    public func result(limit: CaptureLimit = .default) throws -> ExecutionResult {
        try ExecutionEngine.execute(commands: [capturingResult(limit: limit)])[0]
    }

    /// Runs the command asynchronously and captures inherited output streams.
    ///
    /// A nonzero exit status is returned in the result and doesn't throw.
    /// Explicit file, discard, and merge destinations remain unchanged.
    ///
    /// - Parameter limit: The maximum bytes retained from each captured stream.
    /// - Returns: The termination and captured output of the command.
    /// - Throws: ``CommandError`` if setup, launch, or capture fails;
    ///   `CancellationError` if the task is cancelled.
    public func result(limit: CaptureLimit = .default) async throws -> ExecutionResult {
        try await ExecutionEngine.executeAsync(commands: [capturingResult(limit: limit)])[0]
    }

    /// Runs the command and returns checked standard output as text.
    ///
    /// All trailing carriage returns and line feeds are removed. Other whitespace
    /// is preserved.
    ///
    /// - Parameter limit: The maximum bytes retained from standard output.
    /// - Returns: Standard output decoded as UTF-8.
    /// - Throws: ``CommandError`` if setup, launch, capture, or checked execution fails.
    public func text(limit: CaptureLimit = .default) throws -> String {
        let result = try ExecutionEngine.execute(commands: [capturingOutput(limit: limit)])[0]
        try check(result)
        return trimmingTrailingNewlines(result.stdoutText)
    }

    /// Runs the command asynchronously and returns checked standard output as text.
    ///
    /// All trailing carriage returns and line feeds are removed. Other whitespace
    /// is preserved.
    ///
    /// - Parameter limit: The maximum bytes retained from standard output.
    /// - Returns: Standard output decoded as UTF-8.
    /// - Throws: ``CommandError`` if setup, launch, capture, or checked execution
    ///   fails; `CancellationError` if the task is cancelled.
    public func text(limit: CaptureLimit = .default) async throws -> String {
        let result = try await ExecutionEngine.executeAsync(commands: [capturingOutput(limit: limit)])[0]
        try check(result)
        return trimmingTrailingNewlines(result.stdoutText)
    }

    /// Runs the command and returns checked standard output as lines.
    ///
    /// - Parameter limit: The maximum bytes retained from standard output.
    /// - Returns: Standard output decoded as UTF-8 and split at line boundaries.
    /// - Throws: ``CommandError`` if setup, launch, capture, or checked execution fails.
    public func lines(limit: CaptureLimit = .default) throws -> [String] {
        try splitLines(text(limit: limit))
    }

    /// Runs the command asynchronously and returns checked standard output as lines.
    ///
    /// - Parameter limit: The maximum bytes retained from standard output.
    /// - Returns: Standard output decoded as UTF-8 and split at line boundaries.
    /// - Throws: ``CommandError`` if setup, launch, capture, or checked execution
    ///   fails; `CancellationError` if the task is cancelled.
    public func lines(limit: CaptureLimit = .default) async throws -> [String] {
        try await splitLines(text(limit: limit))
    }

    /// Runs the command and streams checked standard output line by line.
    ///
    /// Ending iteration before the stream finishes cancels and reaps the command.
    /// Execution and decoding errors are delivered by the stream while iterating.
    ///
    /// - Returns: An asynchronous stream of decoded output lines.
    public func streamLines() -> AsyncThrowingStream<String, Error> {
        makeLineStream(commands: [self], descriptions: [description])
    }

    fileprivate func capturingOutput(limit: CaptureLimit) -> Command {
        output(.capture(limit))
    }

    fileprivate func capturingResult(limit: CaptureLimit) -> Command {
        var copy = self
        if case .inherit = copy.standardOutput {
            copy.standardOutput = .capture(limit)
        }
        if case .inherit = copy.standardError {
            copy.standardError = .capture(limit)
        }
        return copy
    }

    fileprivate func check(_ result: ExecutionResult) throws {
        guard result.succeeded else {
            throw CommandError.unsuccessful(command: description, result: result)
        }
    }

    private func modifying(_ body: (inout Command) -> Void) -> Command {
        var copy = self
        body(&copy)
        return copy
    }
}

/// An immutable, nonempty sequence of explicitly connected commands.
///
/// Pipelines use pipefail semantics: checked operations fail when any stage
/// terminates unsuccessfully, while result operations preserve every stage result.
public struct Pipeline: Sendable {
    fileprivate let commands: [Command]

    /// Appends a command to the pipeline.
    ///
    /// - Parameter command: The command to append as the final stage.
    /// - Returns: A new pipeline containing the appended command.
    public func pipe(to command: Command) -> Pipeline {
        Pipeline(commands: commands + [command])
    }

    /// Runs the pipeline synchronously and checks every stage.
    ///
    /// - Throws: ``CommandError`` if setup or launch fails, or if any stage
    ///   terminates unsuccessfully.
    public func run() throws {
        let result = try PipelineResult(stages: ExecutionEngine.execute(commands: commands))
        try check(result)
    }

    /// Runs the pipeline asynchronously and checks every stage.
    ///
    /// Cancelling the current task terminates and reaps every direct child process.
    ///
    /// - Throws: ``CommandError`` if setup, launch, or checked execution fails;
    ///   `CancellationError` if the task is cancelled.
    public func run() async throws {
        let result = try await PipelineResult(stages: ExecutionEngine.executeAsync(commands: commands))
        try check(result)
    }

    /// Runs the pipeline synchronously without checking exit statuses.
    ///
    /// - Returns: Stage terminations in pipeline order.
    /// - Throws: ``CommandError`` if setup or launch fails.
    public func status() throws -> [Termination] {
        try ExecutionEngine.execute(commands: commands).map(\.termination)
    }

    /// Runs the pipeline asynchronously without checking exit statuses.
    ///
    /// - Returns: Stage terminations in pipeline order.
    /// - Throws: ``CommandError`` if setup or launch fails; `CancellationError`
    ///   if the task is cancelled.
    public func status() async throws -> [Termination] {
        try await ExecutionEngine.executeAsync(commands: commands).map(\.termination)
    }

    /// Runs the pipeline synchronously and captures inherited output streams.
    ///
    /// Exit statuses aren't checked. Standard output is captured from the final
    /// stage, and standard error is captured independently for every stage.
    ///
    /// - Parameter limit: The maximum bytes retained from each captured stream.
    /// - Returns: Results for every stage in pipeline order.
    /// - Throws: ``CommandError`` if setup, launch, or capture fails.
    public func result(limit: CaptureLimit = .default) throws -> PipelineResult {
        try PipelineResult(stages: ExecutionEngine.execute(commands: capturingResult(limit: limit)))
    }

    /// Runs the pipeline asynchronously and captures inherited output streams.
    ///
    /// Exit statuses aren't checked. Standard output is captured from the final
    /// stage, and standard error is captured independently for every stage.
    ///
    /// - Parameter limit: The maximum bytes retained from each captured stream.
    /// - Returns: Results for every stage in pipeline order.
    /// - Throws: ``CommandError`` if setup, launch, or capture fails;
    ///   `CancellationError` if the task is cancelled.
    public func result(limit: CaptureLimit = .default) async throws -> PipelineResult {
        try await PipelineResult(stages: ExecutionEngine.executeAsync(commands: capturingResult(limit: limit)))
    }

    /// Runs the pipeline and returns checked final output as text.
    ///
    /// All trailing carriage returns and line feeds are removed. Pipefail applies
    /// to every stage.
    ///
    /// - Parameter limit: The maximum bytes retained from final standard output.
    /// - Returns: Final standard output decoded as UTF-8.
    /// - Throws: ``CommandError`` if setup, launch, capture, or checked execution fails.
    public func text(limit: CaptureLimit = .default) throws -> String {
        let result = try PipelineResult(
            stages: ExecutionEngine.execute(commands: capturingOutput(limit: limit))
        )
        try check(result)
        return trimmingTrailingNewlines(result.stdoutText)
    }

    /// Runs the pipeline asynchronously and returns checked final output as text.
    ///
    /// All trailing carriage returns and line feeds are removed. Pipefail applies
    /// to every stage.
    ///
    /// - Parameter limit: The maximum bytes retained from final standard output.
    /// - Returns: Final standard output decoded as UTF-8.
    /// - Throws: ``CommandError`` if setup, launch, capture, or checked execution
    ///   fails; `CancellationError` if the task is cancelled.
    public func text(limit: CaptureLimit = .default) async throws -> String {
        let result = try await PipelineResult(
            stages: ExecutionEngine.executeAsync(commands: capturingOutput(limit: limit))
        )
        try check(result)
        return trimmingTrailingNewlines(result.stdoutText)
    }

    /// Runs the pipeline and returns checked final output as lines.
    ///
    /// - Parameter limit: The maximum bytes retained from final standard output.
    /// - Returns: Final standard output decoded as UTF-8 and split at line boundaries.
    /// - Throws: ``CommandError`` if setup, launch, capture, or checked execution fails.
    public func lines(limit: CaptureLimit = .default) throws -> [String] {
        try splitLines(text(limit: limit))
    }

    /// Runs the pipeline asynchronously and returns checked final output as lines.
    ///
    /// - Parameter limit: The maximum bytes retained from final standard output.
    /// - Returns: Final standard output decoded as UTF-8 and split at line boundaries.
    /// - Throws: ``CommandError`` if setup, launch, capture, or checked execution
    ///   fails; `CancellationError` if the task is cancelled.
    public func lines(limit: CaptureLimit = .default) async throws -> [String] {
        try await splitLines(text(limit: limit))
    }

    /// Runs the pipeline and streams checked final output line by line.
    ///
    /// Pipefail applies to every stage. Ending iteration before the stream finishes
    /// cancels and reaps every process.
    ///
    /// - Returns: An asynchronous stream of decoded lines from the final stage.
    public func streamLines() -> AsyncThrowingStream<String, Error> {
        makeLineStream(commands: commands, descriptions: commands.map(\.description))
    }

    private func capturingOutput(limit: CaptureLimit) -> [Command] {
        var copy = commands
        let last = copy.index(before: copy.endIndex)
        copy[last] = copy[last].capturingOutput(limit: limit)
        return copy
    }

    private func capturingResult(limit: CaptureLimit) -> [Command] {
        var copy = commands
        for index in copy.indices {
            if case .inherit = copy[index].standardError {
                copy[index].standardError = .capture(limit)
            }
        }
        let last = copy.index(before: copy.endIndex)
        if case .inherit = copy[last].standardOutput {
            copy[last].standardOutput = .capture(limit)
        }
        return copy
    }

    private func check(_ result: PipelineResult) throws {
        guard result.succeeded else {
            throw CommandError.pipelineFailed(commands: commands.map(\.description), result: result)
        }
    }
}

/// Creates a command from variadic arguments.
///
/// Arguments are passed directly to the executable without shell parsing.
///
/// - Parameters:
///   - executable: An executable name resolved through `PATH`, or an executable path.
///   - arguments: Arguments passed directly to the executable.
/// - Returns: An immutable command configuration.
public func cmd(_ executable: String, _ arguments: String...) -> Command {
    Command(executable: executable, arguments: arguments)
}

/// Creates a command from an argument array.
///
/// Arguments are passed directly to the executable without shell parsing.
///
/// - Parameters:
///   - executable: An executable name resolved through `PATH`, or an executable path.
///   - arguments: Arguments passed directly to the executable.
/// - Returns: An immutable command configuration.
public func cmd(_ executable: String, arguments: [String]) -> Command {
    Command(executable: executable, arguments: arguments)
}

/// Explicit shell syntax with safely quoted interpolated values.
///
/// Literal segments are trusted shell syntax. Each interpolation is single-quoted
/// as one shell argument, including embedded quotes and shell metacharacters.
///
/// ```swift
/// let revision = "feature branch; echo unsafe"
/// try shell("git show \(revision) | wc -l").run()
/// ```
///
/// Use ``shell(raw:)`` only when an entire dynamic string is trusted shell code.
public struct ShellScript: Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    fileprivate let source: String

    /// Creates a shell script from a string literal.
    ///
    /// - Parameter value: Trusted literal shell syntax.
    public init(stringLiteral value: String) {
        source = value
    }

    /// Creates a shell script from literal syntax and quoted interpolations.
    ///
    /// - Parameter stringInterpolation: The completed interpolation storage.
    public init(stringInterpolation: StringInterpolation) {
        source = stringInterpolation.source
    }

    /// Storage used while constructing an interpolated shell script.
    public struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var source: String

        /// Creates interpolation storage with an initial literal capacity.
        ///
        /// - Parameters:
        ///   - literalCapacity: The combined character capacity of literal segments.
        ///   - interpolationCount: The number of interpolated values.
        public init(literalCapacity: Int, interpolationCount _: Int) {
            source = ""
            source.reserveCapacity(literalCapacity)
        }

        /// Appends trusted literal shell syntax.
        ///
        /// - Parameter literal: A literal segment supplied by the compiler.
        public mutating func appendLiteral(_ literal: String) {
            source += literal
        }

        /// Appends a value quoted as one shell argument.
        ///
        /// - Parameter value: The value whose description is safely quoted.
        public mutating func appendInterpolation(_ value: some CustomStringConvertible) {
            source += quoteForShell(value.description)
        }
    }
}

/// Creates an explicit `/bin/sh` command with safely quoted interpolations.
///
/// - Parameter script: Literal shell syntax with safely quoted interpolations.
/// - Returns: A command that invokes `/bin/sh -c`.
public func shell(_ script: ShellScript) -> Command {
    cmd("/bin/sh", "-c", script.source)
}

/// Creates an explicit `/bin/sh` command from unmodified dynamic syntax.
///
/// - Warning: The string is passed to the shell without escaping. Use this overload
///   only when the entire value is trusted shell syntax. Prefer ``shell(_:)`` for
///   interpolated data.
///
/// - Parameter script: Trusted shell syntax passed unchanged to `/bin/sh -c`.
/// - Returns: A command that invokes `/bin/sh -c`.
public func shell(raw script: String) -> Command {
    cmd("/bin/sh", "-c", script)
}

/// Writes a message and a newline to standard error.
///
/// - Parameter message: The message to write.
public func eprint(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

/// Writes an error message and terminates the script.
///
/// - Parameters:
///   - message: The message written to standard error.
///   - status: The process exit status.
public func die(_ message: String, status: Int32 = 1) -> Never {
    eprint(message)
    exit(status)
}

/// Information about the source script and its invocation.
///
/// `wift` preserves the original script path in argument zero and forwards every
/// argument after the source path unchanged.
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

    /// Arguments passed after the script path, excluding argument zero.
    public static var arguments: [String] {
        Array(CommandLine.arguments.dropFirst())
    }

    /// The script's inherited environment at the time this property is accessed.
    public static var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }
}

private enum ExecutionEngine {
    static func execute(
        commands: [Command],
        controller: CancellationController? = nil,
        lineEmitter: LineEmitter? = nil
    ) throws -> [ExecutionResult] {
        guard !commands.isEmpty else {
            throw CommandError.invalidPipeline("at least one command is required")
        }
        try validate(commands)

        let controller = controller ?? CancellationController()
        let descriptions = commands.map(\.description)
        let inheritedEnvironment = ProcessInfo.processInfo.environment
        let processes = commands.map { _ in Process() }
        let connections = (1 ..< commands.count).map { _ in Pipe() }
        let readers = DispatchGroup()
        var stdoutReaders = [CaptureReader?](repeating: nil, count: commands.count)
        var stderrReaders = [CaptureReader?](repeating: nil, count: commands.count)
        var closeAfterLaunch: [FileHandle] = []
        closeAfterLaunch.reserveCapacity(commands.count * 3)
        var inputWriter: InputWriter?

        for index in commands.indices {
            let command = commands[index]
            let process = processes[index]
            let environment = resolvedEnvironment(
                for: command,
                inheritedEnvironment: inheritedEnvironment
            )
            process.executableURL = try resolveExecutable(
                command.executable,
                environment: environment,
                workingDirectory: command.workingDirectory
            )
            process.arguments = command.arguments
            process.environment = environment
            process.currentDirectoryURL = command.workingDirectory

            if index == commands.startIndex {
                let input = try prepareInput(command.standardInput, command: descriptions[index])
                process.standardInput = input.value
                closeAfterLaunch += input.closeAfterLaunch
                inputWriter = input.writer
            } else {
                let handle = connections[index - 1].fileHandleForReading
                process.standardInput = handle
                closeAfterLaunch.append(handle)
            }

            if index < commands.index(before: commands.endIndex) {
                let handle = connections[index].fileHandleForWriting
                process.standardOutput = handle
                closeAfterLaunch.append(handle)
            } else if let lineEmitter {
                let prepared = prepareCapture(
                    limit: nil,
                    collect: false,
                    observer: { @Sendable [lineEmitter] data in lineEmitter.consume(data) }
                )
                process.standardOutput = prepared.value
                closeAfterLaunch += prepared.closeAfterLaunch
                stdoutReaders[index] = prepared.reader
            } else {
                let prepared = try prepareOutput(
                    command.standardOutput,
                    inherited: .standardOutput,
                    command: descriptions[index]
                )
                process.standardOutput = prepared.value
                closeAfterLaunch += prepared.closeAfterLaunch
                if let reader = prepared.reader {
                    stdoutReaders[index] = reader
                }
            }

            if case .mergedWithStandardOutput = command.standardError {
                process.standardError = process.standardOutput
            } else {
                let prepared = try prepareOutput(
                    command.standardError,
                    inherited: .standardError,
                    command: descriptions[index]
                )
                process.standardError = prepared.value
                closeAfterLaunch += prepared.closeAfterLaunch
                if let reader = prepared.reader {
                    stderrReaders[index] = reader
                }
            }
        }

        for reader in stdoutReaders {
            reader?.start(group: readers)
        }
        for reader in stderrReaders {
            reader?.start(group: readers)
        }

        var launched: [Process] = []
        do {
            for process in processes {
                try process.run()
                launched.append(process)
                controller.register(process)
                if controller.isCancelled {
                    throw CancellationError()
                }
            }
        } catch {
            close(closeAfterLaunch)
            inputWriter?.cancel()
            forceTerminate(launched)
            launched.forEach { $0.waitUntilExit() }
            readers.wait()
            if error is CancellationError {
                throw error
            }
            throw CommandError.launchFailed(
                command: descriptions[launched.count],
                reason: error.localizedDescription
            )
        }

        close(closeAfterLaunch)
        inputWriter?.start()
        processes.forEach { $0.waitUntilExit() }
        inputWriter?.wait()
        readers.wait()

        var results: [ExecutionResult] = []
        results.reserveCapacity(commands.count)
        for index in commands.indices {
            if let reader = stdoutReaders[index], let limit = reader.exceededLimit {
                throw CommandError.outputLimitExceeded(
                    command: descriptions[index],
                    stream: .stdout,
                    limit: limit
                )
            }
            if let reader = stderrReaders[index], let limit = reader.exceededLimit {
                throw CommandError.outputLimitExceeded(
                    command: descriptions[index],
                    stream: .stderr,
                    limit: limit
                )
            }
            results.append(
                ExecutionResult(
                    termination: termination(of: processes[index]),
                    stdout: stdoutReaders[index]?.data ?? Data(),
                    stderr: stderrReaders[index]?.data ?? Data()
                )
            )
        }
        if controller.isCancelled {
            throw CancellationError()
        }
        return results
    }

    static func executeAsync(
        commands: [Command],
        lineEmitter: LineEmitter? = nil
    ) async throws -> [ExecutionResult] {
        let controller = CancellationController()
        return try await withTaskCancellationHandler {
            let results = try await Task.detached {
                try execute(commands: commands, controller: controller, lineEmitter: lineEmitter)
            }.value
            if controller.isCancelled {
                throw CancellationError()
            }
            return results
        } onCancel: {
            controller.cancel()
        }
    }

    private static func validate(_ commands: [Command]) throws {
        for command in commands.dropLast() {
            guard case .inherit = command.standardOutput else {
                throw CommandError.invalidPipeline("only the final command may redirect standard output")
            }
        }
        for command in commands.dropFirst() {
            guard case .inherit = command.standardInput else {
                throw CommandError.invalidPipeline("only the first command may configure standard input")
            }
        }
        for command in commands {
            if case .mergedWithStandardOutput = command.standardOutput {
                throw CommandError.invalidPipeline(
                    "standard output cannot merge into itself: \(command.description)"
                )
            }
        }
    }
}

private struct PreparedInput: ~Copyable {
    let value: FileHandle
    let closeAfterLaunch: [FileHandle]
    let writer: InputWriter?
}

private struct PreparedOutput: ~Copyable {
    let value: FileHandle
    let closeAfterLaunch: [FileHandle]
    let reader: CaptureReader?
}

private func prepareInput(_ input: CommandInput, command: String) throws -> PreparedInput {
    do {
        switch input {
        case .inherit:
            return PreparedInput(value: FileHandle.standardInput, closeAfterLaunch: [], writer: nil)

        case .null:
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/null"))
            return PreparedInput(value: handle, closeAfterLaunch: [handle], writer: nil)

        case let .string(string):
            return prepareDataInput(Data(string.utf8))

        case let .data(data):
            return prepareDataInput(data)

        case let .file(url):
            let handle = try FileHandle(forReadingFrom: url)
            return PreparedInput(value: handle, closeAfterLaunch: [handle], writer: nil)
        }
    } catch {
        throw CommandError.ioFailed(command: command, reason: error.localizedDescription)
    }
}

private func prepareDataInput(_ data: Data) -> PreparedInput {
    let pipe = Pipe()
    return PreparedInput(
        value: pipe.fileHandleForReading,
        closeAfterLaunch: [pipe.fileHandleForReading],
        writer: InputWriter(handle: pipe.fileHandleForWriting, data: data)
    )
}

private func prepareOutput(
    _ output: CommandOutput,
    inherited: FileHandle,
    command: String
) throws -> PreparedOutput {
    do {
        switch output {
        case .inherit:
            return PreparedOutput(value: inherited, closeAfterLaunch: [], reader: nil)

        case .discard:
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
            return PreparedOutput(value: handle, closeAfterLaunch: [handle], reader: nil)

        case let .capture(limit):
            return prepareCapture(limit: limit.byteCount, collect: true, observer: nil)

        case let .file(url, append):
            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            let handle = try FileHandle(forWritingTo: url)
            if append {
                _ = try handle.seekToEnd()
            } else {
                try handle.truncate(atOffset: 0)
            }
            return PreparedOutput(value: handle, closeAfterLaunch: [handle], reader: nil)

        case .mergedWithStandardOutput:
            throw CommandError.invalidPipeline("mergedWithStandardOutput is valid only for standard error")
        }
    } catch let error as CommandError {
        throw error
    } catch {
        throw CommandError.ioFailed(command: command, reason: error.localizedDescription)
    }
}

private func prepareCapture(
    limit: Int?,
    collect: Bool,
    observer: (@Sendable (Data) -> Void)?
) -> PreparedOutput {
    let reader = CaptureReader(limit: limit, collect: collect, observer: observer)
    return PreparedOutput(
        value: reader.pipe.fileHandleForWriting,
        closeAfterLaunch: [reader.pipe.fileHandleForWriting],
        reader: reader
    )
}

private final class CaptureReader: @unchecked Sendable {
    let pipe = Pipe()

    private let buffer: CaptureBuffer
    private let observer: (@Sendable (Data) -> Void)?

    init(limit: Int?, collect: Bool, observer: (@Sendable (Data) -> Void)?) {
        buffer = CaptureBuffer(limit: limit, collect: collect)
        self.observer = observer
    }

    var data: Data {
        buffer.data
    }

    var exceededLimit: Int? {
        buffer.exceededLimit
    }

    func start(group: DispatchGroup) {
        group.enter()
        pipe.fileHandleForReading.readabilityHandler = { [buffer, observer] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                try? handle.close()
                group.leave()
            } else {
                buffer.append(data)
                observer?(data)
            }
        }
    }
}

private final class CaptureBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int?
    private let collect: Bool
    private var storage = Data()
    private var overflow = false

    init(limit: Int?, collect: Bool) {
        self.limit = limit
        self.collect = collect
    }

    var data: Data {
        lock.withLock { storage }
    }

    var exceededLimit: Int? {
        lock.withLock { overflow ? limit : nil }
    }

    func append(_ data: Data) {
        lock.withLock {
            guard collect else {
                return
            }
            guard let limit else {
                storage.append(data)
                return
            }
            let remaining = max(0, limit - storage.count)
            storage.append(data.prefix(remaining))
            overflow = overflow || data.count > remaining
        }
    }
}

private final class InputWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let data: Data
    private let group = DispatchGroup()

    init(handle: FileHandle, data: Data) {
        self.handle = handle
        self.data = data
    }

    func start() {
        group.enter()
        DispatchQueue.global().async { [self] in
            handle.write(data)
            try? handle.close()
            group.leave()
        }
    }

    func cancel() {
        try? handle.close()
    }

    func wait() {
        group.wait()
    }
}

private final class CancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [Process] = []
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func register(_ process: Process) {
        let cancelNow = lock.withLock {
            processes.append(process)
            return cancelled
        }
        if cancelNow, process.isRunning {
            process.terminate()
        }
    }

    func cancel() {
        let firstCancellation = lock.withLock {
            guard !cancelled else {
                return false
            }
            cancelled = true
            return true
        }
        guard firstCancellation else {
            return
        }
        terminateCurrentProcesses()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in
            forceKillCurrentProcesses()
        }
    }

    private func terminateCurrentProcesses() {
        let current = lock.withLock { processes }
        for process in current where process.isRunning {
            process.terminate()
        }
    }

    private func forceKillCurrentProcesses() {
        let identifiers = lock.withLock { processes.filter(\.isRunning).map(\.processIdentifier) }
        for identifier in identifiers {
            _ = kill(identifier, SIGKILL)
        }
    }
}

private final class LineEmitter: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private var storage = Data()
    private var finished = false

    init(_ continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = continuation
    }

    func consume(_ data: Data) {
        let lines = lock.withLock { () -> [String] in
            guard !finished else {
                return []
            }
            storage.append(data)
            var lines: [String] = []
            var lineStart = storage.startIndex
            while let newline = storage[lineStart...].firstIndex(of: 10) {
                var line = Data(storage[lineStart ..< newline])
                if line.last == 13 {
                    line.removeLast()
                }
                lines.append(decodeUTF8(line))
                lineStart = storage.index(after: newline)
            }
            if lineStart != storage.startIndex {
                storage.removeSubrange(storage.startIndex ..< lineStart)
            }
            return lines
        }
        lines.forEach { continuation.yield($0) }
    }

    func finish(throwing error: Error? = nil) {
        let trailing = lock.withLock { () -> String? in
            guard !finished else {
                return nil
            }
            finished = true
            guard !storage.isEmpty else {
                return nil
            }
            defer { storage.removeAll() }
            return decodeUTF8(storage)
        }
        if let trailing {
            continuation.yield(trailing)
        }
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}

private func makeLineStream(
    commands: [Command],
    descriptions: [String]
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let emitter = LineEmitter(continuation)
        let task = Task {
            do {
                let stages = try await ExecutionEngine.executeAsync(commands: commands, lineEmitter: emitter)
                let result = PipelineResult(stages: stages)
                guard result.succeeded else {
                    if commands.count == 1 {
                        throw CommandError.unsuccessful(command: descriptions[0], result: stages[0])
                    }
                    throw CommandError.pipelineFailed(commands: descriptions, result: result)
                }
                emitter.finish()
            } catch {
                emitter.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}

private func resolvedEnvironment(
    for command: Command,
    inheritedEnvironment: [String: String]
) -> [String: String] {
    var environment = command.inheritsEnvironment ? inheritedEnvironment : [:]
    for (key, value) in command.environmentUpdates {
        environment[key] = value
    }
    return environment
}

private func resolveExecutable(
    _ executable: String,
    environment: [String: String],
    workingDirectory: URL?
) throws -> URL {
    let currentDirectory = workingDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    if executable.contains("/") {
        let url = executable.hasPrefix("/")
            ? URL(fileURLWithPath: executable)
            : currentDirectory.appendingPathComponent(executable)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw CommandError.executableNotFound(executable)
        }
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }
    for directory in environment["PATH", default: ""]
        .split(separator: ":", omittingEmptySubsequences: false)
    {
        let base = directory.isEmpty
            ? currentDirectory
            : URL(fileURLWithPath: String(directory), relativeTo: currentDirectory)
        let url = base.appendingPathComponent(executable)
        if FileManager.default.isExecutableFile(atPath: url.path) {
            return url.standardizedFileURL.resolvingSymlinksInPath()
        }
    }
    throw CommandError.executableNotFound(executable)
}

private func termination(of process: Process) -> Termination {
    if process.terminationReason == .uncaughtSignal {
        return .signaled(process.terminationStatus)
    }
    return .exited(process.terminationStatus)
}

private func forceTerminate(_ processes: [Process]) {
    for process in processes where process.isRunning {
        process.terminate()
        _ = kill(process.processIdentifier, SIGKILL)
    }
}

private func close(_ handles: [FileHandle]) {
    for handle in handles {
        try? handle.close()
    }
}

private func trimmingTrailingNewlines(_ value: String) -> String {
    var value = value
    while value.last == "\n" || value.last == "\r" {
        value.removeLast()
    }
    return value
}

private func decodeUTF8(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self) // swiftlint:disable:this optional_data_string_conversion
}

private func splitLines(_ value: String) -> [String] {
    guard !value.isEmpty else {
        return []
    }
    return value.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
}

private func renderArgument(_ argument: String) -> String {
    guard !argument.isEmpty else {
        return "''"
    }
    let safe = argument.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0) || "_@%+=:,./-".unicodeScalars.contains($0)
    }
    return safe ? argument : quoteForShell(argument)
}

private func quoteForShell(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}
