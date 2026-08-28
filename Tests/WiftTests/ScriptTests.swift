import Foundation
import Testing
@testable import Wift

struct ScriptTests {
    @Test func resolvesSymlinksToTheSameCanonicalPath() throws {
        try withTemporaryDirectory { directory in
            let scriptURL = directory.appendingPathComponent("script.swift")
            let symlinkURL = directory.appendingPathComponent("alias.swift")
            try Data("print(\"hello\")".utf8).write(to: scriptURL)
            try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: scriptURL)

            let direct = try Script.resolve(scriptURL.path)
            let throughSymlink = try Script.resolve(symlinkURL.path)

            #expect(direct == throughSymlink)
        }
    }
}
