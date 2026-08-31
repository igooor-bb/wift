import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct ProcessCapture: ~Copyable {
    private var standardOutput: CapturePipe
    private var standardError: CapturePipe

    init() throws {
        let standardOutput = try CapturePipe()
        let standardError = try CapturePipe()
        self.standardOutput = consume standardOutput
        self.standardError = consume standardError
    }

    var standardOutputReadEnd: Int32 {
        standardOutput.readEnd
    }

    var standardOutputWriteEnd: Int32 {
        standardOutput.writeEnd
    }

    var standardErrorReadEnd: Int32 {
        standardError.readEnd
    }

    var standardErrorWriteEnd: Int32 {
        standardError.writeEnd
    }

    mutating func closeWriteEnds() {
        standardOutput.closeWriteEnd()
        standardError.closeWriteEnd()
    }

    mutating func closeReadEnds() {
        standardOutput.closeReadEnd()
        standardError.closeReadEnd()
    }

    mutating func read() throws -> (standardOutput: Data, standardError: Data) {
        var output = Data()
        var error = Data()
        while standardOutput.hasReadEnd || standardError.hasReadEnd {
            var descriptors = [
                pollfd(fd: standardOutput.readEnd, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0),
                pollfd(fd: standardError.readEnd, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0),
            ]
            let result = descriptors.withUnsafeMutableBufferPointer { buffer in
                poll(buffer.baseAddress!, nfds_t(buffer.count), -1)
            }
            if result == -1 {
                guard errno == EINTR else {
                    throw WiftError("unable to read process output: \(errorDescription(errno))")
                }
                continue
            }
            if descriptors[0].revents != 0 {
                try standardOutput.readAvailable(into: &output, streamName: "standard output")
            }
            if descriptors[1].revents != 0 {
                try standardError.readAvailable(into: &error, streamName: "standard error")
            }
        }
        return (output, error)
    }
}

private struct CapturePipe: ~Copyable {
    private(set) var readEnd: Int32 = -1
    private(set) var writeEnd: Int32 = -1

    init() throws {
        var descriptors = [Int32](repeating: -1, count: 2)
        let result = descriptors.withUnsafeMutableBufferPointer { buffer in
            pipe(buffer.baseAddress!)
        }
        guard result == 0 else {
            throw WiftError("unable to create process output pipe: \(errorDescription(errno))")
        }
        do {
            readEnd = try prepare(descriptors[0], nonBlocking: true)
            descriptors[0] = -1
            writeEnd = try prepare(descriptors[1], nonBlocking: false)
            descriptors[1] = -1
        } catch {
            descriptors.filter { $0 >= 0 }.forEach { close($0) }
            if readEnd >= 0 {
                close(readEnd)
                readEnd = -1
            }
            throw error
        }
    }

    deinit {
        if readEnd >= 0 {
            close(readEnd)
        }
        if writeEnd >= 0 {
            close(writeEnd)
        }
    }

    var hasReadEnd: Bool {
        readEnd >= 0
    }

    mutating func closeWriteEnd() {
        if writeEnd >= 0 {
            close(writeEnd)
            writeEnd = -1
        }
    }

    mutating func closeReadEnd() {
        if readEnd >= 0 {
            close(readEnd)
            readEnd = -1
        }
    }

    mutating func readAvailable(into data: inout Data, streamName: String) throws {
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                systemRead(readEnd, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                buffer.withUnsafeBytes { bytes in
                    data.append(bytes.bindMemory(to: UInt8.self).baseAddress!, count: count)
                }
            } else if count == 0 {
                closeReadEnd()
                return
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else if errno != EINTR {
                throw WiftError("unable to read process \(streamName): \(errorDescription(errno))")
            }
        }
    }

    private func prepare(_ descriptor: Int32, nonBlocking: Bool) throws -> Int32 {
        let ownedDescriptor: Int32
        let closesOriginal: Bool
        if descriptor <= STDERR_FILENO {
            ownedDescriptor = fcntl(descriptor, F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
            closesOriginal = true
            guard ownedDescriptor >= 0 else {
                throw WiftError("unable to configure process output pipe: \(errorDescription(errno))")
            }
        } else {
            ownedDescriptor = descriptor
            closesOriginal = false
            guard fcntl(ownedDescriptor, F_SETFD, FD_CLOEXEC) == 0 else {
                throw WiftError("unable to configure process output pipe: \(errorDescription(errno))")
            }
        }

        if nonBlocking {
            let flags = fcntl(ownedDescriptor, F_GETFL)
            guard flags >= 0, fcntl(ownedDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                if closesOriginal {
                    close(ownedDescriptor)
                }
                throw WiftError("unable to configure process output pipe: \(errorDescription(errno))")
            }
        }
        if closesOriginal {
            close(descriptor)
        }
        return ownedDescriptor
    }

    private func systemRead(
        _ descriptor: Int32,
        _ buffer: UnsafeMutableRawPointer?,
        _ count: Int
    ) -> Int {
        #if canImport(Darwin)
            Darwin.read(descriptor, buffer, count)
        #elseif canImport(Glibc)
            Glibc.read(descriptor, buffer, count)
        #endif
    }
}

private func errorDescription(_ error: Int32) -> String {
    String(cString: strerror(error))
}
