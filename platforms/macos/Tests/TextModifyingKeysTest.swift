@testable
import GoNhanh
import XCTest

/// Verifies the fix for buffer staleness bug when using Cmd+Backspace/Cmd+Delete.
/// 
/// BUG: Missing 0x33 (Cmd+Backspace) and 0x75 (Cmd+Delete) in textModifyingKeys
/// causes IME buffer to retain old content after deletion, producing garbled output.
/// 
/// This test FAILS if the fix is not applied, proving the bug exists.
final class TextModifyingKeysTest: XCTestCase {
    
    func testCmdBackspaceAndCmdDeleteAreInTextModifyingKeys() {
        // These keys MUST be in textModifyingKeys to clear buffer on Cmd+Delete/Cmd+Backspace
        XCTAssertTrue(
            textModifyingKeys.contains(0x33),
            "CRITICAL FIX MISSING: 0x33 (Cmd+Backspace) must be in textModifyingKeys"
        )
        XCTAssertTrue(
            textModifyingKeys.contains(0x75),
            "CRITICAL FIX MISSING: 0x75 (Cmd+Delete) must be in textModifyingKeys"
        )
    }
}
