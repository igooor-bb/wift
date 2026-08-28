import Foundation

struct Toolchain: Equatable {
    let compilerPath: String
    let compilerVersion: String
    let target: String
    let sdkPath: String?

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Toolchain {
        guard let compilerPath = ExecutableLookup.find("swiftc", environment: environment) else {
            throw WiftError("unable to locate swiftc")
        }

        let versionOutput = try ProcessExecution.capture(executable: compilerPath, arguments: ["--version"])
        guard versionOutput.exitCode == 0 else {
            throw WiftError("unable to identify swiftc")
        }
        let version = String(decoding: versionOutput.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let sdkPath = resolveSDKPath()
        var targetArguments = ["-print-target-info"]
        if let sdkPath {
            targetArguments += ["-sdk", sdkPath]
        }
        let targetOutput = try ProcessExecution.capture(executable: compilerPath, arguments: targetArguments)
        guard targetOutput.exitCode == 0 else {
            throw WiftError("unable to resolve Swift target information")
        }

        let targetInfo: TargetInfo
        do {
            targetInfo = try JSONDecoder().decode(TargetInfo.self, from: targetOutput.standardOutput)
        } catch {
            throw WiftError("unable to decode Swift target information: \(error.localizedDescription)")
        }

        return Toolchain(
            compilerPath: compilerPath,
            compilerVersion: version,
            target: targetInfo.target.triple,
            sdkPath: sdkPath
        )
    }

    func compilerArguments(moduleCachePath: String) -> [String] {
        var arguments = ["-module-cache-path", moduleCachePath]
        if let sdkPath {
            arguments += ["-sdk", sdkPath]
        }
        return arguments
    }

    private static func resolveSDKPath() -> String? {
        #if os(macOS)
            guard let output = try? ProcessExecution.capture(
                executable: "/usr/bin/xcrun",
                arguments: ["--sdk", "macosx", "--show-sdk-path"]
            ), output.exitCode == 0 else {
                return nil
            }

            let path = String(decoding: output.standardOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        #else
            return nil
        #endif
    }
}

private struct TargetInfo: Decodable {
    struct Target: Decodable {
        let triple: String
    }

    let target: Target
}
