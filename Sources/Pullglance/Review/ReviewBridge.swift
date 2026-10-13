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

    init(storage: ReviewStorage, log: @escaping (String) -> Void) {
        self.storage = storage
        self.log = log
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
    func call(_ function: String, _ arguments: [String: Any]) async throws -> Any? {
        guard let webView else { throw ReviewBridgeError.notAttached }
        let body = "const api = window.__pullglanceReview; if (!api) throw new Error('review script not loaded'); return await api[fn].apply(api, args);"
        return try await webView.callAsyncJavaScript(body, arguments: ["fn": function, "args": arguments["args"] ?? []], in: nil, contentWorld: Self.world)
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
            onEvent?(body["name"] as? String ?? "", body["payload"])
            replyHandler(nil, nil)
        default:
            replyHandler(nil, "unknown handler \(message.name)")
        }
    }
}

enum ReviewBridgeError: Error { case notAttached }
