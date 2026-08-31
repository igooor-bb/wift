import Foundation
import Testing
@testable import Wift

struct ProcessExecutionTests {
    @Test func capturesOutputAndExitCode() throws {
        let output = try ProcessExecution.capture(
            executable: "/bin/sh",
            arguments: ["-c", "printf stdout; printf stderr >&2; exit 7"]
        )

        #expect(output.standardOutput == Data("stdout".utf8))
        #expect(output.standardError == Data("stderr".utf8))
        #expect(output.exitCode == 7)
    }

    @Test func drainsStandardOutputAndErrorConcurrently() throws {
        let byteCount = 256 * 1024
        let output = try ProcessExecution.capture(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "dd if=/dev/zero bs=\(byteCount) count=1 2>/dev/null; "
                    + "dd if=/dev/zero bs=\(byteCount) count=1 >&2 2>/dev/null",
            ]
        )

        #expect(output.standardOutput.count == byteCount)
        #expect(output.standardError.count == byteCount)
        #expect(output.exitCode == 0)
    }
}
