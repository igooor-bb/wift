import Foundation

// Direct POSIX calls are intentional. Toolchain resolution is a synchronous startup hot path,
// while swift-subprocess exposes an async API and adds a swift-system dependency. Keeping this
// layer dependency-free also lets us reuse the mechanism in the source-embedded WiftLibrary.

struct ProcessOutput {
    let standardOutput: Data
    let standardError: Data
    let exitCode: Int32
}

enum ProcessExecution {
    static func capture(
        executable: String,
        arguments: [String]
    ) throws -> ProcessOutput {
        var capture = try ProcessCapture()
        let processID = try POSIXProcess.spawn(
            executable: executable,
            arguments: arguments,
            capture: capture
        )
        capture.closeWriteEnds()
        do {
            let output = try capture.read()
            return try ProcessOutput(
                standardOutput: output.standardOutput,
                standardError: output.standardError,
                exitCode: POSIXProcess.wait(for: processID, executable: executable)
            )
        } catch {
            capture.closeReadEnds()
            _ = try? POSIXProcess.wait(for: processID, executable: executable)
            throw error
        }
    }
}
