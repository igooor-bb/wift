import Foundation

struct Diagnostics {
    let isVerbose: Bool
    private let standardError: FileHandle

    init(
        isVerbose: Bool,
        standardError: FileHandle = .standardError
    ) {
        self.isVerbose = isVerbose
        self.standardError = standardError
    }

    func log(_ message: String) {
        guard isVerbose else {
            return
        }
        standardError.write(Data("wift: \(message)\n".utf8))
    }
}
