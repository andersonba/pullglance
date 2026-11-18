import Foundation
import WebKit

/// The app's side of the page script: calls into `window.__pullglanceReview` and answers its messages.
@MainActor
protocol ReviewScripting: AnyObject {
    func call(_ function: String, _ arguments: [String: Any]) async throws -> Any?
}

@MainActor
final class ReviewBridge: NSObject, ReviewScripting, WKScriptMessageHandlerWithReply {
    static let world = WKContentWorld.world(name: "pullglance-review")
    private let storage: ReviewStorage
    private let log: (String) -> Void
    private weak var webView: WKWebView?
    /// Events from the page: `("context", payload)`, `("listing", payload)`.
    var onEvent: ((String, Any?) -> Void)?

    init(storage: ReviewStorage, log: @escaping (String) -> Void, patience: Duration = ReviewBridge.timeout) {
        self.storage = storage
        self.log = log
        self.patience = patience
    }

    /// Script at document end, in our world, main frame only. Both handlers are reply-capable.
    func install(into ucc: WKUserContentController) {
        guard let url = Bundle.app.url(forResource: "review", withExtension: "js"), let source = try? String(contentsOf: url, encoding: .utf8) else {
            log("review.js missing from resources"); return
        }
        ucc.addScriptMessageHandler(self, contentWorld: Self.world, name: "reviewStorage")
        ucc.addScriptMessageHandler(self, contentWorld: Self.world, name: "reviewEvent")
        ucc.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world))
    }

    func attach(to webView: WKWebView) { self.webView = webView }

    /// Positional arguments go in `["args": [...]]`, e.g. `call("mark", ["args": [NSNull()]])` for `mark(null)`.
    /// A call to a document that gets replaced mid-flight may never answer; nothing upstream may wait forever.
    /// What ends such a call is the replacement itself: the web host says when a navigation commits or the
    /// page's process dies (`documentReplaced`), and every call still waiting fails there and then.
    ///
    /// The clock is only the net under that, and it is long on purpose. A pull request with a thousand files
    /// keeps the page's one thread busy for half a minute after load while GitHub mounts its list (seen live
    /// 2026-11-18), and nothing of ours runs meanwhile: ten seconds of silence used to read as a dead page and
    /// put "The page did not respond" on a page that was about to answer. The limit is also on silence, not
    /// on the call: a long operation posts `progress` events as it goes, and each one starts the wait again.
    static let timeout: Duration = .seconds(60)
    var patience: Duration
    /// When the page last showed it is at work on a call.
    private var lastSign = ContinuousClock.now
    /// How to fail each call still waiting, should its document go away.
    private var pending: [UUID: () -> Void] = [:]

    /// The document the waiting calls were made to is gone; none of them will be answered.
    func documentReplaced() {
        let waiting = pending
        pending = [:]
        for fail in waiting.values { fail() }
    }

    func call(_ function: String, _ arguments: [String: Any]) async throws -> Any? {
        guard let webView else { throw ReviewBridgeError.notAttached }
        let body = "const api = window.__pullglanceReview; if (!api) throw new Error('review script not loaded'); return await api[fn].apply(api, args);"
        let args: [String: Any] = ["fn": function, "args": arguments["args"] ?? []]
        // WebKit's call cannot be cancelled; race it against the clock and take whichever answers first.
        let settled = Settled()
        let started = ContinuousClock.now
        let id = UUID()
        defer { pending[id] = nil }
        let boxed: Boxed = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Boxed, Error>) in
            pending[id] = { if settled.claim() { continuation.resume(throwing: ReviewBridgeError.documentGone) } }
            Task { @MainActor in
                do {
                    let value = try await webView.callAsyncJavaScript(body, arguments: args, in: nil, contentWorld: Self.world)
                    if settled.claim() { continuation.resume(returning: Boxed(value)) }
                } catch {
                    if settled.claim() { continuation.resume(throwing: error) }
                }
            }
            Task { @MainActor in
                while !settled.isDone {
                    let deadline = max(started, self.lastSign) + self.patience
                    if ContinuousClock.now >= deadline { break }
                    try? await Task.sleep(until: deadline, clock: .continuous)
                }
                if settled.claim() { continuation.resume(throwing: ReviewBridgeError.timedOut) }
            }
        }
        return boxed.value
    }

    @MainActor private final class Settled {
        private var done = false
        var isDone: Bool { done }
        func claim() -> Bool { if done { return false }; done = true; return true }
    }

    /// `callAsyncJavaScript` hands back `Any?`; boxing it is how it crosses the continuation under strict concurrency.
    private final class Boxed: @unchecked Sendable {
        let value: Any?
        init(_ value: Any?) { self.value = value }
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping @MainActor (Any?, String?) -> Void) {
        switch message.name {
        case "reviewStorage":
            switch storage.handle(message.body as? [String: Any] ?? [:]) {
            case .success(let value): replyHandler(value, nil)
            case .failure(let error): replyHandler(nil, error.message)
            }
        case "reviewEvent":
            let body = message.body as? [String: Any] ?? [:]
            if body["name"] as? String == "progress" { lastSign = .now }
            onEvent?(body["name"] as? String ?? "", body["payload"])
            replyHandler(nil, nil)
        default:
            replyHandler(nil, "unknown handler \(message.name)")
        }
    }
}

enum ReviewBridgeError: Error { case notAttached, timedOut, documentGone }
