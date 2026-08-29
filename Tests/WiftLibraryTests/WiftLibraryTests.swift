import Darwin
import Foundation
import Testing
@testable import WiftLibrary

@Suite(.serialized)
struct WiftLibraryTests {
    @Test func runsChecksAndCapturesCommands() throws {
        #expect(try cmd("/bin/echo", "hello").text() == "hello")
        #expect(try cmd("/bin/sh", "-c", "exit 9").status() == .exited(9))

        do {
            try cmd("/bin/sh", "-c", "exit 7").run()
            Issue.record("checked run unexpectedly succeeded")
        } catch let CommandError.unsuccessful(_, result) {
            #expect(result.termination == .exited(7))
        }

        let result = try cmd(
            "/bin/sh",
            "-c",
            "printf 'out\n\n'; printf 'err\n' >&2; exit 3"
        ).result()
        #expect(result.termination == .exited(3))
        #expect(result.stdoutText == "out\n\n")
        #expect(result.stderrText == "err\n")
    }

    @Test func configuresInputEnvironmentDirectoryAndFiles() throws {
        try withTemporaryDirectory { directory in
            let lines = try cmd("/bin/cat")
                .input(.string("b\na\n"))
                .pipe(to: cmd("/usr/bin/sort"))
                .lines()
            #expect(lines == ["a", "b"])

            let environment = try cmd("/usr/bin/env")
                .environment(["WIFT_VALUE": "visible"])
                .pipe(to: cmd("/usr/bin/grep", "^WIFT_VALUE="))
                .text()
            #expect(environment == "WIFT_VALUE=visible")

            let marker = directory.appendingPathComponent("marker")
            try Data().write(to: marker)
            try cmd("/bin/test", "-f", "marker")
                .inDirectory(directory)
                .run()

            let output = directory.appendingPathComponent("output")
            try cmd("/bin/echo", "first").output(.file(output)).run()
            try cmd("/bin/echo", "second").output(.file(output, append: true)).run()
            #expect(try String(contentsOf: output, encoding: .utf8) == "first\nsecond\n")
        }
    }

    @Test func pipelinesUsePipefailAndShellInterpolationIsQuoted() throws {
        do {
            try cmd("/bin/sh", "-c", "exit 7")
                .pipe(to: cmd("/usr/bin/true"))
                .run()
            Issue.record("pipefail unexpectedly succeeded")
        } catch let CommandError.pipelineFailed(_, result) {
            #expect(result.stages.map(\.termination) == [.exited(7), .exited(0)])
        }

        let value = "; printf injected"
        #expect(try shell("printf '%s\n' \(value)").text() == value)
        #expect(try cmd("/usr/bin/printf", "%s", value).text() == value)

        let merged = try cmd(
            "/bin/sh",
            "-c",
            "printf out; printf err >&2"
        )
        .error(.mergedWithStandardOutput)
        .result()
        #expect(merged.stdoutText == "outerr")
        #expect(merged.stderr.isEmpty)
    }

    @Test func captureIsConcurrentAndBounded() throws {
        let result = try cmd(
            "/bin/sh",
            "-c",
            "yes o | head -c 200000 & yes e | head -c 200000 >&2 & wait"
        ).result()
        #expect(result.stdout.count == 200_000)
        #expect(result.stderr.count == 200_000)

        do {
            _ = try cmd("/usr/bin/printf", "12345").result(limit: .bytes(4))
            Issue.record("bounded capture unexpectedly succeeded")
        } catch let CommandError.outputLimitExceeded(_, stream, limit) {
            #expect(stream == .stdout)
            #expect(limit == 4)
        }
    }

    @Test func streamsLinesAsynchronously() async throws {
        var lines: [String] = []
        let producer = cmd(
            "/bin/sh",
            "-c",
            "printf 'one\\ntwo\\n\\nthree\\r\\n'; printf '\\316'; printf '\\261\\nlast'"
        )
        for try await line in producer.streamLines() {
            lines.append(line)
        }
        #expect(lines == ["one", "two", "", "three", "α", "last"])
    }

    @Test func cancellationTerminatesAndReapsChild() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("pid")
        let task = Task {
            try await shell("echo $$ > \(marker.path); trap '' TERM; while :; do :; done").run()
        }

        while (try? Data(contentsOf: marker).isEmpty) != false {
            await Task.yield()
        }
        task.cancel()

        do {
            try await task.value
            Issue.record("cancelled command unexpectedly succeeded")
        } catch is CancellationError {
            // Expected.
        }

        let contents = try String(contentsOf: marker, encoding: .utf8)
        let identifier = try #require(pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(identifier, 0) == -1)
        #expect(errno == ESRCH)
    }
}

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("wift-library-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    return directory
}
