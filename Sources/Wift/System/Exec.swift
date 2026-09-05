import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

enum Exec {
    static func replaceCurrentProcess(
        executable: URL,
        argumentZero: String,
        arguments: [String]
    ) throws -> Never {
        let commandLine = [argumentZero] + arguments
        var allocatedArguments = commandLine.map { strdup($0) }
        guard allocatedArguments.allSatisfy({ $0 != nil }) else {
            for pointer in allocatedArguments {
                free(pointer)
            }
            throw WiftError("unable to allocate arguments for executable")
        }
        allocatedArguments.append(nil)
        defer {
            for pointer in allocatedArguments {
                free(pointer)
            }
        }

        let result = executable.path.withCString { executablePath in
            allocatedArguments.withUnsafeMutableBufferPointer { buffer in
                execv(executablePath, buffer.baseAddress!)
            }
        }
        assert(result == -1)

        throw WiftError("failed to execute \(executable.path): \(String(cString: strerror(errno)))", exitCode: 126)
    }
}
