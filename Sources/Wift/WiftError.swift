import Foundation

struct WiftError: Error, CustomStringConvertible {
    let description: String
    let exitCode: Int32

    init(_ description: String, exitCode: Int32 = 1) {
        self.description = description
        self.exitCode = exitCode
    }
}
