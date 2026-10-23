import Foundation
import Security

final class Fixture {
    var identity = "11111111-1111-4111-8111-111111111111"
    var name = "Wi-Fi"
    var networkSetID = "fixture-location"
    var configuration: [String: Any] = [
        "HTTPEnable": 0, "HTTPProxy": "before.invalid", "HTTPPort": 8080,
        "HTTPSEnable": 0, "HTTPSProxy": "before.invalid", "HTTPSPort": 8080,
        "SOCKSEnable": 0, "SOCKSProxy": "before.invalid", "SOCKSPort": 8080,
        "ProxyAutoConfigEnable": 0, "ProxyAutoConfigURLString": "https://before.invalid/pac",
        "ExceptionsList": ["localhost"], "UnrelatedData": Data([0, 255, 1]),
    ]
    var requiresAuthorization = true
    var applyFails = false
    var writes = 0
    var authorizationCount = 0
}

final class FixtureStore: FengWoProxyPreferencesStore {
    let fixture: Fixture
    let authorized: Bool
    init(_ fixture: Fixture, _ authorized: Bool) { self.fixture = fixture; self.authorized = authorized }
    func read(_ service: String) throws -> FengWoProxySnapshot {
        guard fixture.name == service else { throw FengWoProxyError(reason: "service_not_unique", code: 0) }
        return FengWoProxySnapshot(serviceID: fixture.identity, serviceName: fixture.name, proxies: fixture.configuration, networkSetID: fixture.networkSetID)
    }
    func write(_ snapshot: FengWoProxySnapshot, proxies: [String: Any], canCommit: () -> Bool) throws {
        if fixture.requiresAuthorization && !authorized {
            throw FengWoProxyError(reason: "preferences_lock", code: 1003)
        }
        guard try read(snapshot.serviceName).matches(snapshot) else {
            throw FengWoProxyError(reason: "settings_changed", code: 0)
        }
        guard canCommit() else { throw FengWoProxyError(reason: "superseded", code: 0) }
        fixture.configuration = proxies
        fixture.writes += 1
        if fixture.applyFails { throw FengWoProxyError(reason: "preferences_apply", code: 1, committed: true) }
    }
}

