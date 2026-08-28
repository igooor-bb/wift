import Foundation

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
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw WiftError("unable to run \(executable): \(error.localizedDescription)")
        }

        process.waitUntilExit()
        return ProcessOutput(
            standardOutput: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            standardError: standardError.fileHandleForReading.readDataToEndOfFile(),
            exitCode: process.terminationStatus
        )
    }
}
