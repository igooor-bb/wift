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
        guard let version = String(data: versionOutput.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty
        else {
            throw WiftError("unable to decode swiftc version")
        }

        guard let targetLine = version.split(separator: "\n").first(where: { $0.hasPrefix("Target: ") }) else {
            throw WiftError("unable to resolve Swift target information")
        }
        let target = targetLine.dropFirst("Target: ".count).trimmingCharacters(in: .whitespaces)
        let sdkPath = resolveSDKPath(environment: environment)

        return Toolchain(
            compilerPath: compilerPath,
            compilerVersion: version,
            target: target,
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

    private static func resolveSDKPath(environment: [String: String]) -> String? {
        #if os(macOS)
            if let sdkRoot = environment["SDKROOT"], !sdkRoot.isEmpty {
                return URL(fileURLWithPath: sdkRoot).standardizedFileURL.resolvingSymlinksInPath().path
            }
            guard let output = try? ProcessExecution.capture(
                executable: "/usr/bin/xcrun",
                arguments: ["--sdk", "macosx", "--show-sdk-path"]
            ), output.exitCode == 0 else {
                return nil
            }

            guard let path = String(data: output.standardOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                return nil
            }
            return path.isEmpty ? nil : path
        #else
            return nil
        #endif
    }
}
