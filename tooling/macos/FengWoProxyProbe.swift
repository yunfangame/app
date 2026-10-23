import CryptoKit
import Foundation
import SystemConfiguration

enum ProbeFailure: Error { case invalidInput, unavailable }

struct ProbeSnapshotFailure: Error {
    let stage: String
    let reason: String
    var systemError = 0
    var details: [String: Any] = [:]
}

func canonical(_ value: Any) throws -> Any {
    if let data = value as? Data { return ["type": "data", "value": data.base64EncodedString()] }
    if let date = value as? Date { return ["type": "date", "value": date.timeIntervalSince1970] }
    if let dictionary = value as? [String: Any] { return try dictionary.mapValues(canonical) }
    if let array = value as? [Any] { return try array.map(canonical) }
    if value is String || value is NSNumber { return value }
    throw ProbeFailure.invalidInput
}

func digest(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: canonical(value), options: [.sortedKeys, .fragmentsAllowed])
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func logicalProxies(_ source: [String: Any]) -> [String: Any] {
    var result = source
    for prefix in ["HTTP", "HTTPS", "SOCKS"] {
        let enabled = (source[prefix + "Enable"] as? NSNumber)?.intValue ?? 0
        result[prefix + "Enable"] = enabled
        if enabled == 0 {
            result.removeValue(forKey: prefix + "Proxy")
            result.removeValue(forKey: prefix + "Port")
        }
    }
    for key in ["ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable", "ExcludeSimpleHostnames"] {
        result[key] = (source[key] as? NSNumber)?.intValue ?? 0
    }
    if result["ProxyAutoConfigEnable"] as? Int == 0 { result.removeValue(forKey: "ProxyAutoConfigURLString") }
    result["ExceptionsList"] = source["ExceptionsList"] ?? [String]()
    return result
}

func routeInterface(_ destination: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/sbin/route")
    process.arguments = ["-n", "get", destination]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw ProbeFailure.unavailable }
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let parts = line.split(whereSeparator: { $0.isWhitespace })
        if parts.count == 2 && parts[0] == "interface:" { return String(parts[1]) }
    }
    throw ProbeFailure.unavailable
}

