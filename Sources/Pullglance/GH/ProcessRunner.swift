import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

enum ProcessFailure: Error, Equatable {
    case launchFailed(String)
    case timedOut
}

/// Foundation's Process and Pipe are not Sendable; this wrapper lets us hand them across isolation domains.
private final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Bridges `Process.terminationHandler` to `await` without parking a cooperative-pool thread in `waitUntilExit()`.
/// The handler is installed before `run()`, so an exit that happens before anyone awaits is not lost.
private final class ExitSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var exited = false
    private var continuation: CheckedContinuation<Void, Never>?

    func signal() {
        lock.lock()
        exited = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }

    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if exited {
                lock.unlock()
                c.resume()
            } else {
                continuation = c
                lock.unlock()
            }
        }
    }
}

enum ProcessRunner {
    /// How long a process gets to leave after SIGTERM before SIGKILL.
    static let killGrace: Duration = .seconds(2)
    /// How long, after the process has exited, the pipes get to deliver what is still in flight. A child
    /// the process left behind keeps the pipes open, and waiting for its EOF would be waiting for the child.
    static let drainGrace: Duration = .seconds(1)
}

/// Collects a pipe's output as it arrives, on the handle's own queue: no thread blocked in a read, so
/// nothing waits on an EOF that an orphaned child may never send. `finish()` ends the collection with
/// what was read so far; EOF finishes it on its own.
private final class PipeReader: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    private var data = Data()
    private var finished = false
    private var continuation: CheckedContinuation<Data, Never>?

    init(_ handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [self] h in
            let chunk = h.availableData
            if chunk.isEmpty {
                finish()
            } else {
                lock.lock()
                data.append(chunk)
                lock.unlock()
            }
        }
    }

    func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        handle.readabilityHandler = nil
        let pending = continuation
        continuation = nil
        let result = data
        lock.unlock()
        // The handle closes with the pipe, when the run is over: closing it here could pull the descriptor
        // from under a handler still reading on its queue.
        pending?.resume(returning: result)
    }

    func value() async -> Data {
        await withCheckedContinuation { c in
            lock.lock()
            if finished {
                let result = data
                lock.unlock()
                c.resume(returning: result)
            } else {
                continuation = c
                lock.unlock()
            }
        }
    }
}

/// Runs an executable without a shell, reads both pipes as they fill (so a full pipe never deadlocks),
/// and terminates the process if it exceeds `timeout`: SIGTERM, then SIGKILL after `ProcessRunner.killGrace`
/// for a process that shrugs it off. Never blocks a cooperative-pool thread, and never waits on a pipe an
/// orphaned child holds open: `ProcessRunner.drainGrace` after the exit, what was read is the result.
func runProcess(executable: URL, arguments: [String], timeout: Duration) async throws -> ProcessResult {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    environment["GH_PROMPT_DISABLED"] = "1"
    environment["GH_NO_UPDATE_NOTIFIER"] = "1"
    environment["NO_COLOR"] = "1"
    process.environment = environment

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.standardInput = FileHandle.nullDevice

    let exit = ExitSignal()
    process.terminationHandler = { _ in exit.signal() }
    let stdout = PipeReader(stdoutPipe.fileHandleForReading)
    let stderr = PipeReader(stderrPipe.fileHandleForReading)

    do {
        try process.run()
    } catch {
        stdout.finish()
        stderr.finish()
        throw ProcessFailure.launchFailed(error.localizedDescription)
    }

    let processBox = UncheckedBox(process)
    let killer = Task {
        try await Task.sleep(for: timeout)
        guard processBox.value.isRunning else { return }
        processBox.value.terminate()
        try await Task.sleep(for: ProcessRunner.killGrace)
        if processBox.value.isRunning { kill(processBox.value.processIdentifier, SIGKILL) }
    }

    await exit.wait()
    killer.cancel()
    let drain = Task {
        try await Task.sleep(for: ProcessRunner.drainGrace)
        stdout.finish()
        stderr.finish()
    }
    let (outData, errData) = await (stdout.value(), stderr.value())
    drain.cancel()

    // The only signals we ever send come from `killer`, so an uncaught signal means the timeout fired.
    if processBox.value.terminationReason == .uncaughtSignal { throw ProcessFailure.timedOut }
    return ProcessResult(exitCode: processBox.value.terminationStatus, stdout: outData, stderr: errData)
}
