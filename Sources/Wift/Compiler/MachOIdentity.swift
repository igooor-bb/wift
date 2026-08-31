import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct MachOIdentity: Equatable {
    private static let headerSize = 32
    private static let maximumLoadCommandsSize = 1024 * 1024
    private static let magic64: UInt32 = 0xFEED_FACF
    private static let uuidCommand: UInt32 = 0x1B
    private static let sourceVersionCommand: UInt32 = 0x2A

    let uuid: String
    let sourceVersion: UInt64?

    static func read(from url: URL) -> MachOIdentity? {
        let descriptor = url.path.withCString { path in
            open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            return nil
        }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG
        else {
            close(descriptor)
            return nil
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

        guard let header = try? handle.read(upToCount: headerSize),
              header.count == headerSize,
              uint32(in: header, at: 0) == magic64,
              let commandsSize = uint32(in: header, at: 20),
              commandsSize <= maximumLoadCommandsSize,
              let commands = try? handle.read(upToCount: Int(commandsSize)),
              commands.count == Int(commandsSize)
        else {
            return nil
        }
        return parseLoadCommands(commands)
    }

    private static func parseLoadCommands(_ data: Data) -> MachOIdentity? {
        var offset = 0
        var uuid: String?
        var sourceVersion: UInt64?

        while offset < data.count {
            guard let command = uint32(in: data, at: offset),
                  let commandSize = uint32(in: data, at: offset + 4),
                  commandSize >= 8,
                  Int(commandSize) <= data.count - offset
            else {
                return nil
            }

            switch command {
            case uuidCommand where commandSize >= 24:
                uuid = data[(offset + 8) ..< (offset + 24)]
                    .map { String(format: "%02x", $0) }
                    .joined()

            case sourceVersionCommand where commandSize >= 16:
                sourceVersion = uint64(in: data, at: offset + 8)

            default:
                break
            }
            offset += Int(commandSize)
        }

        guard offset == data.count, let uuid else {
            return nil
        }
        return MachOIdentity(uuid: uuid, sourceVersion: sourceVersion)
    }

    private static func uint32(in data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - MemoryLayout<UInt32>.size else {
            return nil
        }
        return data.withUnsafeBytes { bytes in
            UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }

    private static func uint64(in data: Data, at offset: Int) -> UInt64? {
        guard offset >= 0, offset <= data.count - MemoryLayout<UInt64>.size else {
            return nil
        }
        return data.withUnsafeBytes { bytes in
            UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
        }
    }
}
