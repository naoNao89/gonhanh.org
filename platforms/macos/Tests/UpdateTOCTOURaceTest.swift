import XCTest
@testable import GoNhanh

// MARK: - Update Security Test
//
// Source-level regression guards for CWE-377 / CWE-367:
//   Insecure Temporary File + TOCTOU Race Condition in auto-update.
//
// The vulnerable code used a predictable /tmp/GoNhanh-update.app path with
// shell("rm -rf") + shell("cp -R"), enabling:
//   1. Symlink attack: attacker pre-places symlink at /tmp/GoNhanh-update.app
//   2. TOCTOU race: between rm -rf and cp -R, attacker swaps in malicious .app
//   3. The relaunch script then installs + executes the malicious .app bundle
//
// The fix (commit 84345c75) replaced:
//   - /tmp/GoNhanh-update.app → FileManager.url(for: .itemReplacementDirectory)
//   - shell("rm -rf") → FileManager.removeItem()
//   - shell("cp -R")  → FileManager.copyItem()
//
// These tests scan UpdateManager.swift source code to detect if the vulnerable
// patterns are ever reintroduced. Modeled after LogSecurityTest.swift pattern —
// permanent CI guards via source scanning.
//
// CVSS v3.1: 6.5 (Medium) — AV:L/AC:H/PR:L/UI:R/S:C/C:N/I:H/A:N

final class UpdateTOCTOURaceTest: XCTestCase {

