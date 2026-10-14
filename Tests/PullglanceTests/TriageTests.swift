import AppKit
import Testing
@testable import Pullglance

/// Keyboard triage in the popover: ↓ starts, the focus walks the rows, letters act on the focused row.
@Suite struct TriageTests {
    @Test func downStartsAtTheFirstRowAndTheEndsClamp() {
        var focus = TriageFocus()
        let rows = ["a", "b", "c"]
        focus.move(1, in: rows)
        #expect(focus.id == "a")
        focus.move(1, in: rows)
        focus.move(1, in: rows)
        #expect(focus.id == "c")
        focus.move(1, in: rows)
        #expect(focus.id == "c", "no wrap")
        focus.move(-1, in: rows)
        #expect(focus.id == "b")
    }

    @Test func upWithoutFocusDoesNothingAndAVanishedRowDropsTheFocus() {
        var focus = TriageFocus()
        focus.move(-1, in: ["a", "b"])
        #expect(focus.id == nil)
        focus.move(1, in: ["a", "b"])
        focus.move(1, in: ["b"])          // "a" left the list: start over from what is there
        #expect(focus.id == "b")
    }

    /// After P or S the row leaves its place; the one that slides into it is next, or the previous at the end.
    @Test func theRowThatTakesTheLeaversPlaceIsNext() {
        #expect(TriageFocus.successor(of: "b", in: ["a", "b", "c"]) == "c")
        #expect(TriageFocus.successor(of: "c", in: ["a", "b", "c"]) == "b")
        #expect(TriageFocus.successor(of: "a", in: ["a"]) == nil)
        #expect(TriageFocus.successor(of: "zz", in: ["a"]) == nil)
    }

    @Test func keysMapOnlyWithoutModifiers() {
        #expect(TriageKey(characters: "p", keyCode: 35, modifiers: []) == .pin)
        #expect(TriageKey(characters: "P", keyCode: 35, modifiers: [.shift]) == .pin)
        #expect(TriageKey(characters: "s", keyCode: 1, modifiers: []) == .snooze)
        #expect(TriageKey(characters: "o", keyCode: 31, modifiers: []) == .open)
        #expect(TriageKey(characters: "\r", keyCode: 36, modifiers: []) == .review)
        #expect(TriageKey(characters: nil, keyCode: 125, modifiers: []) == .down)
        #expect(TriageKey(characters: nil, keyCode: 126, modifiers: []) == .up)
        #expect(TriageKey(characters: nil, keyCode: 123, modifiers: []) == .left)
        #expect(TriageKey(characters: nil, keyCode: 124, modifiers: []) == .right)
        #expect(TriageKey(characters: nil, keyCode: 53, modifiers: []) == .escape)
        #expect(TriageKey(characters: " ", keyCode: 49, modifiers: []) == .space)
        #expect(TriageKey(characters: "p", keyCode: 35, modifiers: [.command]) == nil, "⌘P is someone else's")
        #expect(TriageKey(characters: "x", keyCode: 7, modifiers: []) == nil)
        // The rest of the row menu, same initials; two with ⌘ because they are the system's letters.
        #expect(TriageKey(characters: "r", keyCode: 15, modifiers: []) == .refresh)
        #expect(TriageKey(characters: "c", keyCode: 8, modifiers: []) == .comment)
        #expect(TriageKey(characters: "m", keyCode: 46, modifiers: []) == .merge)
        #expect(TriageKey(characters: "c", keyCode: 8, modifiers: [.command]) == .copyLink)
        #expect(TriageKey(characters: "/", keyCode: 44, modifiers: [.command]) == .shortcuts)
        #expect(TriageKey(characters: "/", keyCode: 44, modifiers: []) == nil)
        #expect(TriageKey(characters: "c", keyCode: 8, modifiers: [.option]) == nil)
    }
}
