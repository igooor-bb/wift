import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

enum Exec {
    static func replaceCurrentProcess(
        executable: URL,
        scriptPath: String,
        arguments: [String]
    ) throws -> Never {
        let commandLine = [scriptPath] + arguments
        var allocatedArguments = commandLine.map { strdup($0) }
        guard allocatedArguments.allSatisfy({ $0 != nil }) else {
            for pointer in allocatedArguments {
                free(pointer)
            }
            throw WiftError("unable to allocate arguments for cached binary")
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

        throw WiftError("failed to execute cached binary: \(String(cString: strerror(errno)))", exitCode: 126)
    }
}
