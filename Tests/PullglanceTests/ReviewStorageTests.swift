import Foundation
import Testing
@testable import Pullglance

@MainActor
@Suite struct ReviewStorageTests {
    private func storage() -> (ReviewStorage, UserDefaults) {
        let defaults = testDefaults()
        return (ReviewStorage(defaults: defaults), defaults)
    }

    @Test func setThenGetRoundTripsAndReportsChanges() throws {
        let (s, _) = storage()
        let changes = try s.handle(["area": "local", "op": "set", "items": ["ghra:compare:/acme/web/compare/a...b": ["viewed": ["x"], "updatedAt": 1]]]).get() as? [String: [String: Any]]
        #expect(changes?["ghra:compare:/acme/web/compare/a...b"]?["oldValue"] == nil)
        #expect((changes?["ghra:compare:/acme/web/compare/a...b"]?["newValue"] as? [String: Any])?["updatedAt"] as? Int == 1)
        let all = try s.handle(["area": "local", "op": "get"]).get() as? [String: Any]
        #expect(all?.keys.sorted() == ["ghra:compare:/acme/web/compare/a...b"])
    }

    @Test func persistentAreasSurviveANewInstanceSessionDoesNot() throws {
        let (s, defaults) = storage()
        _ = s.handle(["area": "local", "op": "set", "items": ["k": 1]])
        _ = s.handle(["area": "session", "op": "set", "items": ["k": 2]])
        let again = ReviewStorage(defaults: defaults)
        #expect((try again.handle(["area": "local", "op": "get"]).get() as? [String: Any])?["k"] as? Int == 1)
        #expect((try again.handle(["area": "session", "op": "get"]).get() as? [String: Any])?.isEmpty == true)
    }

    @Test func removeClearAndBadRequests() throws {
        let (s, _) = storage()
        _ = s.handle(["area": "local", "op": "set", "items": ["a": 1, "b": 2]])
        let removed = try s.handle(["area": "local", "op": "remove", "keys": ["a"]]).get() as? [String: [String: Any]]
        #expect(removed?["a"]?["oldValue"] as? Int == 1)
        #expect(removed?["a"]?["newValue"] == nil)
        _ = s.handle(["area": "local", "op": "clear"])
        #expect((try s.handle(["area": "local", "op": "get"]).get() as? [String: Any])?.isEmpty == true)
        if case .success = s.handle(["op": "get"]) { Issue.record("missing area must fail") }
        if case .success = s.handle(["area": "local", "op": "explode"]) { Issue.record("unknown op must fail") }
        if case .success = s.handle(["area": "managed", "op": "get"]) { Issue.record("unknown area must fail") }
    }

    @Test func clearPersistentWipesLocalAndSync() throws {
        let (s, _) = storage()
        _ = s.handle(["area": "local", "op": "set", "items": ["k": 1]])
        _ = s.handle(["area": "sync", "op": "set", "items": ["k": 1]])
        s.clearPersistent()
        #expect((try s.handle(["area": "local", "op": "get"]).get() as? [String: Any])?.isEmpty == true)
        #expect((try s.handle(["area": "sync", "op": "get"]).get() as? [String: Any])?.isEmpty == true)
    }

    @Test func nonJSONValuesAreRejected() throws {
        let (s, _) = storage()
        if case .success = s.handle(["area": "local", "op": "set", "items": ["when": Date()]]) { Issue.record("non-JSON value must fail") }
        #expect((try s.handle(["area": "local", "op": "get"]).get() as? [String: Any])?["when"] == nil)
    }
}
