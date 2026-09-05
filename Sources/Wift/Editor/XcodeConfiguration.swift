import Foundation
import XcodeProj

extension EditorConfiguration {
    func xcodeFiles() throws -> [String: Data] {
        // Xcode expands build-setting expressions even in some path fields. Refuse these
        // spellings rather than silently index a different file or compiler installation.
        for path in [scriptPath, module.directory.path, toolchain.sdkPath ?? "", swiftDirectory] {
            guard !path.contains("$("), !path.contains("${"), !path.contains("\n"), !path.contains("\r") else {
                throw WiftError("Xcode edit does not support build-setting expressions or newlines in paths; use VS Code")
            }
        }
        guard let platform = toolchain.target.range(of: "-apple-macos") else {
            throw WiftError("Xcode edit requires a macOS toolchain")
        }
        let version = String(toolchain.target[platform.upperBound...]).replacingOccurrences(of: "x", with: "")
        let architecture = String(toolchain.target[..<platform.lowerBound])
        let settings: BuildSettings = [
            "PRODUCT_NAME": "Script",
            "SDKROOT": .string(toolchain.sdkPath ?? "macosx"),
            "ARCHS": .string(architecture),
            "MACOSX_DEPLOYMENT_TARGET": .string(version),
            "SWIFT_VERSION": "5.0", // swiftc's default language mode, as used by the runner.
            "SWIFT_EXEC": .string(swiftDirectory + "/swiftc"),
            "SWIFT_INCLUDE_PATHS": [quotedBuildPath(module.directory.path)],
            "OTHER_LDFLAGS": [quotedBuildPath(module.objectURL.path)],
            "SWIFT_DISABLE_PARSE_AS_LIBRARY": "YES",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
            "CODE_SIGNING_ALLOWED": "NO",
            "ALWAYS_SEARCH_USER_PATHS": "NO",
        ]
        let source = PBXFileReference(
            sourceTree: .absolute, name: URL(fileURLWithPath: scriptPath).lastPathComponent,
            lastKnownFileType: "sourcecode.swift", path: scriptPath
        )
        let product = PBXFileReference(sourceTree: .buildProductsDir, explicitFileType: "compiled.mach-o.executable", path: "Script")
        let products = PBXGroup(children: [product], sourceTree: .group, name: "Products")
        let group = PBXGroup(children: [source, products], sourceTree: .group)
        let buildFile = PBXBuildFile(file: source)
        let phase = PBXSourcesBuildPhase(files: [buildFile])
        let targetConfiguration = XCBuildConfiguration(name: "Debug", buildSettings: settings)
        let targetConfigurations = XCConfigurationList(buildConfigurations: [targetConfiguration], defaultConfigurationName: "Debug")
        let projectConfiguration = XCBuildConfiguration(name: "Debug")
        let projectConfigurations = XCConfigurationList(buildConfigurations: [projectConfiguration], defaultConfigurationName: "Debug")
        let target = PBXNativeTarget(
            name: "Script", buildConfigurationList: targetConfigurations, buildPhases: [phase],
            productName: "Script", product: product, productType: .commandLineTool
        )
        let project = PBXProject(
            name: "Script", buildConfigurationList: projectConfigurations, compatibilityVersion: "Xcode 14.0",
            preferredProjectObjectVersion: nil, minimizedProjectReferenceProxies: nil,
            mainGroup: group, developmentRegion: "en", knownRegions: ["en"], productsGroup: products, targets: [target]
        )
        let document = PBXProj(rootObject: project, objectVersion: 56, objects: [
            project, group, products, source, product, buildFile, phase, target,
            targetConfiguration, targetConfigurations, projectConfiguration, projectConfigurations,
        ])
        guard let data = try document.dataRepresentation() else { throw WiftError("unable to encode Xcode project") }
        return ["Script.xcodeproj/project.pbxproj": data]
    }

    private func quotedBuildPath(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
