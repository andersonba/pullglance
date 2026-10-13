import Foundation
import Synchronization

/// Verbose-mode aid: a background thread pings the main queue ten times a second and logs any reply that
/// took longer than a quarter second, so a "the app stalled" report can be matched to a timestamp and a
/// duration in the log. Costs nothing visible; runs only while verbose logging is on.
final class MainThreadWatchdog: Sendable {
    static let shared = MainThreadWatchdog()
    private let running = Mutex(false)

    func start() {
        guard running.withLock({ started in
            defer { started = true }
            return !started
        }) else { return }
        let thread = Thread { [log = AppLog.shared] in
            let threshold: Duration = .milliseconds(250)
            while log.isVerbose {
                let done = DispatchSemaphore(value: 0)
                let sent = ContinuousClock.now
                DispatchQueue.main.async { done.signal() }
                done.wait()
                let delay = sent.duration(to: .now)
                if delay > threshold {
                    log.debug("main thread stalled for \(delay.formatted(.units(allowed: [.milliseconds], width: .narrow)))")
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            MainThreadWatchdog.shared.running.withLock { $0 = false }
        }
        thread.name = "MainThreadWatchdog"
        thread.qualityOfService = .utility
        thread.start()
    }
}
