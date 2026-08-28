import Foundation
import Testing
@testable import Wift

struct DiagnosticsTests {
    @Test func prefixesVerboseMessages() throws {
        try withTemporaryDirectory { directory in
            let output = directory.appendingPathComponent("stderr")
            try Data().write(to: output)
            let fileHandle = try FileHandle(forWritingTo: output)
            defer { try? fileHandle.close() }

            Diagnostics(isVerbose: true, standardError: fileHandle).log("cache hit")
            try fileHandle.synchronize()

            #expect(try String(contentsOf: output, encoding: .utf8) == "wift: cache hit\n")
        }
    }

    @Test func staysSilentWhenDisabled() throws {
        try withTemporaryDirectory { directory in
            let output = directory.appendingPathComponent("stderr")
            try Data().write(to: output)
            let fileHandle = try FileHandle(forWritingTo: output)
            defer { try? fileHandle.close() }

            Diagnostics(isVerbose: false, standardError: fileHandle).log("cache hit")
            try fileHandle.synchronize()

            #expect(try Data(contentsOf: output).isEmpty)
        }
    }
}
