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

/// Reads a pipe to EOF on a GCD thread. Blocking there is fine; blocking the cooperative pool is not:
/// with three blocked threads per process, a few concurrent `gh` calls starve the timeout task entirely.
private func readToEnd(_ handle: FileHandle) async -> Data {
    let box = UncheckedBox(handle)
    return await withCheckedContinuation { c in
        DispatchQueue.global(qos: .utility).async {
            c.resume(returning: box.value.readDataToEndOfFile())
        }
    }
}

/// Runs an executable without a shell, reads both pipes concurrently (so a full pipe never deadlocks),
/// and terminates the process if it exceeds `timeout`. Never blocks a cooperative-pool thread.
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

    do {
        try process.run()
    } catch {
        throw ProcessFailure.launchFailed(error.localizedDescription)
    }

    let processBox = UncheckedBox(process)
    async let stdout = readToEnd(stdoutPipe.fileHandleForReading)
    async let stderr = readToEnd(stderrPipe.fileHandleForReading)
    let killer = Task {
        try await Task.sleep(for: timeout)
        if processBox.value.isRunning { processBox.value.terminate() }
    }

    await exit.wait()
    killer.cancel()
    let (outData, errData) = await (stdout, stderr)

    // The only signal we ever send is SIGTERM from `killer`, so an uncaught signal means the timeout fired.
    if processBox.value.terminationReason == .uncaughtSignal { throw ProcessFailure.timedOut }
    return ProcessResult(exitCode: processBox.value.terminationStatus, stdout: outData, stderr: errData)
}
