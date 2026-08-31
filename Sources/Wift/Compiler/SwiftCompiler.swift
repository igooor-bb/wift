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
        let stagingDirectory = outputURL.deletingLastPathComponent()
        let stagedSourceURL = stagingDirectory.appendingPathComponent("script.swift", isDirectory: false)
        do {
            try script.contents.write(to: stagedSourceURL, options: .atomic)
        } catch {
            throw WiftError("unable to stage script source: \(error.localizedDescription)")
        }
        defer {
            try? FileManager.default.removeItem(at: stagedSourceURL)
        }

        try invoke(
            arguments: compilerArguments + ["script.swift", "-o", outputURL.path],
            currentDirectoryURL: stagingDirectory
        )
    }

    func compileSupportModule(_ module: SupportModule) throws {
        try invoke(
            arguments: module.compilerArguments + [
                "-emit-module-path",
                module.moduleURL.path,
                module.sourceURL.path,
                "-o",
                module.objectURL.path,
            ]
        )
    }

    private func invoke(arguments: [String], currentDirectoryURL: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolchain.compilerPath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
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
