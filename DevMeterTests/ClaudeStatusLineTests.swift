import XCTest
@testable import DevMeter

final class ClaudeStatusLineTests: XCTestCase {
    func testDecode_whenBothWindowsExist_preservesPercentAndEpochResetWithoutInferringTotals() throws {
        let data = Data(#"{"rate_limits":{"five_hour":{"used_percentage":23.4,"resets_at":1800000000},"seven_day":{"used_percentage":70,"resets_at":1800500000}},"context_window":{"used_percentage":99}}"#.utf8)
        let limits = try ClaudeStatusLineDecoder.limits(from: data)
        XCTAssertEqual(limits.map(\.id), ["claude.five-hour", "claude.seven-day"])
        XCTAssertEqual(limits.map(\.remainingPercent), [76, 30])
        XCTAssertEqual(limits.first?.resetsAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testDecode_whenWindowOrResetIsMissing_doesNotInventValuesFromContextOrSpend() throws {
        let data = Data(#"{"rate_limits":{"seven_day":{"used_percentage":42},"spend_limit":{"used_percentage":9}},"context_window":{"used_percentage":90}}"#.utf8)
        let limits = try ClaudeStatusLineDecoder.limits(from: data)
        XCTAssertEqual(limits.count, 1)
        XCTAssertEqual(limits.first?.usedPercent, 42)
        XCTAssertNil(limits.first?.resetsAt)
        for raw in ["{}", #"{"rate_limits":null}"#, #"{"rate_limits":{}}"#] {
            XCTAssertTrue(try ClaudeStatusLineDecoder.limits(from: Data(raw.utf8)).isEmpty)
        }
    }

    func testDecode_whenFieldTypeOrRangeChanges_rejectsMalformedData() {
        for raw in [
            #"{"rate_limits":{"five_hour":{"used_percentage":101}}}"#,
            #"{"rate_limits":{"five_hour":{"used_percentage":-1}}}"#,
            #"{"rate_limits":{"five_hour":{"used_percentage":"25"}}}"#,
            #"{"rate_limits":{"five_hour":{"resets_at":1800000000}}}"#,
            #"{"rate_limits":{"five_hour":{"used_percentage":25,"resets_at":-1}}}"#,
            #"{"rate_limits":{"five_hour":[]}}"#, "not json"
        ] { XCTAssertThrowsError(try ClaudeStatusLineDecoder.limits(from: Data(raw.utf8))) }
        XCTAssertThrowsError(try ClaudeStatusLineDecoder.limits(from: Data(count: ClaudeStatusLineCapture.maximumInputBytes + 1)))
    }

    func testCapture_whenInputContainsSensitiveFields_persistsOnlyWhitelistedQuotaMetadata() throws {
        let data = Data(#"{"session_id":"secret-session-canary","transcript_path":"/private/secret-canary.jsonl","workspace":{"current_dir":"/secret-project-canary"},"apiKey":"secret-token-canary","rate_limits":{"five_hour":{"used_percentage":20}}}"#.utf8)
        let capture = try ClaudeStatusLineCapture(data: data, now: .now)
        let encoded = try JSONEncoder().encode(capture)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("canary"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "capturedAt", "limits"])
        XCTAssertNil(try capture.snapshot(now: .now).accountKey)
    }

    func testFile_roundTrip_keepsReceiptTimeAndOwnerOnlyPermissions_andClearRemovesCapture() throws {
        let file = try temporaryFile()
        let receipt = Date.now.addingTimeInterval(-600)
        let capture = try ClaudeStatusLineCapture(data: Data(#"{"rate_limits":{"five_hour":{"used_percentage":80,"resets_at":1700000000}}}"#.utf8), now: receipt)
        try file.write(capture)
        let snapshot = try file.read(now: .now)
        XCTAssertEqual(snapshot.fetchedAt, receipt)
        XCTAssertEqual(snapshot.limits.first?.usedPercent, 80)
        XCTAssertLessThan(try XCTUnwrap(snapshot.limits.first?.resetsAt), Date.now)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        try file.clear()
        XCTAssertThrowsError(try file.read(now: .now)) { error in
            guard case ClaudeStatusLineError.notConnected = error else { return XCTFail("Expected disconnected") }
        }
    }

    func testFile_whenUnavailableEventArrives_doesNotReusePreviousEventAsLiveQuota() throws {
        let file = try temporaryFile()
        try file.write(ClaudeStatusLineCapture(data: Data(#"{"rate_limits":{"five_hour":{"used_percentage":10}}}"#.utf8), now: .now))
        try file.write(ClaudeStatusLineCapture(data: Data("{}".utf8), now: .now))
        XCTAssertThrowsError(try file.read(now: .now)) { error in
            guard case ClaudeStatusLineError.noQuota = error else { return XCTFail("Expected missing quota") }
        }
    }

    func testFile_whenCorruptOversizedOrFutureDated_rejectsRatherThanOverwriting() throws {
        let file = try temporaryFile()
        for data in [Data("broken".utf8), Data(count: ClaudeStatusLineCapture.maximumFileBytes + 1)] {
            try data.write(to: file.url)
            XCTAssertThrowsError(try file.read(now: .now))
            XCTAssertEqual(try Data(contentsOf: file.url), data)
        }
        let future = try ClaudeStatusLineCapture(data: Data(#"{"rate_limits":{"five_hour":{"used_percentage":10}}}"#.utf8), now: Date.now.addingTimeInterval(3_600))
        try file.write(future)
        XCTAssertThrowsError(try file.read(now: .now))
    }

    func testFile_whenPathIsSymbolicLink_refusesToReadTarget() throws {
        let file = try temporaryFile()
        let target = file.url.deletingLastPathComponent().appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: file.url, withDestinationURL: target)
        XCTAssertThrowsError(try file.read(now: .now))
        XCTAssertEqual(try Data(contentsOf: target), Data("{}".utf8))
    }

    func testClear_whenCachePathIsDirectory_refusesRecursiveDeletion() throws {
        let file = try temporaryFile()
        try FileManager.default.createDirectory(at: file.url, withIntermediateDirectories: false)
        let contents = file.url.appendingPathComponent("preserve.txt")
        try Data("preserve".utf8).write(to: contents)
        XCTAssertThrowsError(try file.clear())
        XCTAssertTrue(FileManager.default.fileExists(atPath: contents.path))
    }

    func testSetupCommand_whenPathHasSpacesAndQuotes_producesValidJSONWithOneQuotedExecutable() throws {
        let text = ClaudeStatusLineCommand.settingsJSON(executable: URL(fileURLWithPath: "/Applications/Dev Meter's.app/Contents/MacOS/DevMeter"))
        let data = try XCTUnwrap(text.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: String]])
        XCTAssertEqual(object["statusLine"]?["type"], "command")
        XCTAssertEqual(object["statusLine"]?["command"], "'/Applications/Dev Meter'\\''s.app/Contents/MacOS/DevMeter' --claude-statusline")
    }

    private func temporaryFile() throws -> ClaudeStatusLineFile {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DevMeter-ClaudeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return ClaudeStatusLineFile(url: directory.appendingPathComponent("capture.json"))
    }
}
