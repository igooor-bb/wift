import Foundation

struct ModuleCacheContext: Equatable {
    let arguments: [String]
}

struct Toolchain: Equatable {
    let compilerPath: String
    let compilerVersion: String
    let target: String
    let sdkPath: String?

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cache: Cache,
        dependencies: ToolchainResolutionDependencies = .live
    ) throws -> Toolchain {
        guard let compilerPath = dependencies.findExecutable("swiftc", environment) else {
            throw WiftError("unable to locate swiftc")
        }

        let sdkPath = resolveSDKPath(environment: environment, capture: dependencies.capture)
        guard let signature = ToolchainInstallationSignature.resolve(
            compilerPath: compilerPath,
            sdkPath: sdkPath,
            environment: environment,
            dependencies: dependencies
        ) else {
            return try identify(
                compilerPath: compilerPath,
                sdkPath: sdkPath,
                capture: dependencies.capture
            )
        }

        return try ToolchainResolutionCache(cache: cache).resolve(
            signature: signature,
            compilerPath: compilerPath,
            sdkPath: sdkPath
        ) {
            try identify(
                compilerPath: compilerPath,
                sdkPath: sdkPath,
                capture: dependencies.capture
            )
        }
    }

    private static func identify(
        compilerPath: String,
        sdkPath: String?,
        capture: (String, [String]) throws -> ProcessOutput
    ) throws -> Toolchain {
        let versionOutput = try capture(compilerPath, ["--version"])
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
        return Toolchain(
            compilerPath: compilerPath,
            compilerVersion: version,
            target: target,
            sdkPath: sdkPath
        )
    }

    func moduleCacheContext(moduleCachePath: String) -> ModuleCacheContext {
        var arguments = [
            "-module-cache-path",
            moduleCachePath,
            "-target",
            target,
        ]
        if let sdkPath {
            arguments += ["-sdk", sdkPath]
        }
        return ModuleCacheContext(arguments: arguments)
    }

    private static func resolveSDKPath(
        environment: [String: String],
        capture: (String, [String]) throws -> ProcessOutput
    ) -> String? {
        #if os(macOS)
            if let sdkRoot = environment["SDKROOT"], !sdkRoot.isEmpty {
                return URL(fileURLWithPath: sdkRoot).standardizedFileURL.resolvingSymlinksInPath().path
            }
            guard let output = try? capture("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-path"]),
                  output.exitCode == 0
            else {
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
