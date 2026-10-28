import XCTest
@testable import DevMeter

final class CodexLocalUsageProviderTests: XCTestCase {
    func testFetchSnapshot_whenNpmSymlinkHasSiblingNodeAndGUIPath_shouldCompleteHandshake() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DevMeter-NVM-\(UUID().uuidString)")
        let bin = directory.appendingPathComponent("bin")
        let library = directory.appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = library.appendingPathComponent("codex.js")
        // 用系统 sh 作为测试解释器；关键是 env 必须从原 npm bin 找到 node，不能依赖测试进程 PATH。
        try #"""
        #!/usr/bin/env node
        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *'refreshToken'*)
              case "$line" in *'"id":3'*) id=3 ;; *) id=2 ;; esac
              printf '{"id":%s,"result":{"account":null}}\n' "$id" ;;
            *'rateLimits'*) printf '%s\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":12}}}}' ;;
          esac
        done
        """#.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let launcher = bin.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: script)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("node"), withDestinationURL: URL(fileURLWithPath: "/bin/sh"))
        let provider = CodexLocalUsageProvider(executableURL: launcher,
                                             environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"], timeout: .seconds(2))
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.limits.first?.remainingPercent, 88)
    }

    func testProcessEnvironment_withoutSiblingNode_preservesNativeCLIRuntimeEnvironment() {
        let original = ["PATH": "/usr/bin:/bin", "CUSTOM_FLAG": "kept"]
        let executable = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("codex")
        XCTAssertEqual(CodexProcessEnvironment.make(executableURL: executable, environment: original), original)
    }

    func testFetchSnapshot_whenLauncherExits127_preservesActualExitStatus() async throws {
        let script = try makeExecutableScript(contents: "#!/bin/sh\nIFS= read -r line\nexit 127\n")
        defer { try? FileManager.default.removeItem(at: script) }
        let provider = CodexLocalUsageProvider(executableURL: script, timeout: .seconds(2))
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("Expected process exit")
        } catch UsageProviderError.processExited(let status) {
            XCTAssertEqual(status, 127)
        } catch { XCTFail("Unexpected error: \(error)") }
    }

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
                *'refreshToken'*)
                  case "$line" in
                    *'"id":3'*) request_id=3 ;;
                    *) request_id=2 ;;
                  esac
                  printf '{"id":%s,"result":{"account":{"type":"chatgpt","email":"fixture@example.invalid","planType":"plus"}}}\n' "$request_id"
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
        XCTAssertNotNil(snapshot.accountKey)
    }

    func testIdentity_whenPersonalAccount_returnsSaltedPlanScopedKeyWithoutEmail() {
        let response = Data(#"{"id":2,"result":{"account":{"type":"chatgpt","email":"fixture@example.invalid","planType":"plus"}}}"#.utf8)
        let key = CodexAccountIdentity.key(from: response, salt: "installation-a")
        XCTAssertEqual(key?.count, 64)
        XCTAssertFalse(key?.contains("fixture") ?? true)
        XCTAssertEqual(key, CodexAccountIdentity.key(from: response, salt: "installation-a"))
        XCTAssertNotEqual(key, CodexAccountIdentity.key(from: response, salt: "installation-b"))
        let upgraded = Data(#"{"id":2,"result":{"account":{"type":"chatgpt","email":"fixture@example.invalid","planType":"pro"}}}"#.utf8)
        XCTAssertNotEqual(key, CodexAccountIdentity.key(from: upgraded, salt: "installation-a"))
    }

    func testIdentity_whenOrganizationUnknownOrMissing_neverCreatesAmbiguousHistoryScope() {
        for body in [
            #"{"id":2,"result":{"account":{"type":"chatgpt","email":"fixture@example.invalid","planType":"business"}}}"#,
            #"{"id":2,"result":{"account":{"type":"chatgpt","email":null,"planType":"plus"}}}"#,
            #"{"id":2,"result":{"account":{"type":"apiKey"}}}"#,
            #"{"id":2,"error":{"message":"unsupported"}}"#
        ] {
            XCTAssertNil(CodexAccountIdentity.key(from: Data(body.utf8), salt: "test"))
        }
    }

    func testFetchSnapshot_whenAccountChangesDuringRead_rejectsMixedAccountResult() async throws {
        let url = try makeExecutableScript(contents: #"""
        #!/bin/sh
        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *'refreshToken'*)
              case "$line" in
                *'"id":3'*) request_id=3; address=second@example.invalid ;;
                *) request_id=2; address=first@example.invalid ;;
              esac
              printf '{"id":%s,"result":{"account":{"type":"chatgpt","email":"%s","planType":"plus"}}}\n' "$request_id" "$address"
              ;;
            *'rateLimits'*) printf '%s\n' '{"id":1,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20}}}}' ;;
          esac
        done
        """#)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await CodexLocalUsageProvider(executableURL: url, timeout: .seconds(2)).fetchSnapshot()
            XCTFail("A mixed-account snapshot must be rejected")
        } catch {
            guard case UsageProviderError.protocolFailure = error else { return XCTFail("Unexpected error: \(error)") }
        }
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
            .appendingPathComponent("DevMeterTests", isDirectory: true)
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