func snapshot() throws -> [String: Any] {
    guard getuid() != 0 else { throw ProbeSnapshotFailure(stage: "execution_context", reason: "root_not_allowed") }
    guard let preferences = SCPreferencesCreate(nil, "FengWo read-only probe" as CFString, nil) else {
        throw ProbeSnapshotFailure(stage: "preferences", reason: "preferences_unavailable", systemError: Int(SCError()))
    }
    guard let currentSet = SCNetworkSetCopyCurrent(preferences),
          let setID = SCNetworkSetGetSetID(currentSet) as String?,
          let services = SCNetworkSetCopyServices(currentSet) as? [SCNetworkService] else {
        throw ProbeSnapshotFailure(stage: "current_network_location", reason: "current_set_unavailable", systemError: Int(SCError()))
    }
    guard let dynamic = SCDynamicStoreCreate(nil, "FengWo read-only probe" as CFString, nil, nil) else {
        throw ProbeSnapshotFailure(stage: "dynamic_store", reason: "dynamic_store_unavailable", systemError: Int(SCError()))
    }
    let global = ["IPv4", "IPv6"].compactMap { family in
        SCDynamicStoreCopyValue(dynamic, "State:/Network/Global/\(family)" as CFString) as? [String: Any]
    }.first { $0["PrimaryService"] is String }
    guard let primaryID = global?["PrimaryService"] as? String else {
        throw ProbeSnapshotFailure(stage: "primary_service", reason: "primary_service_unavailable")
    }
    var saved = [String: Any]()
    var logical = [String: Any]()
    var primary = [String: Any]()
    var primaryName = ""
    var active = false
    let enableKeys = ["HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable"]
    for service in services {
        guard let id = SCNetworkServiceGetServiceID(service) as String?,
              let name = SCNetworkServiceGetName(service) as String? else {
            throw ProbeSnapshotFailure(stage: "service_identity", reason: "service_identity_unavailable")
        }
        let config: [String: Any]
        if let networkProtocol = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies) {
            config = SCNetworkProtocolGetConfiguration(networkProtocol) as? [String: Any] ?? [:]
        } else { config = [:] }
        for key in enableKeys {
            if let value = config[key] {
                guard let number = value as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      !["f", "d"].contains(String(cString: number.objCType)),
                      number == 0 || number == 1 else {
                    throw ProbeSnapshotFailure(stage: "proxy_configuration", reason: "invalid_enable_flag")
                }
            }
        }
        saved[id] = config
        logical[id] = logicalProxies(config)
        if enableKeys.contains(where: { (config[$0] as? NSNumber)?.intValue ?? 0 != 0 }) { active = true }
        if id == primaryID { primary = config; primaryName = name }
    }
    guard !primaryName.isEmpty else {
        throw ProbeSnapshotFailure(stage: "primary_service", reason: "primary_not_in_current_set")
    }
    let nativeRead: [String: Any]
    do {
        nativeRead = try FengWoProxyAuthorization().readAutoDiscovery(primaryName)
    } catch let error as FengWoProxyError {
        throw ProbeSnapshotFailure(stage: "native_auto_discovery", reason: error.reason, systemError: error.code, details: error.details)
    }
    guard nativeRead["serviceID"] as? String == primaryID,
          nativeRead["networkSetID"] as? String == setID else {
        throw ProbeSnapshotFailure(stage: "native_service_identity", reason: "service_identity_changed")
    }
    let ports = ["HTTPPort", "HTTPSPort", "SOCKSPort"].compactMap { (primary[$0] as? NSNumber)?.intValue }
    let loopback = zip(["HTTP", "HTTPS", "SOCKS"], ports).allSatisfy { prefix, port in
        (primary[prefix + "Enable"] as? NSNumber)?.intValue == 1 &&
        primary[prefix + "Proxy"] as? String == "127.0.0.1" && (1...65535).contains(port)
    } && ports.count == 3 && Set(ports).count == 1
    var routes: [String]
    do { routes = try [routeInterface("1.1.1.1"), routeInterface("8.8.8.8")] }
    catch { throw ProbeSnapshotFailure(stage: "route_lookup", reason: "ipv4_route_unavailable") }
    if let ipv6 = try? routeInterface("2001:4860:4860::8888") { routes.append(ipv6) }
    let effective = SCDynamicStoreCopyProxies(dynamic) as? [String: Any] ?? [:]
    let effectiveLoopback = ["HTTP", "HTTPS", "SOCKS"].allSatisfy { prefix in
        (effective[prefix + "Enable"] as? NSNumber)?.intValue == 1 &&
        effective[prefix + "Proxy"] as? String == "127.0.0.1" &&
        (effective[prefix + "Port"] as? NSNumber)?.intValue == ports.first
    }
    return [
        "timestamp": Date().timeIntervalSince1970,
        "uid": Int(getuid()), "readOnly": true,
        "primaryServiceDigest": try digest([setID, primaryID]),
        "configurationDigest": try digest(saved),
        "logicalDigest": try digest(logical),
        "routeDigest": try digest(routes),
        "tunRouteObserved": routes.contains(where: { $0.hasPrefix("utun") }),
        "configuredProxyActive": active,
        "loopbackProxyVerified": loopback && effectiveLoopback,
        "proxyPort": loopback ? ports[0] : 0,
        "autoDiscoveryNativeReadable": nativeRead["enabled"] is Bool,
        "networkServiceCount": services.count,
    ]
}

func audit(_ directory: String, since: TimeInterval, phase: String) throws -> [String: Any] {
    guard ["connected", "disconnected", "quit", "collect"].contains(phase) else { throw ProbeFailure.invalidInput }
    var entries = [[String: Any]]()
    let decoder = ISO8601DateFormatter()
    decoder.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    for suffix in [".2", ".1", ""] {
        let url = URL(fileURLWithPath: directory).appendingPathComponent("events.jsonl" + suffix)
        guard FileManager.default.fileExists(atPath: url.path) else { continue }
        let data = try Data(contentsOf: url)
        guard data.count <= 2 * 1024 * 1024 else { throw ProbeFailure.invalidInput }
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let bytes = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let timestamp = entry["timestamp"] as? String,
                  let date = decoder.date(from: timestamp), date.timeIntervalSince1970 >= since,
                  let event = entry["event"] as? String,
                  event.hasPrefix("system_proxy.") || event.hasPrefix("system_exit.") || event.hasPrefix("core.lifecycle.")
            else { continue }
            entries.append(entry)
        }
    }
    let candidate = entries.last { entry in
        guard let event = entry["event"] as? String, let fields = entry["fields"] as? [String: Any],
              fields["stale_request"] as? Bool != true else { return false }
        if phase == "quit" { return event == "system_proxy.shutdown.completed" }
        return event == "system_proxy.apply.completed" &&
            fields["running_requested"] as? Bool == (phase == "connected") &&
            (phase != "connected" || fields["system_proxy_requested"] as? Bool == true)
    }
    let nativeWrite = entries.contains { entry in
        guard entry["event"] as? String == "system_proxy.native.write.completed",
              let fields = entry["fields"] as? [String: Any],
              fields["success"] as? Bool == true else { return false }
        return entry["session"] as? String == candidate?["session"] as? String
    }
    let matched = (candidate?["fields"] as? [String: Any])?["success"] as? Bool == true &&
        (phase != "connected" || nativeWrite)
    return ["phase": phase, "matched": matched, "eventCount": entries.count, "events": entries]
}

