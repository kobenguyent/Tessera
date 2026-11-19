import Foundation

/// Result of running an external macOS subprocess with concurrent pipe draining and timeout protection.
public struct SubprocessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

public enum SubprocessError: LocalizedError, Sendable {
    case executableNotFound(String)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "Executable not found or not runnable: \(path)"
        case .launchFailed(let reason):
            return reason
        }
    }
}

/// Safe, deadlock-free subprocess execution engine for TesseraCore.
/// - Drains stdout and stderr concurrently so large outputs (>64 KB) never deadlock on OS pipe buffers.
/// - Writes stdin using Swift's throwing API to avoid SIGPIPE crashes on early child exit.
/// - Enforces an upper timeout bound and cleanly terminates hung processes.
/// - Caps captured output per stream to prevent unbounded memory growth.
public enum SubprocessRunner {
    public static let defaultMaxCaptureBytes = 256 * 1024

    public static func run(
        executablePath: String,
        arguments: [String],
        stdin: String? = nil,
        timeoutSeconds: TimeInterval = 20.0,
        maxCaptureBytes: Int = defaultMaxCaptureBytes
    ) throws -> SubprocessResult {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw SubprocessError.executableNotFound(executablePath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe = Pipe()
        if stdin != nil {
            process.standardInput = stdinPipe
        }

        let ioGroup = DispatchGroup()
        final class LockedBuffer: @unchecked Sendable {
            private let lock = NSLock()
            private var data = Data()
            func set(_ newData: Data) {
                lock.lock()
                data = newData
                lock.unlock()
            }
            func get() -> Data {
                lock.lock()
                defer { lock.unlock() }
                return data
            }
        }
        let stdoutBuffer = LockedBuffer()
        let stderrBuffer = LockedBuffer()

        func startDrain(_ handle: FileHandle, into buffer: LockedBuffer) {
            ioGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer {
                    try? handle.close()
                    ioGroup.leave()
                }
                var collected = Data()
                while true {
                    let chunk: Data
                    do {
                        guard let read = try handle.read(upToCount: 8192), !read.isEmpty else {
                            break
                        }
                        chunk = read
                    } catch {
                        break
                    }
                    if collected.count < maxCaptureBytes {
                        let remaining = maxCaptureBytes - collected.count
                        collected.append(chunk.prefix(remaining))
                    }
                }
                buffer.set(collected)
            }
        }

        let exitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            exitSemaphore.signal()
        }

        do {
            try process.run()
        } catch {
            throw SubprocessError.launchFailed(error.localizedDescription)
        }

        startDrain(stdoutPipe.fileHandleForReading, into: stdoutBuffer)
        startDrain(stderrPipe.fileHandleForReading, into: stderrBuffer)

        if let stdin {
            let writeHandle = stdinPipe.fileHandleForWriting
            DispatchQueue.global(qos: .userInitiated).async {
                defer { try? writeHandle.close() }
                if let payload = stdin.data(using: .utf8) {
                    try? writeHandle.write(contentsOf: payload)
                }
            }
        }

        let waitResult = exitSemaphore.wait(timeout: .now() + max(0.1, timeoutSeconds))
        var timedOut = false
        if waitResult == .timedOut {
            timedOut = true
            process.terminate()
            if exitSemaphore.wait(timeout: .now() + 1.0) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exitSemaphore.wait(timeout: .now() + 1.0)
            }
        }

        _ = ioGroup.wait(timeout: .now() + 2.0)

        let outStr = String(data: stdoutBuffer.get(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errStr = String(data: stderrBuffer.get(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return SubprocessResult(
            exitCode: timedOut ? -1 : process.terminationStatus,
            stdout: outStr,
            stderr: errStr,
            timedOut: timedOut
        )
    }
}
