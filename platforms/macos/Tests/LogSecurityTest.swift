import XCTest
@testable import GoNhanh

// MARK: - Log Security Test
//
// Source-level regression guards for GHSA-8wjg-2xq6-gqmh (CWE-532/CWE-276).
// These tests scan RustBridge.swift source code to detect if the CVE pattern
// is ever reintroduced:
//
//   1. /tmp/gonhanh path in non-comment code
//   2. Log.key() leaking character content via result()
//   3. Log call sites leaking char/chars/text values
//
// Why source-scanning (not runtime)?
//   Log is a private enum — cannot be invoked from test code.
//   The keyboardCallback requires a real CGEvent tap (not testable in unit tests).
//   Source scanning is actually MORE reliable: it catches the pattern regardless
//   of whether logging is enabled at runtime.
//
// Modeled after coreutils' check-safe-traversal.sh — permanent CI guards.

final class LogSecurityTest: XCTestCase {

    /// Resolve RustBridge.swift relative to this test file's compile-time path.
    /// Tests/LogSecurityTest.swift → ../../RustBridge.swift (up from file, up from Tests/)
    private var rustBridgeSourcePath: String {
        let testFilePath = URL(fileURLWithPath: #filePath)
        return testFilePath
            .deletingLastPathComponent()  // removes filename → Tests/
            .deletingLastPathComponent()  // removes Tests/ → platforms/macos/
            .appendingPathComponent("RustBridge.swift")
            .path
    }

    private func readRustBridgeSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let sourcePath = rustBridgeSourcePath
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            XCTFail("RustBridge.swift not found at \(sourcePath) — cannot verify CVE regression", file: file, line: line)
            return ""
        }
        return try String(contentsOfFile: sourcePath)
    }

    // MARK: - CVE Regression: /tmp Path Must Not Be Used

    /// Verify the old vulnerable /tmp path is no longer referenced in active code.
    /// If someone re-introduces /tmp/gonhanh, this test catches it.
    func testNoTmpPathInRustBridgeSource() throws {
        let source = try readRustBridgeSource()
        guard !source.isEmpty else { return }

        let nonCommentLines = source.components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("///")
            }
            .joined(separator: "\n")

        XCTAssertFalse(
            nonCommentLines.contains("/tmp/gonhanh"),
            "SECURITY REGRESSION: /tmp/gonhanh_debug.log path found in non-comment code. " +
            "This is the CVE vulnerability — log path must be ~/Library/Logs/GoNhanh/"
        )
    }

    // MARK: - Log Content Security: No Keystroke Leakage

    /// Verify that Log.key() format string contains only the key code,
    /// not character content. The vulnerable version logged result().
    func testLogKeyFormatExcludesCharacterContent() throws {
        let source = try readRustBridgeSource()
        guard !source.isEmpty else { return }

        let lines = source.components(separatedBy: "\n")
        let keyLines = lines.filter { $0.contains("static func key(") && $0.contains("write(") }

        XCTAssertFalse(keyLines.isEmpty, "Should find Log.key() definition")

        for line in keyLines {
            XCTAssertFalse(
                line.contains("result()"),
                "SECURITY REGRESSION: Log.key() must NOT log result() (character content). " +
                "Found: \(line)"
            )
            XCTAssertTrue(
                line.contains("K:\\(code)"),
                "Log.key() should log only key code in format K:<code>. Found: \(line)"
            )
        }
    }

    /// Verify that no Log.info/Log.key call site in the keyboard callback
    /// logs character values (char, chars, text content).
    func testNoCharacterContentInLogCallSites() throws {
        let source = try readRustBridgeSource()
        guard !source.isEmpty else { return }

        let lines = source.components(separatedBy: "\n")

        let dangerousPatterns = [
            "chars='",          // chars='<text>'
            "char='",           // char='<c>'
            "String(chars)",    // String(chars) — converts chars to string
            "text='",           // text='<content>'
        ]

        // Check Log.key() call sites (not the definition)
        let logKeyCalls = lines.enumerated().filter { (_, line) in
            line.contains("Log.key(") && !line.contains("static func key(")
        }

        for (lineNum, line) in logKeyCalls {
            for pattern in dangerousPatterns {
                XCTAssertFalse(
                    line.contains(pattern),
                    "SECURITY: Line \(lineNum + 1) leaks character content via '\(pattern)': \(line.trimmingCharacters(in: .whitespaces))"
                )
            }
        }

        // Check Log.info calls for text content leakage in inject/keyDown
        let logInfoCalls = lines.enumerated().filter { (_, line) in
            line.contains("Log.info(") && (line.contains("inject:") || line.contains("keyDown:"))
        }

        for (lineNum, line) in logInfoCalls {
            for pattern in dangerousPatterns {
                XCTAssertFalse(
                    line.contains(pattern),
                    "SECURITY: Line \(lineNum + 1) leaks character content via '\(pattern)': \(line.trimmingCharacters(in: .whitespaces))"
                )
            }
        }
    }

    // MARK: - Runtime Proof: Vietnamese Engine Produces Sensitive Content

    /// Prove the IME engine transforms keystrokes into Vietnamese text —
    /// demonstrating that logging this content IS a keylogger.
    ///
    /// This test types "chào" (hello), "việt", "mật" (password) through
    /// RustBridge.processKey() and verifies the engine produces Vietnamese
    /// characters. Combined with the source-scanning tests above, this proves:
    ///
    ///   1. The engine DOES produce sensitive Vietnamese text (this test)
    ///   2. The old Log.key() format WOULD log that text (testLogKeyFormat...)
    ///   3. The old /tmp path IS world-readable (testNoTmpPath...)
    ///
    /// Together: typing Vietnamese → engine produces "chào" → vulnerable
    /// Log.key() writes "K:8 → chào" → /tmp/gonhanh_debug.log (0644) →
    /// any local user reads your passwords.
    func testEngineProducesVietnameseContent() throws {
        // Initialize the Rust IME engine
        RustBridge.initialize()

        // Vietnamese words to type via Telex:
        //   "chào"  = c h a o f  → chào (hello)
        //   "việt"  = v i e e t j → việt
        //   "mật"   = m a a t j   → mật (secret/password)
        //
        // macOS keycodes: a=0x00, c=0x08, e=0x0E, f=0x03, h=0x04,
        //   i=0x22, j=0x26, m=0x2E, o=0x1F, t=0x11, v=0x09
        let vietnameseWords: [(keys: [(UInt16, Character)], expected: String)] = [
            ([(0x08, "c"), (0x04, "h"), (0x00, "a"), (0x1F, "o"), (0x03, "f")], "chào"),
            ([(0x09, "v"), (0x22, "i"), (0x0E, "e"), (0x0E, "e"), (0x11, "t"), (0x26, "j")], "việt"),
            ([(0x2E, "m"), (0x00, "a"), (0x00, "a"), (0x11, "t"), (0x26, "j")], "mật"),
        ]

        for word in vietnameseWords {
            RustBridge.clearBuffer()
            for (keyCode, char) in word.keys {
                _ = RustBridge.processKey(keyCode: keyCode, caps: false, ctrl: false, char: char)
            }
            let buffer = RustBridge.getFullBuffer()

            XCTAssertEqual(
                buffer, word.expected,
                "Engine should produce '\(word.expected)' — this is the sensitive content " +
                "that the vulnerable logger would expose to attackers via /tmp/gonhanh_debug.log"
            )
        }
    }
}
