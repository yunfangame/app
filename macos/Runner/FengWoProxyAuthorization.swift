import Foundation
import Security
import SystemConfiguration

struct FengWoProxySnapshot {
    let serviceID: String
    let serviceName: String
    let proxies: [String: Any]
    let networkSetID: String?

    init(serviceID: String, serviceName: String, proxies: [String: Any], networkSetID: String? = nil) {
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.proxies = proxies
        self.networkSetID = networkSetID
    }

    func matches(_ other: FengWoProxySnapshot) -> Bool {
        serviceID == other.serviceID && serviceName == other.serviceName && networkSetID == other.networkSetID &&
            NSDictionary(dictionary: proxies).isEqual(to: other.proxies)
    }
}

struct FengWoProxyError: Error {
    let reason: String
    let code: Int
    var committed = false
    var details: [String: Any] = [:]
}

struct FengWoProxyServiceCandidate {
    let id: String
    let name: String
}

struct FengWoProxyServiceSelection {
    let id: String
    let strategy: String
    let scopedMatches: Int
    let globalMatches: Int

    var diagnostics: [String: Any] {
        ["selection": strategy, "scoped_match_count": scopedMatches, "global_match_count": globalMatches]
    }

    static func resolve(_ name: String, services: [FengWoProxyServiceCandidate], currentServiceIDs: Set<String>, primaryServiceID: String?, expectedServiceID: String? = nil) throws -> Self {
        let global = services.filter { $0.name == name }
        let scoped = global.filter { currentServiceIDs.contains($0.id) }
        let details: [String: Any] = ["scoped_match_count": scoped.count, "global_match_count": global.count]
        if let expectedServiceID {
            guard scoped.contains(where: { $0.id == expectedServiceID }) else {
                throw FengWoProxyError(reason: "service_identity_changed", code: 0, details: details)
            }
            return Self(id: expectedServiceID, strategy: "snapshot_id", scopedMatches: scoped.count, globalMatches: global.count)
        }
        if scoped.count == 1 {
            return Self(id: scoped[0].id, strategy: scoped[0].id == primaryServiceID ? "primary_current_set" : "unique_current_set", scopedMatches: 1, globalMatches: global.count)
        }
        throw FengWoProxyError(reason: scoped.isEmpty ? "service_not_found" : "service_not_unique", code: 0, details: details)
    }
}

protocol FengWoProxyPreferencesStore {
    func read(_ service: String) throws -> FengWoProxySnapshot
    func write(_ snapshot: FengWoProxySnapshot, proxies: [String: Any], canCommit: () -> Bool) throws
}

final class FengWoSystemProxyStore: FengWoProxyPreferencesStore {
    private let preferences: SCPreferences
    private let onDiscovery: (([String: Any]) -> Void)?

    init(authorization: AuthorizationRef?, onDiscovery: (([String: Any]) -> Void)? = nil) throws {
        guard let preferences = SCPreferencesCreateWithAuthorization(
            nil, "FengWo scoped system proxy" as CFString, nil, authorization
        ) else {
            throw FengWoProxyError(reason: "preferences_unavailable", code: Int(SCError()))
        }
        self.preferences = preferences
        self.onDiscovery = onDiscovery
    }