@main
enum ProxyAuthorizationTests {
    static var passed = 0
    static var failures = [String]()
    static let start = [
        ["-setautoproxystate", "Wi-Fi", "off"],
        ["-setproxyautodiscovery", "Wi-Fi", "off"],
        ["-setwebproxy", "Wi-Fi", "127.0.0.1", "17980"],
        ["-setsecurewebproxy", "Wi-Fi", "127.0.0.1", "17980"],
        ["-setsocksfirewallproxy", "Wi-Fi", "127.0.0.1", "17980"],
        ["-setproxybypassdomains", "Wi-Fi", "localhost", "*.internal.invalid"],
        ["-setwebproxystate", "Wi-Fi", "on"],
        ["-setsecurewebproxystate", "Wi-Fi", "on"],
        ["-setsocksfirewallproxystate", "Wi-Fi", "on"],
    ]
    static let stop = [
        ["-setwebproxy", "Wi-Fi", "before.invalid", "8080"],
        ["-setsecurewebproxy", "Wi-Fi", "before.invalid", "8080"],
        ["-setsocksfirewallproxy", "Wi-Fi", "before.invalid", "8080"],
        ["-setproxybypassdomains", "Wi-Fi", "localhost"],
        ["-setwebproxystate", "Wi-Fi", "off"],
        ["-setsecurewebproxystate", "Wi-Fi", "off"],
        ["-setsocksfirewallproxystate", "Wi-Fi", "off"],
        ["-setautoproxystate", "Wi-Fi", "off"],
        ["-setproxyautodiscovery", "Wi-Fi", "off"],
    ]

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: message, code: 1) }
    }

    static func test(_ name: String, _ body: () throws -> Void) {
        do { try body(); passed += 1; print("PASS \(name)") }
        catch { failures.append(name); print("FAIL \(name): \(error)") }
    }

    static func engine(_ fixture: Fixture, authorize: (() -> OSStatus)? = nil) -> FengWoProxyAuthorization {
        FengWoProxyAuthorization(storeFactory: { FixtureStore(fixture, $0) }, authorizationRequest: {
            fixture.authorizationCount += 1
            return authorize?() ?? errAuthorizationSuccess
        })
    }

    static func main() throws {
        let current = FengWoProxyServiceCandidate(id: "current-wifi", name: "Wi-Fi")
        let other = FengWoProxyServiceCandidate(id: "other-location-wifi", name: "Wi-Fi")
        let duplicate = FengWoProxyServiceCandidate(id: "current-second-wifi", name: "Wi-Fi")
        let ethernet = FengWoProxyServiceCandidate(id: "current-ethernet", name: "Ethernet")
        test("duplicate names outside the current location no longer reject a valid service") {
            let services = [other, current, ethernet]
            try check(services.filter { $0.name == "Wi-Fi" }.count == 2, "legacy failure not reproduced")
            let selected = try FengWoProxyServiceSelection.resolve("Wi-Fi", services: services, currentServiceIDs: [current.id, ethernet.id], primaryServiceID: current.id)
            try check(selected.id == current.id && selected.strategy == "primary_current_set", "wrong scoped service")
            try check(selected.globalMatches == 2 && selected.scopedMatches == 1, "missing diagnostic counts")
        }
        test("same-location duplicate names remain ambiguous even with a known primary ID") {
            do {
                _ = try FengWoProxyServiceSelection.resolve("Wi-Fi", services: [current, duplicate], currentServiceIDs: [current.id, duplicate.id], primaryServiceID: duplicate.id)
                throw NSError(domain: "ambiguous CLI readback accepted", code: 1)
            } catch let error as FengWoProxyError {
                try check(error.reason == "service_not_unique", "ambiguous current-set names not rejected")
            }
        }
        for primary in [nil, other.id, ethernet.id] as [String?] {
            test("ambiguous current services cannot use an unrelated primary \(primary ?? "none")") {
                do {
                    _ = try FengWoProxyServiceSelection.resolve("Wi-Fi", services: [other, current, duplicate, ethernet], currentServiceIDs: [current.id, duplicate.id, ethernet.id], primaryServiceID: primary)
                    throw NSError(domain: "ambiguous service accepted", code: 1)
                } catch let error as FengWoProxyError {
                    try check(error.reason == "service_not_unique", "wrong ambiguity reason")
                    try check(error.details["scoped_match_count"] as? Int == 2, "missing ambiguity count")
                }
            }
        }
        test("a service in another location is not a fallback") {
            do {
                _ = try FengWoProxyServiceSelection.resolve("Wi-Fi", services: [other, ethernet], currentServiceIDs: [ethernet.id], primaryServiceID: other.id)
                throw NSError(domain: "foreign location accepted", code: 1)
            } catch let error as FengWoProxyError {
                try check(error.reason == "service_not_found", "missing service not distinguished")
                try check(error.details["global_match_count"] as? Int == 1, "missing global count")
            }
        }
        test("a snapshot ID stays pinned when the primary service changes") {
            let selected = try FengWoProxyServiceSelection.resolve("Wi-Fi", services: [current, duplicate], currentServiceIDs: [current.id, duplicate.id], primaryServiceID: duplicate.id, expectedServiceID: current.id)
            try check(selected.id == current.id && selected.strategy == "snapshot_id", "snapshot retargeted")
        }
        for candidates in [[duplicate], [FengWoProxyServiceCandidate(id: current.id, name: "Renamed")]] {
            test("removed or renamed snapshot identity fails without choosing another service") {
                do {
                    _ = try FengWoProxyServiceSelection.resolve("Wi-Fi", services: candidates, currentServiceIDs: [current.id, duplicate.id], primaryServiceID: duplicate.id, expectedServiceID: current.id)
                    throw NSError(domain: "snapshot retargeted", code: 1)
                } catch let error as FengWoProxyError {
                    try check(error.reason == "service_identity_changed", "wrong identity failure")
                }
            }
        }
        test("service discovery diagnostics contain no service names or IDs") {
            let selected = try FengWoProxyServiceSelection.resolve("Wi-Fi", services: [current, other], currentServiceIDs: [current.id], primaryServiceID: current.id)
            let encoded = String(data: try JSONSerialization.data(withJSONObject: selected.diagnostics), encoding: .utf8)!
            try check(!encoded.contains("Wi-Fi") && !encoded.contains(current.id) && !encoded.contains(other.id), "private identity logged")
        }
        test("authorization right matches the SystemConfiguration helper") {
            try check(FengWoProxyAuthorization.authorizationRight == "system.services.systemconfiguration.network", "incorrect authorization right")
        }
        for conflict in ["service-id", "network-location"] {
            test("caller-pinned \(conflict) mismatch stops before authorization") {
                let fixture = Fixture()
                let value = engine(fixture)
                let result = value.perform(start,
                    expectedServiceID: conflict == "service-id" ? "other-id" : fixture.identity,
                    expectedNetworkSetID: conflict == "network-location" ? "other-location" : fixture.networkSetID)
                try check(result["reason"] as? String == (conflict == "service-id" ? "service_identity_changed" : "network_location_changed"), "wrong pinned failure")
                try check(fixture.writes == 0 && fixture.authorizationCount == 0, "wrong target reached mutation")
            }
        }
        test("matching caller identity permits scoped authorization and restoration") {
            let fixture = Fixture(); let value = engine(fixture)
            try check(value.perform(start, expectedServiceID: fixture.identity, expectedNetworkSetID: fixture.networkSetID)["success"] as? Bool == true, "pinned start failed")
            try check(value.perform(stop, expectedServiceID: fixture.identity, expectedNetworkSetID: fixture.networkSetID)["success"] as? Bool == true, "pinned restore failed")
            try check(fixture.writes == 2 && fixture.authorizationCount == 1, "pinned lifecycle incorrect")
        }
        test("scoped authorization, connection and disconnection preserve unrelated settings") {
            let fixture = Fixture()
            let engine = engine(fixture)
            let connected = engine.perform(start)
            try check(connected["success"] as? Bool == true, "connection failed")
            try check(connected["authorizationUsed"] as? Bool == true, "authorization not recorded")
            try check(fixture.configuration["HTTPPort"] as? Int == 17980, "wrong proxy")
            try check(fixture.configuration["UnrelatedData"] as? Data == Data([0, 255, 1]), "CFData lost")
            let disconnected = engine.perform(stop)
            try check(disconnected["success"] as? Bool == true, "disconnect failed")
            try check(fixture.authorizationCount == 1, "cleanup should reuse authorization session")
            try check(fixture.configuration["HTTPEnable"] as? Int == 0, "HTTP remains enabled")
            try check(fixture.configuration["HTTPProxy"] as? String == "before.invalid", "original endpoint not restored")
            try check(fixture.writes == 2, "unexpected write count")
        }
        test("direct writable settings need no authorization prompt") {
            let fixture = Fixture(); fixture.requiresAuthorization = false
            try check(engine(fixture).perform(start)["success"] as? Bool == true, "direct write failed")
            try check(fixture.authorizationCount == 0, "unnecessary prompt")
        }
        for status in [errAuthorizationCanceled, errAuthorizationDenied] {
            test("authorization refusal \(status) cannot mutate settings") {
                let fixture = Fixture()
                let result = engine(fixture, authorize: { status }).perform(start)
                try check(result["success"] as? Bool == false, "false success")
                try check(result["authorizationCancelled"] as? Bool == (status == errAuthorizationCanceled), "cancel classification")
                try check(fixture.writes == 0, "write after authorization refusal")
            }
        }
        for conflict in ["port", "service-id", "service-name", "network-location"] {
            test("post-authorization conflict \(conflict) prevents writes") {
                let fixture = Fixture()
                let engine = engine(fixture, authorize: {
                    if conflict == "port" { fixture.configuration["HTTPPort"] = 9000 }
                    if conflict == "service-id" { fixture.identity = "22222222-2222-4222-8222-222222222222" }
                    if conflict == "service-name" { fixture.name = "Other" }
                    if conflict == "network-location" { fixture.networkSetID = "other-location" }
                    return errAuthorizationSuccess
                })
                try check(engine.perform(start)["success"] as? Bool == false, "conflict falsely succeeded")
                try check(fixture.writes == 0, "overwrote external configuration")
            }
        }
        test("disconnect while authorization pending invalidates old request") {
            let fixture = Fixture()
            var value: FengWoProxyAuthorization!
            value = engine(fixture, authorize: { value.invalidate(); return errAuthorizationSuccess })
            let result = value.perform(start)
            try check(result["reason"] as? String == "superseded", "old request not cancelled")
            try check(fixture.writes == 0, "old request committed")
        }
        test("exit while authorization pending invalidates all later writes") {
            let fixture = Fixture()
            var value: FengWoProxyAuthorization!
            value = engine(fixture, authorize: { value.invalidate(terminating: true); return errAuthorizationSuccess })
            try check(value.perform(start)["success"] as? Bool == false, "exit ignored")
            try check(value.perform(start)["reason"] as? String == "superseded", "write accepted after exit")
            try check(fixture.writes == 0, "write after exit")
        }
        test("committed apply failure remains visible and can be restored") {
            let fixture = Fixture(); fixture.applyFails = true
            let engine = engine(fixture)
            let result = engine.perform(start)
            try check(result["success"] as? Bool == false, "apply failure hidden")
            try check(result["committed"] as? Bool == true, "lost pending cleanup ownership")
            fixture.applyFails = false
            try check(engine.perform(stop)["success"] as? Bool == true, "cleanup failed")
        }
        test("missing WPAD is read as off without mutating or authorizing") {
            let fixture = Fixture()
            let result = try engine(fixture).readAutoDiscovery("Wi-Fi")
            try check(result["enabled"] as? Bool == false, "missing flag not off")
            try check(result["settingPresent"] as? Bool == false, "presence incorrect")
            try check(fixture.writes == 0 && fixture.authorizationCount == 0, "read mutated settings")
        }
        for value: Any in [true, "0", 2, 0.0] {
            test("invalid WPAD type \(type(of: value))/\(value) stays unknown") {
                let fixture = Fixture(); fixture.configuration["ProxyAutoDiscoveryEnable"] = value
                do { _ = try engine(fixture).readAutoDiscovery("Wi-Fi"); throw NSError(domain: "accepted invalid WPAD", code: 1) }
                catch is FengWoProxyError {}
            }
        }
        for port in ["0", "65536", "bad"] {
            test("invalid endpoint port \(port) rejected before authorization") {
                let fixture = Fixture()
                let result = engine(fixture).perform([["-setwebproxy", "Wi-Fi", "127.0.0.1", port]])
                try check(result["reason"] as? String == "invalid_commands", "invalid endpoint accepted")
                try check(fixture.authorizationCount == 0 && fixture.writes == 0, "invalid endpoint reached mutation")
            }
        }
        for commands in [
            [["-setdnsservers", "Wi-Fi", "1.1.1.1"]],
            [["-setwebproxystate", "Wi-Fi", "off"], ["-setwebproxystate", "Other", "off"]],
            [["-setwebproxystate", "Wi-Fi", "on; echo bad"]],
            [["-setwebproxystate", "Wi-Fi", "on", "extra"]],
            [["-setwebproxy", "Wi-Fi", "127.0.0.1\0bad", "1234"]],
            [["-setautoproxyurl", "Wi-Fi", String(repeating: "x", count: 8193)]],
            [],
        ] {
            test("invalid command shape \(passed) rejected before authorization") {
                let fixture = Fixture()
                try check(engine(fixture).perform(commands)["reason"] as? String == "invalid_commands", "invalid command accepted")
                try check(fixture.authorizationCount == 0 && fixture.writes == 0, "invalid command reached mutation")
            }
        }
        test("idempotent repeat apply does not authorize or write again") {
            let fixture = Fixture(); let engine = engine(fixture)
            _ = engine.perform(start)
            let result = engine.perform(start)
            try check(result["writeSkipped"] as? Bool == true, "unchanged write not skipped")
            try check(fixture.writes == 1 && fixture.authorizationCount == 1, "repeat mutated")
        }
        let summary: [String: Any] = ["passed": passed, "failed": failures.count, "failures": failures, "hostNetworkSettingsChanged": false]
        print(String(data: try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]), encoding: .utf8)!)
        if !failures.isEmpty { exit(1) }
    }
}
