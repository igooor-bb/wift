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
        let stagedSourceURL: URL? = if script.needsStagedSwiftSource {
            outputURL.deletingLastPathComponent().appendingPathComponent("script.swift", isDirectory: false)
        } else {
            nil
        }
        if let stagedSourceURL {
            do {
                try script.contents.write(to: stagedSourceURL, options: .atomic)
            } catch {
                throw WiftError("unable to stage script source: \(error.localizedDescription)")
            }
        }
        defer {
            if let stagedSourceURL {
                try? FileManager.default.removeItem(at: stagedSourceURL)
            }
        }

        let sourcePath = stagedSourceURL?.path ?? script.path
        try invoke(arguments: compilerArguments + [sourcePath, "-o", outputURL.path])
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

    private func invoke(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolchain.compilerPath)
        process.arguments = arguments
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