    private func service(_ name: String, expected: FengWoProxySnapshot? = nil) throws -> (SCNetworkService, String) {
        do {
            guard let currentSet = SCNetworkSetCopyCurrent(preferences),
                  let setID = SCNetworkSetGetSetID(currentSet) as String?,
                  let currentServices = SCNetworkSetCopyServices(currentSet) as? [SCNetworkService],
                  let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] else {
                throw FengWoProxyError(reason: "current_set_unavailable", code: Int(SCError()))
            }
            if let expected, expected.networkSetID != setID {
                throw FengWoProxyError(reason: "network_location_changed", code: 0)
            }
            let candidates = services.compactMap { service -> FengWoProxyServiceCandidate? in
                guard let id = SCNetworkServiceGetServiceID(service) as String?,
                      let name = SCNetworkServiceGetName(service) as String? else { return nil }
                return FengWoProxyServiceCandidate(id: id, name: name)
            }
            let currentIDs = Set(currentServices.compactMap { SCNetworkServiceGetServiceID($0) as String? })
            let dynamic = SCDynamicStoreCreate(nil, "FengWo proxy service identity" as CFString, nil, nil)
            var primaryID: String?
            if let dynamic {
                for family in ["IPv4", "IPv6"] {
                    if let state = SCDynamicStoreCopyValue(dynamic, "State:/Network/Global/\(family)" as CFString) as? [String: Any],
                       let id = state["PrimaryService"] as? String {
                        primaryID = id
                        break
                    }
                }
            }
            let selection = try FengWoProxyServiceSelection.resolve(
                name, services: candidates, currentServiceIDs: currentIDs,
                primaryServiceID: primaryID, expectedServiceID: expected?.serviceID
            )
            guard let target = currentServices.first(where: { SCNetworkServiceGetServiceID($0) as String? == selection.id }) else {
                throw FengWoProxyError(reason: "service_identity_changed", code: 0, details: selection.diagnostics)
            }
            onDiscovery?(selection.diagnostics.merging(["success": true]) { _, new in new })
            return (target, setID)
        } catch {
            let failure = error as? FengWoProxyError ?? FengWoProxyError(reason: "service_discovery", code: 0)
            onDiscovery?(failure.details.merging(["success": false, "reason": failure.reason]) { _, new in new })
            throw failure
        }
    }

    func read(_ name: String) throws -> FengWoProxySnapshot {
        let (networkService, setID) = try service(name)
        return try snapshot(networkService, networkSetID: setID)
    }

    private func snapshot(_ networkService: SCNetworkService, networkSetID: String) throws -> FengWoProxySnapshot {
        guard let networkProtocol = SCNetworkServiceCopyProtocol(networkService, kSCNetworkProtocolTypeProxies) else {
            throw FengWoProxyError(reason: "proxy_protocol_unavailable", code: Int(SCError()))
        }
        guard let serviceID = SCNetworkServiceGetServiceID(networkService) as String?,
              let name = SCNetworkServiceGetName(networkService) as String? else {
            throw FengWoProxyError(reason: "service_identity_unavailable", code: 0)
        }
        let configuration = SCNetworkProtocolGetConfiguration(networkProtocol) as? [String: Any] ?? [:]
        return FengWoProxySnapshot(
            serviceID: serviceID,
            serviceName: name,
            proxies: configuration,
            networkSetID: networkSetID
        )
    }

    func write(_ snapshot: FengWoProxySnapshot, proxies: [String: Any], canCommit: () -> Bool) throws {
        SCPreferencesSynchronize(preferences)
        guard SCPreferencesLock(preferences, false) else {
            throw FengWoProxyError(reason: "preferences_lock", code: Int(SCError()))
        }
        defer { SCPreferencesUnlock(preferences) }
        let (networkService, setID) = try service(snapshot.serviceName, expected: snapshot)
        let current = try self.snapshot(networkService, networkSetID: setID)
        guard current.matches(snapshot) else {
            throw FengWoProxyError(reason: "settings_changed", code: 0)
        }
        guard canCommit() else {
            throw FengWoProxyError(reason: "superseded", code: 0)
        }
        guard let networkProtocol = SCNetworkServiceCopyProtocol(networkService, kSCNetworkProtocolTypeProxies),
              SCNetworkProtocolSetConfiguration(networkProtocol, proxies as CFDictionary),
              SCPreferencesCommitChanges(preferences) else {
            throw FengWoProxyError(reason: "preferences_commit", code: Int(SCError()))
        }
        guard SCPreferencesApplyChanges(preferences) else {
            throw FengWoProxyError(reason: "preferences_apply", code: Int(SCError()), committed: true)
        }
    }
}

final class FengWoProxyAuthorization {
    typealias StoreFactory = (Bool) throws -> FengWoProxyPreferencesStore
    static let authorizationRight = "system.services.systemconfiguration.network"

    private let queue = DispatchQueue(label: "com.fengwo.proxy.authorization")
    private let stateLock = NSLock()
    private var generation = 0
    private var terminating = false
    private var authorization: AuthorizationRef?
    private var authorized = false
    private let storeFactory: StoreFactory?
    private let authorizationRequest: (() -> OSStatus)?
    var onProgress: ((String, [String: Any]) -> Void)?

    init(storeFactory: StoreFactory? = nil, authorizationRequest: (() -> OSStatus)? = nil) {
        self.storeFactory = storeFactory
        self.authorizationRequest = authorizationRequest
    }

    deinit {
        if let authorization { AuthorizationFree(authorization, []) }
    }

