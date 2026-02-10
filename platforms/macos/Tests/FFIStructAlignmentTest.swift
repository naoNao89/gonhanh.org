import XCTest
@testable import GoNhanh

// MARK: - FFI Struct Alignment Security Test
//
// Verify macOS ImeResult struct matches the Rust Result layout.
//
// The Rust Result struct uses chars: [u32; 256] = 1024 bytes + 4 bytes = 1028 bytes.
// All platform bridges MUST match this exactly. A mismatch causes action/backspace/count
// fields to be read from wrong memory offsets, silently corrupting every keystroke result.
//
// These tests verify:
// 1. macOS ImeResult chars tuple has exactly 256 UInt32 elements (1028 bytes total)
// 2. macOS ImeResult has 'flags' field (not '_pad')
// 3. macOS RustBridge.swift defines FLAG_KEY_CONSUMED constant
// 4. macOS struct size is documented as 1028 bytes

final class FFIStructAlignmentTest: XCTestCase {

    // MARK: - Path Helpers

    /// Resolve RustBridge.swift relative to this test file's compile-time path.
    private var rustBridgeSwiftPath: String {
        let testFilePath = URL(fileURLWithPath: #filePath)
        return testFilePath
            .deletingLastPathComponent()  // removes filename → Tests/
            .deletingLastPathComponent()  // removes Tests/ → platforms/macos/
            .appendingPathComponent("RustBridge.swift")
            .path
    }

    private func readSource(at path: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            XCTFail("Source file not found at \(path)", file: file, line: line)
            return ""
        }
        return try String(contentsOfFile: path)
    }

    /// Extract lines between "struct ImeResult" and "};" from source.
    private func extractImeResultStruct(from source: String) -> String {
        var inStruct = false
        var lines: [String] = []
        for line in source.components(separatedBy: "\n") {
            if line.contains("struct ImeResult") {
                inStruct = true
            }
            if inStruct {
                lines.append(line)
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("};") ||
                   line.trimmingCharacters(in: .whitespaces) == "}" {
                    break
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - macOS Tests (should PASS — macOS is already correct)

    /// Verify macOS ImeResult struct has 256 UInt32 chars (1024 bytes)
    /// plus 4 bytes for action/backspace/count/flags = 1028 bytes total.
    func testMacOSImeResultHas256Elements() throws {
        let source = try readSource(at: rustBridgeSwiftPath)
        guard !source.isEmpty else { return }

        // Extract only the chars tuple — between "var chars: (" and the closing ")"
        // This avoids counting UInt32 in comments or other fields
        var inCharsTuple = false
        var charsTupleLines: [String] = []
        for line in source.components(separatedBy: "\n") {
            if line.contains("var chars: (") {
                inCharsTuple = true
            }
            if inCharsTuple {
                charsTupleLines.append(line)
                // The closing ")" line for the tuple
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == ")" || trimmed.hasPrefix(")") {
                    break
                }
            }
        }

        let charsTuple = charsTupleLines.joined(separator: "\n")
        // Count UInt32 occurrences — each element in the tuple is one UInt32
        let uint32Count = charsTuple.components(separatedBy: "UInt32").count - 1

        XCTAssertEqual(
            uint32Count, 256,
            """
            CRITICAL: macOS ImeResult chars tuple should have exactly 256 UInt32 elements, \
            but found \(uint32Count). Must match Rust MAX = 256 (buffer.rs). \
            Struct size should be 256*4 + 4 = 1028 bytes.
            """
        )
    }

    /// Verify macOS ImeResult struct has a 'flags' field (not '_pad').
    func testMacOSImeResultHasFlagsField() throws {
        let source = try readSource(at: rustBridgeSwiftPath)
        guard !source.isEmpty else { return }

        let structBody = extractImeResultStruct(from: source)

        XCTAssertTrue(
            structBody.contains("var flags"),
            """
            macOS ImeResult must have a 'flags' field (var flags: UInt8). \
            The Rust struct has 'flags: u8' with FLAG_KEY_CONSUMED bit 0. \
            Without this, shortcut key_consumed support is broken.
            """
        )

        XCTAssertFalse(
            structBody.contains("_pad"),
            """
            macOS ImeResult still uses '_pad' instead of 'flags'. \
            Rename to 'flags' to match Rust struct.
            """
        )
    }

    /// Verify macOS has FLAG_KEY_CONSUMED constant matching Rust.
    func testMacOSHasFlagKeyConsumedConstant() throws {
        let source = try readSource(at: rustBridgeSwiftPath)
        guard !source.isEmpty else { return }

        XCTAssertTrue(
            source.contains("FLAG_KEY_CONSUMED"),
            """
            macOS RustBridge.swift must define FLAG_KEY_CONSUMED constant \
            to match Rust engine::FLAG_KEY_CONSUMED = 0x01.
            """
        )
    }

    /// Verify macOS struct comment documents correct size (1028 bytes).
    func testMacOSStructSizeComment() throws {
        let source = try readSource(at: rustBridgeSwiftPath)
        guard !source.isEmpty else { return }

        XCTAssertTrue(
            source.contains("1028"),
            """
            macOS RustBridge.swift should document ImeResult size as 1028 bytes \
            (256*4 + 4). If this fails, the size documentation is outdated.
            """
        )
    }

}
