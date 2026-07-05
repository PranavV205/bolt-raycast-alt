import XCTest
import Carbon.HIToolbox
@testable import Bolt

final class HotkeyParseTests: XCTestCase {

    func testDefaultLauncherCombo() {
        let parsed = HotkeyBindings.parse("option+space")
        XCTAssertEqual(parsed?.keyCode, kVK_Space)
        XCTAssertEqual(parsed?.modifiers, optionKey)
    }

    func testMultipleModifiersAndSynonyms() {
        let parsed = HotkeyBindings.parse("ctrl+alt+v")
        XCTAssertEqual(parsed?.keyCode, kVK_ANSI_V)
        XCTAssertEqual(parsed?.modifiers, controlKey | optionKey)

        let cmd = HotkeyBindings.parse("command+shift+return")
        XCTAssertEqual(cmd?.keyCode, kVK_Return)
        XCTAssertEqual(cmd?.modifiers, cmdKey | shiftKey)
    }

    func testWhitespaceAndCaseInsensitive() {
        XCTAssertNotNil(HotkeyBindings.parse("Cmd + Shift + Space"))
    }

    func testBareKeyRequiresModifier() {
        XCTAssertNil(HotkeyBindings.parse("e"))
        XCTAssertNil(HotkeyBindings.parse("space"))
    }

    func testBareFunctionKeyAllowed() {
        let parsed = HotkeyBindings.parse("f5")
        XCTAssertEqual(parsed?.keyCode, kVK_F5)
        XCTAssertEqual(parsed?.modifiers, 0)
    }

    func testInvalidCombosReturnNil() {
        XCTAssertNil(HotkeyBindings.parse("cmd+spce"))       // typo'd key
        XCTAssertNil(HotkeyBindings.parse("cmd+"))           // no key
        XCTAssertNil(HotkeyBindings.parse("cmd+a+b"))        // two keys
        XCTAssertNil(HotkeyBindings.parse(""))
    }

    func testEveryDefaultBindingParsesOrIsNone() {
        for (name, combo) in HotkeyBindings.defaults {
            if combo == "none" { continue }
            XCTAssertNotNil(HotkeyBindings.parse(combo), "default for \(name) must parse")
        }
    }
}