    func invalidate(terminating: Bool = false) {
        stateLock.lock()
        generation += 1
        self.terminating = self.terminating || terminating
        stateLock.unlock()
    }

    private func ticket() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation
    }

    private func current(_ value: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !terminating && generation == value
    }

    private func store(_ authorized: Bool) throws -> FengWoProxyPreferencesStore {
        if let storeFactory { return try storeFactory(authorized) }
        return try FengWoSystemProxyStore(authorization: authorized ? authorization : nil, onDiscovery: { [weak self] fields in
            self?.onProgress?("service.discovery.completed", fields)
        })
    }

    private func requestAuthorization() -> OSStatus {
        if let authorizationRequest { return authorizationRequest() }
        if authorization == nil {
            let status = AuthorizationCreate(nil, nil, [], &authorization)
            guard status == errAuthorizationSuccess else { return status }
        }
        guard let authorization else { return errAuthorizationInvalidRef }
        return Self.authorizationRight.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { pointer in
                var rights = AuthorizationRights(count: 1, items: pointer)
                return AuthorizationCopyRights(
                    authorization, &rights, nil,
                    [.interactionAllowed, .extendRights, .preAuthorize], nil
                )
            }
        }
    }

    private func commit(_ session: FengWoProxyPreferencesStore, before: FengWoProxySnapshot, next: [String: Any], ticket: Int) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !terminating && generation == ticket else {
            throw FengWoProxyError(reason: "superseded", code: 0)
        }
        try session.write(before, proxies: next, canCommit: { !self.terminating && self.generation == ticket })
    }

    func readAutoDiscovery(_ name: String) throws -> [String: Any] {
        let snapshot = try store(false).read(name)
        let value = snapshot.proxies["ProxyAutoDiscoveryEnable"]
        var enabled = false
        if let value {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  !["f", "d"].contains(String(cString: number.objCType)),
                  number == 0 || number == 1 else {
                throw FengWoProxyError(reason: "invalid_auto_discovery", code: 0)
            }
            enabled = number == 1
        }
        var result: [String: Any] = [
            "serviceID": snapshot.serviceID,
            "serviceName": name,
            "enabled": enabled,
            "settingPresent": value != nil,
            "backend": "system_configuration",
        ]
        if let setID = snapshot.networkSetID { result["networkSetID"] = setID }
        return result
    }

    static func nextConfiguration(_ commands: [[String]], current: [String: Any]) throws -> [String: Any] {
        guard !commands.isEmpty && commands.count <= 128 else {
            throw FengWoProxyError(reason: "invalid_commands", code: 0)
        }
        guard commands.flatMap({ $0 }).reduce(0, { $0 + $1.utf8.count }) <= 262144 else {
            throw FengWoProxyError(reason: "invalid_commands", code: 0)
        }
        var result = current
        let states = [
            "-setautoproxystate": "ProxyAutoConfigEnable",
            "-setproxyautodiscovery": "ProxyAutoDiscoveryEnable",
            "-setwebproxystate": "HTTPEnable",
            "-setsecurewebproxystate": "HTTPSEnable",
            "-setsocksfirewallproxystate": "SOCKSEnable",
        ]
        let endpoints = ["-setwebproxy": "HTTP", "-setsecurewebproxy": "HTTPS", "-setsocksfirewallproxy": "SOCKS"]
        var serviceName: String?
        for args in commands {
            guard args.count >= 3 && args.count <= 1024,
                  !args[1].isEmpty,
                  args.allSatisfy({ $0.utf8.count <= 8192 && !$0.contains("\0") }),
                  serviceName == nil || serviceName == args[1] else {
                throw FengWoProxyError(reason: "invalid_commands", code: 0)
            }
            serviceName = args[1]
            if let key = states[args[0]] {
                guard args.count == 3 && ["on", "off"].contains(args[2]) else {
                    throw FengWoProxyError(reason: "invalid_commands", code: 0)
                }
                result[key] = args[2] == "on" ? 1 : 0
            } else if let key = endpoints[args[0]] {
                guard args.count == 4 && !args[2].isEmpty,
                      let port = Int(args[3]), port >= 1 && port <= 65535 else {
                    throw FengWoProxyError(reason: "invalid_commands", code: 0)
                }
                result["\(key)Enable"] = 1
                result["\(key)Proxy"] = args[2]
                result["\(key)Port"] = port
            } else if args[0] == "-setautoproxyurl" && args.count == 3 {
                result["ProxyAutoConfigURLString"] = args[2]
                result["ProxyAutoConfigEnable"] = 1
            } else if args[0] == "-setproxybypassdomains" {
                result["ExceptionsList"] = args.count == 3 && args[2] == "Empty" ? [] : Array(args.dropFirst(2))
            } else {
                throw FengWoProxyError(reason: "invalid_commands", code: 0)
            }
        }
        return result
    }

    func perform(_ commands: [[String]], generation expectedGeneration: Int? = nil, expectedServiceID: String? = nil, expectedNetworkSetID: String? = nil) -> [String: Any] {
        let value = expectedGeneration ?? ticket()
        var attempted = false
        var used = authorized
        do {
            _ = try Self.nextConfiguration(commands, current: [:])
            guard current(value) else { throw FengWoProxyError(reason: "superseded", code: 0) }
            let session = try store(authorized)
            let before = try session.read(commands[0][1])
            if let expectedNetworkSetID, before.networkSetID != expectedNetworkSetID {
                throw FengWoProxyError(reason: "network_location_changed", code: 0)
            }
            if let expectedServiceID, before.serviceID != expectedServiceID {
                throw FengWoProxyError(reason: "service_identity_changed", code: 0)
            }
            let next = try Self.nextConfiguration(commands, current: before.proxies)
            if NSDictionary(dictionary: next).isEqual(to: before.proxies) {
                return ["success": true, "writeSkipped": true, "authorizationUsed": used, "backend": "system_configuration"]
            }
            do {
                try commit(session, before: before, next: next, ticket: value)
            } catch let error as FengWoProxyError where error.code == kSCStatusAccessError && !error.committed {
                guard current(value) else { throw FengWoProxyError(reason: "superseded", code: 0) }
                attempted = true
                onProgress?("authorization.started", ["backend": "system_configuration"])
                let status = requestAuthorization()
                onProgress?("authorization.completed", ["backend": "system_configuration", "status": Int(status)])
                guard status == errAuthorizationSuccess else {
                    throw FengWoProxyError(
                        reason: status == errAuthorizationCanceled ? "authorization_cancelled" : "authorization_denied",
                        code: Int(status)
                    )
                }
                guard current(value) else { throw FengWoProxyError(reason: "superseded", code: 0) }
                authorized = true
                used = true
                try commit(store(true), before: before, next: next, ticket: value)
            }
            return [
                "success": true, "authorizationAttempted": attempted,
                "authorizationUsed": used, "committed": true, "backend": "system_configuration",
            ]
        } catch {
            let failure = error as? FengWoProxyError ?? FengWoProxyError(reason: "native_failure", code: 0)
            return failure.details.merging([
                "success": false, "reason": failure.reason, "systemError": failure.code,
                "committed": failure.committed, "authorizationAttempted": attempted,
                "authorizationUsed": used, "authorizationCancelled": failure.reason == "authorization_cancelled",
                "backend": "system_configuration",
            ]) { _, new in new }
        }
    }

    func handle(method: String, arguments: Any?, completion: @escaping ([String: Any]?) -> Void) {
        if method == "invalidate" {
            invalidate()
            completion(["success": true])
            return
        }
        let value = ticket()
        queue.async {
            let result: [String: Any]
            if method == "readAutoDiscovery", let args = arguments as? [String: Any], let name = args["service"] as? String {
                do { result = try self.readAutoDiscovery(name) }
                catch {
                    let failure = error as? FengWoProxyError ?? FengWoProxyError(reason: "auto_discovery_unreadable", code: 0)
                    result = failure.details.merging(["success": false, "reason": failure.reason, "systemError": failure.code]) { _, new in new }
                }
            } else if method == "writeCommands", let args = arguments as? [String: Any], let commands = args["commands"] as? [[String]] {
                if let supplied = args["serviceIdentity"] {
                    if let identity = supplied as? [String: String], identity.count == 2,
                       let id = identity["serviceID"], UUID(uuidString: id) != nil,
                       let setID = identity["networkSetID"], !setID.isEmpty, setID.utf8.count <= 128, !setID.contains("\0") {
                        result = self.perform(commands, generation: value, expectedServiceID: id, expectedNetworkSetID: setID)
                    } else {
                        result = ["success": false, "reason": "invalid_commands", "systemError": 0]
                    }
                } else {
                    result = self.perform(commands, generation: value)
                }
            } else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
