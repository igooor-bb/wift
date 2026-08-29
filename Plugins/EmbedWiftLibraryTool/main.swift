import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("usage: EmbedWiftLibraryTool <input> <output>")
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let bytes = try Data(contentsOf: input).map(String.init).joined(separator: ",")
let generated = """
enum EmbeddedWiftLibrarySource {
    static let bytes: [UInt8] = [\(bytes)]
}

"""
try Data(generated.utf8).write(to: output, options: .atomic)
