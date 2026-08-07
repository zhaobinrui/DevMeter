import XCTest
@testable import CodexMeter

final class CodexLocalUsageProviderTests: XCTestCase {
    func testFetchSnapshot_whenServerResponds_shouldCompleteJSONLHandshake() async throws {
        let executableURL = try makeExecutableScript(
            contents: #"""
            #!/bin/sh
            while IFS= read -r line
            do
              case "$line" in
                *'"method":"initialize"'*)
                  printf '%s\n' '{"id":0,"result":{}}'
                  ;;
                *'rateLimits'*)
                  printf '%s\n' '{"id":1,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":null},"secondary":null,"credits":null}}}'
                  ;;
              esac
            done
            """#
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }
        let provider = CodexLocalUsageProvider(
            executableURL: executableURL,
            timeout: .seconds(2)
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.limits.first?.id, "codex.primary")
        XCTAssertEqual(snapshot.limits.first?.remainingPercent, 80)
    }

    func testFetchSnapshot_whenServerDoesNotRespond_shouldTimeOut() async throws {
        let executableURL = try makeExecutableScript(
            contents: #"""
            #!/bin/sh
            while IFS= read -r line
            do
              :
            done
            """#
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }
        let provider = CodexLocalUsageProvider(
            executableURL: executableURL,
            timeout: .milliseconds(100)
        )

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("Expected the provider to time out")
        } catch {
            guard case UsageProviderError.timedOut = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeExecutableScript(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexMeterTests", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
        return url
    }
}