func selfTest() throws {
    let initial: [String: Any] = ["UnrelatedData": Data([0, 255]), "ExceptionsList": ["localhost"]]
    var stopped = initial
    stopped["HTTPEnable"] = 0
    stopped["HTTPProxy"] = "127.0.0.1"
    stopped["HTTPPort"] = 7890
    stopped["ProxyAutoDiscoveryEnable"] = 0
    guard try digest(logicalProxies(initial)) == digest(logicalProxies(stopped)) else { throw ProbeFailure.invalidInput }
    stopped["HTTPEnable"] = 1
    guard try digest(logicalProxies(initial)) != digest(logicalProxies(stopped)) else { throw ProbeFailure.invalidInput }
    stopped = initial; stopped["UnrelatedData"] = Data([1, 2])
    guard try digest(logicalProxies(initial)) != digest(logicalProxies(stopped)) else { throw ProbeFailure.invalidInput }
    let args = [["-setwebproxy", "Wi-Fi", "127.0.0.1", "7890"]]
    let changed = try FengWoProxyAuthorization.nextConfiguration(args, current: initial)
    guard changed["HTTPEnable"] as? Int == 1, changed["UnrelatedData"] as? Data == Data([0, 255]) else { throw ProbeFailure.invalidInput }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let timestamp = formatter.string(from: Date())
    func entry(_ event: String, _ fields: [String: Any], session: String = "fixture") -> [String: Any] {
        ["event": event, "fields": fields, "timestamp": timestamp, "session": session]
    }
    let applied = entry("system_proxy.apply.completed", ["running_requested": true, "system_proxy_requested": true, "success": true])
    let written = entry("system_proxy.native.write.completed", ["success": true])
    func verify(_ entries: [[String: Any]], _ expected: Bool, phase: String = "connected") throws {
        var data = Data()
        for entry in entries { data.append(try JSONSerialization.data(withJSONObject: entry)); data.append(10) }
        try data.write(to: directory.appendingPathComponent("events.jsonl"))
        let result = try audit(directory.path, since: Date().timeIntervalSince1970 - 10, phase: phase)
        guard result["matched"] as? Bool == expected else { throw ProbeFailure.invalidInput }
    }
    try verify([applied], false)
    try verify([written, applied], true)
    try verify([written, applied, entry("system_proxy.apply.completed", ["running_requested": true, "system_proxy_requested": true, "success": false])], false)
    try verify([entry("system_proxy.native.write.completed", ["success": true], session: "other"), applied], false)
    try verify([entry("system_proxy.apply.completed", ["running_requested": false, "success": true])], true, phase: "disconnected")
    try verify([entry("system_proxy.shutdown.completed", ["success": false])], false, phase: "quit")
    try verify([entry("system_proxy.shutdown.completed", ["success": true])], true, phase: "quit")
}

@main
enum FengWoProxyProbe {
    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let result: [String: Any]
            if args == ["snapshot"] { result = try snapshot() }
            else if args == ["self-test"] { try selfTest(); result = ["selfTestsPassed": true, "systemSettingsWritten": false] }
            else if args.count == 4 && args[0] == "audit", let time = Double(args[2]) {
                result = try audit(args[1], since: time, phase: args[3])
            } else { throw ProbeFailure.invalidInput }
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data + Data([10]))
        } catch {
            let failure = error as? ProbeSnapshotFailure ?? ProbeSnapshotFailure(stage: "probe", reason: "read_failed")
            let details = failure.details.merging([
                "stage": failure.stage, "reason": failure.reason, "system_error": failure.systemError,
            ]) { _, new in new }
            if let data = try? JSONSerialization.data(withJSONObject: ["readOnly": true, "complete": false, "failure": details], options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data + Data([10]))
            }
            FileHandle.standardError.write(Data("Read-only probe failed at \(failure.stage): \(failure.reason); no system settings were written.\n".utf8))
            exit(2)
        }
    }
}
