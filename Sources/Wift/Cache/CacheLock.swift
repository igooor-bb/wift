import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct CacheLock: ~Copyable {
    enum Mode {
        case shared
        case exclusive

        var operation: Int32 {
            switch self {
            case .shared:
                LOCK_SH

            case .exclusive:
                LOCK_EX
            }
        }
    }

    private var fileDescriptor: Int32 = -1

    init(
        url: URL,
        mode: Mode = .exclusive,
        onContention: () -> Void = {}
    ) throws {
        let descriptor = url.path.withCString { path in
            open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw WiftError("unable to open cache lock: \(Self.currentErrorDescription())")
        }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_uid == geteuid(),
              status.st_mode & S_IFMT == S_IFREG,
              status.st_mode & (S_IWGRP | S_IWOTH) == 0
        else {
            close(descriptor)
            throw WiftError("cache lock is not an owner-controlled regular file")
        }
        let immediateResult = flock(descriptor, mode.operation | LOCK_NB)
        if immediateResult != 0, errno == EWOULDBLOCK || errno == EAGAIN {
            onContention()
            guard flock(descriptor, mode.operation) == 0 else {
                let description = Self.currentErrorDescription()
                close(descriptor)
                throw WiftError("unable to acquire cache lock: \(description)")
            }
        } else if immediateResult != 0 {
            let description = Self.currentErrorDescription()
            close(descriptor)
            throw WiftError("unable to acquire cache lock: \(description)")
        }
        fileDescriptor = descriptor
    }

    deinit {
        if fileDescriptor >= 0 {
            flock(fileDescriptor, LOCK_UN)
            close(fileDescriptor)
        }
    }

    borrowing func whileHeld<T>(_ body: () throws -> T) rethrows -> T {
        try body()
    }

    private static func currentErrorDescription() -> String {
        String(cString: strerror(errno))
    }
}
