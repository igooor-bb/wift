import Foundation

struct CompilerFailure: Error {
    let exitCode: Int32
}

struct SwiftCompiler {
    let toolchain: Toolchain

    func compile(
        script: Script,
        compilerArguments: [String],
        outputURL: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolchain.compilerPath)
        process.arguments = compilerArguments + [script.path, "-o", outputURL.path]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            throw WiftError("unable to run swiftc: \(error.localizedDescription)")
        }

        process.waitUntilExit()
        let exitCode: Int32 = if process.terminationReason == .uncaughtSignal {
            128 + process.terminationStatus
        } else {
            process.terminationStatus
        }
        guard exitCode == 0 else {
            throw CompilerFailure(exitCode: exitCode)
        }
    }
}
