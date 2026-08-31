#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

enum POSIXProcess {
    static func spawn(
        executable: String,
        arguments: [String],
        capture: borrowing ProcessCapture
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        var result = posix_spawn_file_actions_init(&fileActions)
        guard result == 0 else {
            throw WiftError("unable to configure process launch: \(errorDescription(result))")
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        try redirect(
            readEnd: capture.standardOutputReadEnd,
            writeEnd: capture.standardOutputWriteEnd,
            to: STDOUT_FILENO,
            fileActions: &fileActions
        )
        try redirect(
            readEnd: capture.standardErrorReadEnd,
            writeEnd: capture.standardErrorWriteEnd,
            to: STDERR_FILENO,
            fileActions: &fileActions
        )

        var processID: pid_t = 0
        result = try withCStringArray([executable] + arguments) { argumentPointers in
            executable.withCString { executablePath in
                posix_spawn(
                    &processID,
                    executablePath,
                    &fileActions,
                    nil,
                    argumentPointers,
                    environ
                )
            }
        }
        guard result == 0 else {
            throw WiftError("unable to run \(executable): \(errorDescription(result))")
        }
        return processID
    }

    static func wait(for processID: pid_t, executable: String) throws -> Int32 {
        var status: Int32 = 0
        while waitpid(processID, &status, 0) == -1 {
            guard errno == EINTR else {
                throw WiftError("unable to wait for \(executable): \(errorDescription(errno))")
            }
        }
        return if status & 0x7F == 0 {
            (status >> 8) & 0xFF
        } else {
            status & 0x7F
        }
    }

    private static func redirect(
        readEnd: Int32,
        writeEnd: Int32,
        to destination: Int32,
        fileActions: inout posix_spawn_file_actions_t?
    ) throws {
        for result in [
            posix_spawn_file_actions_adddup2(&fileActions, writeEnd, destination),
            posix_spawn_file_actions_addclose(&fileActions, readEnd),
            posix_spawn_file_actions_addclose(&fileActions, writeEnd),
        ] where result != 0 {
            throw WiftError("unable to configure process output: \(errorDescription(result))")
        }
    }

    private static func withCStringArray<T>(
        _ strings: [String],
        body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> T
    ) throws -> T {
        var pointers = strings.map { strdup($0) }
        guard pointers.allSatisfy({ $0 != nil }) else {
            pointers.forEach { free($0) }
            throw WiftError("unable to allocate process arguments")
        }
        pointers.append(nil)
        defer { pointers.forEach { free($0) } }
        return try pointers.withUnsafeMutableBufferPointer { buffer in
            try body(buffer.baseAddress!)
        }
    }

    private static func errorDescription(_ error: Int32) -> String {
        String(cString: strerror(error))
    }
}
