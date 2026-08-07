import XCTest
@testable import CodexMeter

final class CodexRateLimitsDecoderTests: XCTestCase {
    func testDecodeSnapshot_whenMultipleBucketsExist_shouldMapAllWindows() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try CodexRateLimitsDecoder.decodeSnapshot(
            from: Data(Self.multipleBucketsResponse.utf8),
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(snapshot.limits.map(\.id), [
            "codex.primary",
            "codex.secondary",
            "codex_other.primary"
        ])
        XCTAssertEqual(snapshot.limits.map(\.name), [
            "5 小时额度",
            "周额度",
            "代码审查 · 1 小时额度"
        ])
        XCTAssertEqual(snapshot.limits.map(\.remainingPercent), [75, 40, 58])
        XCTAssertEqual(snapshot.creditBalance, "120.5")
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
    }

    func testDecodeSnapshot_whenMultiBucketViewIsMissing_shouldUseLegacyBucket() throws {
        let snapshot = try CodexRateLimitsDecoder.decodeSnapshot(
            from: Data(Self.legacyResponse.utf8)
        )

        XCTAssertEqual(snapshot.limits.count, 1)
        XCTAssertEqual(snapshot.limits.first?.id, "codex.primary")
        XCTAssertEqual(snapshot.limits.first?.name, "周额度")
        XCTAssertEqual(snapshot.limits.first?.remainingPercent, 3)
        XCTAssertEqual(snapshot.creditBalance, "0")
    }

    func testDecodeSnapshot_whenCreditsAreUnlimited_shouldUseReadableLabel() throws {
        let snapshot = try CodexRateLimitsDecoder.decodeSnapshot(
            from: Data(Self.unlimitedCreditsResponse.utf8)
        )

        XCTAssertEqual(snapshot.creditBalance, "无限")
    }

    func testDecodeSnapshot_whenNoWindowsExist_shouldThrowNoUsageLimits() {
        XCTAssertThrowsError(
            try CodexRateLimitsDecoder.decodeSnapshot(
                from: Data(#"{"id":1,"result":{"rateLimits":null,"rateLimitsByLimitId":{}}}"#.utf8)
            )
        ) { error in
            guard case UsageProviderError.noUsageLimits = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDecodeSnapshot_whenServerReturnsError_shouldSurfaceMessage() {
        XCTAssertThrowsError(
            try CodexRateLimitsDecoder.decodeSnapshot(
                from: Data(#"{"id":1,"error":{"code":-32000,"message":"not signed in"}}"#.utf8)
            )
        ) { error in
            guard case let UsageProviderError.protocolFailure(message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "not signed in")
        }
    }

    private static let multipleBucketsResponse = #"""
    {
      "id": 1,
      "result": {
        "rateLimits": {
          "limitId": "codex",
          "primary": {"usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1800003600},
          "secondary": {"usedPercent": 60, "windowDurationMins": 10080, "resetsAt": 1800604800},
          "credits": {"hasCredits": true, "unlimited": false, "balance": "120.5"}
        },
        "rateLimitsByLimitId": {
          "codex": {
            "limitId": "codex",
            "limitName": null,
            "primary": {"usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1800003600},
            "secondary": {"usedPercent": 60, "windowDurationMins": 10080, "resetsAt": 1800604800},
            "credits": {"hasCredits": true, "unlimited": false, "balance": "120.5"}
          },
          "codex_other": {
            "limitId": "codex_other",
            "limitName": "代码审查",
            "primary": {"usedPercent": 42, "windowDurationMins": 60, "resetsAt": 1800007200},
            "secondary": null,
            "credits": null
          }
        }
      }
    }
    """#

    private static let legacyResponse = #"""
    {
      "id": 1,
      "result": {
        "rateLimits": {
          "limitId": "codex",
          "primary": {"usedPercent": 97, "windowDurationMins": 10080, "resetsAt": 1800604800},
          "secondary": null,
          "credits": {"hasCredits": false, "unlimited": false, "balance": "0"}
        }
      }
    }
    """#

    private static let unlimitedCreditsResponse = #"""
    {
      "id": 1,
      "result": {
        "rateLimits": {
          "limitId": "codex",
          "primary": {"usedPercent": 1, "windowDurationMins": 300, "resetsAt": null},
          "credits": {"hasCredits": true, "unlimited": true, "balance": null}
        }
      }
    }
    """#
}
