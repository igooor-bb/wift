import Darwin
import Foundation

struct BenchmarkCommand: Sendable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]

    init(
        executable: String,
        arguments: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

struct ProcessMeasurement: Sendable {
    let exitCode: Int32
    let peakResidentBytes: UInt64
}

enum ProcessRunnerError: Error, CustomStringConvertible {
    case fileActions(Int32)
    case spawn(executable: String, error: Int32)
    case wait(error: Int32)
    case unsuccessful(executable: String, exitCode: Int32)

    var description: String {
        switch self {
        case let .fileActions(error):
            "unable to configure process file actions: \(errorDescription(error))"

        case let .spawn(executable, error):
            "unable to launch \(executable): \(errorDescription(error))"

        case let .wait(error):
            "unable to wait for process: \(errorDescription(error))"

        case let .unsuccessful(executable, exitCode):
            "\(executable) exited with status \(exitCode)"
        }
    }

    private func errorDescription(_ error: Int32) -> String {
        String(cString: strerror(error))
    }
}

struct ProcessRunner {
    @discardableResult
    func run(_ command: BenchmarkCommand, measurePeakRSS: Bool = false) throws -> ProcessMeasurement {
        let pid = try spawn(command)
        let sampler = measurePeakRSS ? PeakResidentMemorySampler(processIDs: [pid]) : nil
        sampler?.start()
        let measurement = try wait(for: pid)
        let sampledPeak = sampler?.stop() ?? 0
        let peakResidentBytes = max(measurement.peakResidentBytes, sampledPeak)
        guard measurement.exitCode == 0 else {
            throw ProcessRunnerError.unsuccessful(
                executable: command.executable,
                exitCode: measurement.exitCode
            )
        }
        return ProcessMeasurement(exitCode: measurement.exitCode, peakResidentBytes: peakResidentBytes)
    }

    func runConcurrently(_ commands: [BenchmarkCommand]) throws -> [ProcessMeasurement] {
        let processes = try commands.map { command in
            try (command: command, pid: spawn(command))
        }
        var results: [ProcessMeasurement] = []
        results.reserveCapacity(processes.count)
        for process in processes {
            let measurement = try wait(for: process.pid)
            guard measurement.exitCode == 0 else {
                throw ProcessRunnerError.unsuccessful(
                    executable: process.command.executable,
                    exitCode: measurement.exitCode
                )
            }
            results.append(measurement)
        }
        return results
    }

    private func spawn(_ command: BenchmarkCommand) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        var result = posix_spawn_file_actions_init(&fileActions)
        guard result == 0 else {
            throw ProcessRunnerError.fileActions(result)
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        result = posix_spawn_file_actions_addopen(
            &fileActions,
            STDIN_FILENO,
            "/dev/null",
            O_RDONLY,
            0
        )
        guard result == 0 else {
            throw ProcessRunnerError.fileActions(result)
        }
        for descriptor in [STDOUT_FILENO, STDERR_FILENO] {
            result = posix_spawn_file_actions_addopen(
                &fileActions,
                descriptor,
                "/dev/null",
                O_WRONLY,
                0
            )
            guard result == 0 else {
                throw ProcessRunnerError.fileActions(result)
            }
        }

        var pid: pid_t = 0
        let arguments = [command.executable] + command.arguments
        let environment = command.environment
            .map { "\($0.key)=\($0.value)" }
            .sorted()
        result = withCStringArray(arguments) { argumentPointers in
            withCStringArray(environment) { environmentPointers in
                posix_spawn(
                    &pid,
                    command.executable,
                    &fileActions,
                    nil,
                    argumentPointers,
                    environmentPointers
                )
            }
        }
        guard result == 0 else {
            throw ProcessRunnerError.spawn(executable: command.executable, error: result)
        }
        return pid
    }

    private func wait(for pid: pid_t) throws -> ProcessMeasurement {
        var status: Int32 = 0
        var usage = rusage()
        while wait4(pid, &status, 0, &usage) == -1 {
            guard errno == EINTR else {
                throw ProcessRunnerError.wait(error: errno)
            }
        }
        let exitCode: Int32 = if status & 0x7F == 0 {
            (status >> 8) & 0xFF
        } else {
            128 + (status & 0x7F)
        }
        return ProcessMeasurement(
            exitCode: exitCode,
            peakResidentBytes: UInt64(max(0, usage.ru_maxrss))
        )
    }

    private func withCStringArray<T>(
        _ strings: [String],
        body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> T
    ) rethrows -> T {
        let pointers = strings.map { strdup($0) } + [nil]
        defer {
            for pointer in pointers.dropLast() {
                free(pointer)
            }
        }
        return try pointers.withUnsafeBufferPointer { buffer in
            try body(UnsafeMutablePointer(mutating: buffer.baseAddress!))
        }
    }
}

private final class PeakResidentMemorySampler: @unchecked Sendable {
    private let processIDs: [pid_t]
    private let lock = NSLock()
    private let group = DispatchGroup()
    private var shouldStop = false
    private var peakResidentBytes: UInt64 = 0

    init(processIDs: [pid_t]) {
        self.processIDs = processIDs
    }

    func start() {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer { group.leave() }
            while !stopped {
                sample()
                usleep(1000)
            }
            sample()
        }
    }

    func stop() -> UInt64 {
        lock.withLock { shouldStop = true }
        group.wait()
        return lock.withLock { peakResidentBytes }
    }

    private var stopped: Bool {
        lock.withLock { shouldStop }
    }

    private func sample() {
        var pending = processIDs
        var visited = Set<pid_t>()
        var residentBytes: UInt64 = 0
        while let pid = pending.popLast() {
            guard visited.insert(pid).inserted else {
                continue
            }
            residentBytes += residentMemory(of: pid)
            pending.append(contentsOf: childProcessIDs(of: pid))
        }
        lock.withLock {
            peakResidentBytes = max(peakResidentBytes, residentBytes)
        }
    }

    private func residentMemory(of pid: pid_t) -> UInt64 {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.stride
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(size))
        guard result == size else {
            return 0
        }
        return info.pti_resident_size
    }

    private func childProcessIDs(of pid: pid_t) -> [pid_t] {
        let requiredCount = proc_listchildpids(pid, nil, 0)
        guard requiredCount > 0 else {
            return []
        }
        var children = [pid_t](
            repeating: 0,
            count: Int(requiredCount) + 16
        )
        let actualCount = children.withUnsafeMutableBytes { buffer in
            proc_listchildpids(pid, buffer.baseAddress, Int32(buffer.count))
        }
        guard actualCount > 0 else {
            return []
        }
        return Array(children.prefix(Int(actualCount)))
            .filter { $0 > 0 }
    }
}
