import Foundation

guard CommandLine.arguments.count == 4 else {
    fatalError("usage: EmbedWiftLibraryTool <library-input> <version-input> <output>")
}

let libraryInput = URL(fileURLWithPath: CommandLine.arguments[1])
let versionInput = URL(fileURLWithPath: CommandLine.arguments[2])
let output = URL(fileURLWithPath: CommandLine.arguments[3])
let libraryBytes = try Data(contentsOf: libraryInput).map(String.init).joined(separator: ",")
let versionContents = try String(contentsOf: versionInput, encoding: .utf8)
let version = versionContents.trimmingCharacters(in: .whitespacesAndNewlines)
let semanticVersionPattern = #"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"#
guard !version.isEmpty,
      versionContents == version || versionContents == "\(version)\n" || versionContents == "\(version)\r\n",
      version.range(of: semanticVersionPattern, options: .regularExpression) != nil
else {
    fatalError("VERSION must contain one semantic version such as 0.1.0")
}

let generated = """
enum EmbeddedWiftLibrarySource {
    static let bytes: [UInt8] = [\(libraryBytes)]
}

enum WiftVersion {
    static let current = "\(version)"
}

"""
try Data(generated.utf8).write(to: output, options: .atomic)