    /// Resolve UpdateManager.swift relative to this test file's compile-time path.
    /// Tests/UpdateTOCTOURaceTest.swift → ../../UpdateManager.swift
    private var updateManagerSourcePath: String {
        let testFilePath = URL(fileURLWithPath: #filePath)
        return testFilePath
            .deletingLastPathComponent()  // removes filename → Tests/
            .deletingLastPathComponent()  // removes Tests/ → platforms/macos/
            .appendingPathComponent("UpdateManager.swift")
            .path
    }

    private func readUpdateManagerSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let sourcePath = updateManagerSourcePath
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            XCTFail("UpdateManager.swift not found at \(sourcePath) — cannot verify CVE regression", file: file, line: line)
            return ""
        }
        return try String(contentsOfFile: sourcePath)
    }

    /// Extract non-comment, non-blank lines from source for pattern matching.
    private func activeCodeLines(from source: String) -> [(lineNum: Int, text: String)] {
        source.components(separatedBy: "\n")
            .enumerated()
            .compactMap { (idx, line) in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") || trimmed.isEmpty {
                    return nil
                }
                return (lineNum: idx + 1, text: line)
            }
    }

    /// Extract the body of a named function from source code.
    /// Uses brace-counting to find the function boundary.
    /// Returns the function body as a string (empty if not found).
    private func extractFunctionBody(named funcName: String, from source: String) -> String {
        let lines = source.components(separatedBy: "\n")
        var capturing = false
        var braceDepth = 0
        var bodyLines: [String] = []

        for line in lines {
            if !capturing {
                // Look for "func <funcName>" or "private func <funcName>"
                if line.contains("func \(funcName)") {
                    capturing = true
                    braceDepth = 0
                }
            }

            if capturing {
                bodyLines.append(line)
                braceDepth += line.filter({ $0 == "{" }).count
                braceDepth -= line.filter({ $0 == "}" }).count
                if braceDepth <= 0 && bodyLines.count > 1 {
                    break
                }
            }
        }
        return bodyLines.joined(separator: "\n")
    }

    // MARK: - CVE Regression: Predictable /tmp Path (CWE-377)

    /// Verify the old vulnerable /tmp/GoNhanh-update.app path is no longer used.
    /// A predictable path in world-writable /tmp enables symlink attacks.
    func testNoPredictableTmpPathForUpdate() throws {
        let source = try readUpdateManagerSource()
        guard !source.isEmpty else { return }

        let activeLines = activeCodeLines(from: source)

        // The specific vulnerable path
        let dangerousPaths = [
            "/tmp/GoNhanh-update.app",
            "/tmp/GoNhanh",
        ]

        for (lineNum, line) in activeLines {
            for path in dangerousPaths {
                XCTAssertFalse(
                    line.contains(path),
                    "SECURITY REGRESSION (CWE-377): Predictable temp path '\(path)' found at line \(lineNum). " +
                    "Update staging MUST use FileManager.url(for: .itemReplacementDirectory) for unpredictable, " +
                    "user-private paths. Found: \(line.trimmingCharacters(in: .whitespaces))"
                )
            }
        }
    }

    /// Verify no hardcoded /tmp/ paths are used for any update-related file operations.
    /// Even variations like /tmp/SomethingElse.app would be vulnerable.
    func testNoHardcodedTmpDirectory() throws {
        let source = try readUpdateManagerSource()
        guard !source.isEmpty else { return }

        let activeLines = activeCodeLines(from: source)

        for (lineNum, line) in activeLines {
            // Match any string literal containing /tmp/ (but not inside string interpolation comments)
            if line.contains("\"/tmp/") {
                XCTFail(
                    "SECURITY REGRESSION (CWE-377): Hardcoded /tmp/ path found at line \(lineNum). " +
                    "All temporary files must use FileManager.url(for: .itemReplacementDirectory) or " +
                    "FileManager.default.temporaryDirectory (which resolves to user-private temp). " +
                    "Found: \(line.trimmingCharacters(in: .whitespaces))"
                )
            }
        }
    }

    // MARK: - CVE Regression: Shell-based File Operations (CWE-367 TOCTOU)

    /// Verify that shell("rm -rf") is NOT used for update staging operations.
    /// Shell-based rm creates a TOCTOU window between deletion and copy.
    func testNoShellRmForUpdateStaging() throws {
        let source = try readUpdateManagerSource()
        guard !source.isEmpty else { return }

        let activeLines = activeCodeLines(from: source)

        // Find lines in prepareInstall context that use shell rm -rf on temp paths
        // (shell rm for hdiutil detach is acceptable — only file manipulation is dangerous)
        for (lineNum, line) in activeLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // shell("rm -rf") on anything NOT /Volumes/ (hdiutil detach is OK)
            if trimmed.contains("shell(") && trimmed.contains("rm -rf") && !trimmed.contains("/Volumes/") && !trimmed.contains("hdiutil") {
                XCTFail(
                    "SECURITY REGRESSION (CWE-367): shell(\"rm -rf\") used for file ops at line \(lineNum). " +
                    "This creates a TOCTOU race window. Use FileManager.removeItem() instead. " +
                    "Found: \(trimmed)"
                )
            }
        }
    }

    /// Verify that shell("cp -R") is NOT used for copying the update bundle.
    /// Shell-based cp creates a TOCTOU window where an attacker can race to swap files.
    func testNoShellCpForUpdateStaging() throws {
        let source = try readUpdateManagerSource()
        guard !source.isEmpty else { return }

        let activeLines = activeCodeLines(from: source)

        for (lineNum, line) in activeLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("shell(") && trimmed.contains("cp -R") {
                XCTFail(
                    "SECURITY REGRESSION (CWE-367): shell(\"cp -R\") used at line \(lineNum). " +
                    "This creates a TOCTOU race window. Use FileManager.copyItem() instead. " +
                    "Found: \(trimmed)"
                )
            }
        }
    }

    // MARK: - Secure APIs in prepareInstall() Context

    /// Verify that prepareInstall uses FileManager's itemReplacementDirectory.
    /// This is the macOS-native way to create secure, unpredictable temp paths
    /// with proper permissions (equivalent to mkstemp on POSIX).
    func testUsesSecureTempDirectoryAPI() throws {
        let source = try readUpdateManagerSource()
        guard !source.isEmpty else { return }

        let prepareInstallBody = extractFunctionBody(named: "prepareInstall", from: source)
        XCTAssertFalse(prepareInstallBody.isEmpty, "Should find prepareInstall function body")

        XCTAssertTrue(
            prepareInstallBody.contains(".itemReplacementDirectory"),
            "SECURITY REGRESSION: prepareInstall() must use FileManager.url(for: .itemReplacementDirectory) " +
            "to create unpredictable, user-private temporary directories for update staging. " +
            "This prevents symlink attacks and TOCTOU races."
        )
    }

    /// Verify FileManager.copyItem is used INSIDE prepareInstall (not just anywhere in the file).
    func testUsesFileManagerCopyItemInPrepareInstall() throws {
        let source = try readUpdateManagerSource()
        guard !source.isEmpty else { return }

        let prepareInstallBody = extractFunctionBody(named: "prepareInstall", from: source)
        XCTAssertFalse(prepareInstallBody.isEmpty, "Should find prepareInstall function body")

        XCTAssertTrue(
            prepareInstallBody.contains("copyItem(atPath:") || prepareInstallBody.contains("copyItem(at:"),
            "SECURITY REGRESSION: prepareInstall() must use FileManager.copyItem() " +
            "instead of shell(\"cp -R\") for copying the update bundle. " +
            "FileManager APIs are atomic and not susceptible to TOCTOU races."
        )
    }

    /// Verify FileManager.removeItem is used INSIDE prepareInstall (not just anywhere in the file).
    func testUsesFileManagerRemoveItemInPrepareInstall() throws {
        let source = try readUpdateManagerSource()
        guard !source.isEmpty else { return }

        let prepareInstallBody = extractFunctionBody(named: "prepareInstall", from: source)
        XCTAssertFalse(prepareInstallBody.isEmpty, "Should find prepareInstall function body")

        XCTAssertTrue(
            prepareInstallBody.contains("removeItem(atPath:") || prepareInstallBody.contains("removeItem(at:"),
            "SECURITY REGRESSION: prepareInstall() must use FileManager.removeItem() " +
            "instead of shell(\"rm -rf\") for removing old temp files. " +
            "FileManager APIs avoid the TOCTOU race window between check-and-act."
        )
    }

    // MARK: - Combined Attack Vector Verification

    /// End-to-end verification: the complete vulnerable pattern must not exist.
    /// The old attack chain was:
    ///   1. Predictable path: /tmp/GoNhanh-update.app
    ///   2. shell("rm -rf '/tmp/GoNhanh-update.app'")     — TOCTOU window opens
    ///   3. shell("cp -R '<source>' '/tmp/GoNhanh-update.app'")  — race here
    ///   4. mv '/tmp/GoNhanh-update.app' '/Applications/GoNhanh.app'
    ///
    /// ALL four components must be absent for the fix to hold.
    func testCompleteAttackChainAbsent() throws {
        let source = try readUpdateManagerSource()
        guard !source.isEmpty else { return }

        let activeCode = activeCodeLines(from: source).map(\.text).joined(separator: "\n")

        let vulnerablePatterns: [(pattern: String, description: String)] = [
            ("/tmp/GoNhanh-update.app", "predictable temp path"),
            ("shell(\"rm -rf", "shell-based file deletion (TOCTOU window)"),
            ("shell(\"cp -R", "shell-based file copy (TOCTOU race target)"),
        ]

        var foundVulnerabilities: [String] = []

        for (pattern, description) in vulnerablePatterns {
            if activeCode.contains(pattern) {
                foundVulnerabilities.append("  - \(description): '\(pattern)'")
            }
        }

        XCTAssertTrue(
            foundVulnerabilities.isEmpty,
            "SECURITY REGRESSION: CVE attack chain components found in UpdateManager.swift:\n" +
            foundVulnerabilities.joined(separator: "\n") + "\n" +
            "The complete fix requires: .itemReplacementDirectory + FileManager.copyItem() + FileManager.removeItem()"
        )
    }
}
