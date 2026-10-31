import Foundation
import Darwin

// The deadline includes feeding stdin, process execution and draining output.
// Nonblocking writes prevent a stalled reader from holding the translation queue.
enum TranslationProcess {
    enum Failure: Error { case timedOut, inputFailed(Int32) }
    struct Result {
        let status: Int32
        let output: Data
        let errors: Data
    }
    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()
        func append(_ data: Data) { lock.lock(); defer { lock.unlock() }; bytes.append(data) }
        func data() -> Data { lock.lock(); defer { lock.unlock() }; return bytes }
    }

    static func run(executable: URL, arguments: [String], environment: [String: String],
                    input: Data, timeout: TimeInterval) throws -> Result {
        let child = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        child.environment = environment
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = stderr
        let finished = DispatchSemaphore(value: 0)
        child.terminationHandler = { _ in finished.signal() }
        let deadline = DispatchTime.now() + max(0.01, timeout)
        try child.run()
        let drained = DispatchGroup()
        let output = Capture(), errors = Capture()
        for (pipe, capture) in [(stdout, output), (stderr, errors)] {
            drained.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { try? pipe.fileHandleForReading.close(); drained.leave() }
                while let data = try? pipe.fileHandleForReading.read(upToCount: 65536), !data.isEmpty {
                    capture.append(data)
                }
            }
        }
        defer {
            try? stdin.fileHandleForWriting.close()
            if child.isRunning {
                child.terminate()
                if finished.wait(timeout: .now() + 0.5) == .timedOut, child.isRunning {
                    _ = kill(child.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + 0.5)
                }
            }
        }
        let fd = stdin.fileHandleForWriting.fileDescriptor
        guard fcntl(fd, F_SETNOSIGPIPE, 1) != -1,
              fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else {
            throw Failure.inputFailed(errno)
        }
        try input.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                guard DispatchTime.now() < deadline else { throw Failure.timedOut }
                let written = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if written > 0 { offset += written; continue }
                if written < 0 && errno == EINTR { continue }
                guard written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) else {
                    throw Failure.inputFailed(errno)
                }
                var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                _ = poll(&descriptor, 1, 10)
            }
        }
        try stdin.fileHandleForWriting.close()
        guard finished.wait(timeout: deadline) == .success,
              drained.wait(timeout: deadline) == .success else { throw Failure.timedOut }
        return Result(status: child.terminationStatus, output: output.data(), errors: errors.data())
    }
}

// Failure to establish the original selection must never authorize a paste.
enum TextReplacementSafety {
    static func canReplace(sourcePID: Int32?, currentPID: Int32?, sameElement: Bool,
                           original: String, selected: String?,
                           originalRange: NSRange?, currentRange: NSRange?) -> Bool {
        guard let sourcePID, sourcePID == currentPID, sameElement,
              !original.isEmpty, let selected, let originalRange, let currentRange else { return false }
        return original == selected && originalRange == currentRange
    }
}
