import Cocoa
import CryptoKit
import Darwin
import SQLite3

struct FengWoIdentityPreparation {
    let legacyImported: Bool
    let status: String

    var dictionary: [String: Any] {
        ["legacyImported": legacyImported, "status": status]
    }
}

final class FengWoIdentityMigration {
    static let markerName = ".fengwo-identity-v2.plist"
    private let files = FileManager.default
    private let root: URL
    private let sourceID: String
    private let destinationID: String
    private let readPreferences: (String) throws -> [String: Any]
    private let writePreferences: (String, [String: Any]) throws -> Void
    private let legacyRunning: () -> Bool
    private let checkpoint: (String) throws -> Void

    init(
        root: URL,
        sourceID: String,
        destinationID: String,
        readPreferences: @escaping (String) throws -> [String: Any],
        writePreferences: @escaping (String, [String: Any]) throws -> Void,
        legacyRunning: @escaping () -> Bool,
        checkpoint: @escaping (String) throws -> Void = { _ in }
    ) {
        self.root = root.standardizedFileURL
        self.sourceID = sourceID
        self.destinationID = destinationID
        self.readPreferences = readPreferences
        self.writePreferences = writePreferences
        self.legacyRunning = legacyRunning
        self.checkpoint = checkpoint
    }

    static func production() throws -> FengWoIdentityMigration {
        guard let identity = Bundle.main.bundleIdentifier,
              ["com.fengwo.accelerator", "com.fengwo.accelerator.debug"].contains(identity),
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { throw CocoaError(.fileReadInvalidFileName) }
        return FengWoIdentityMigration(
            root: support,
            sourceID: identity.hasSuffix(".debug") ? "com.follow.clash.debug" : "com.follow.clash",
            destinationID: identity,
            readPreferences: { domain in
                let defaults = domain == identity ? UserDefaults.standard : UserDefaults(suiteName: domain)
                guard let defaults = defaults else { throw CocoaError(.fileReadUnknown) }
                return defaults.persistentDomain(forName: domain) ?? [:]
            },
            writePreferences: { domain, values in
                let defaults = domain == identity ? UserDefaults.standard : UserDefaults(suiteName: domain)
                guard let defaults = defaults else { throw CocoaError(.fileWriteUnknown) }
                defaults.setPersistentDomain(values, forName: domain)
                guard defaults.synchronize(),
                      NSDictionary(dictionary: defaults.persistentDomain(forName: domain) ?? [:]).isEqual(to: values)
                else { throw CocoaError(.fileWriteUnknown) }
            },
            legacyRunning: {
                let source = identity.hasSuffix(".debug") ? "com.follow.clash.debug" : "com.follow.clash"
                return !NSRunningApplication.runningApplications(withBundleIdentifier: source).isEmpty
            }
        )
    }

    private var source: URL { root.appendingPathComponent(sourceID, isDirectory: true) }
    private var destination: URL { root.appendingPathComponent(destinationID, isDirectory: true) }
    private var transaction: URL { root.appendingPathComponent(".\(destinationID).identity-v2", isDirectory: true) }
    private var payload: URL { transaction.appendingPathComponent("payload", isDirectory: true) }
    private var journal: URL { transaction.appendingPathComponent("preferences.plist") }

    func prepare() throws -> FengWoIdentityPreparation {
        guard sourceID != destinationID,
              !sourceID.contains("/"), !destinationID.contains("/"),
              ["com.follow.clash", "com.follow.clash.debug"].contains(sourceID),
              ["com.fengwo.accelerator", "com.fengwo.accelerator.debug"].contains(destinationID),
              sourceID.hasSuffix(".debug") == destinationID.hasSuffix(".debug")
        else { return result("invalid_identity") }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let descriptor = open(root.appendingPathComponent(".\(destinationID).identity.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return result("migration_failed") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return result("migration_busy") }
        defer { flock(descriptor, LOCK_UN) }
        do {
            let existing = try readPreferences(destinationID)
            if files.fileExists(atPath: destination.path) {
                try requireDirectory(destination)
                let marker = destination.appendingPathComponent(Self.markerName)
                if files.fileExists(atPath: marker.path) {
                    let record = try readPlist(marker)
                    guard markerMatches(record) else { return result("destination_present") }
                    if record["state"] as? String == "complete" {
                        return result("already_imported", imported: record["imported"] as? Bool == true)
                    }
                    if record["state"] as? String == "pending" {
                        return try completePending(record, existing: existing)
                    }
                }
                if !(try files.contentsOfDirectory(atPath: destination.path)).isEmpty {
                    return result("destination_present")
                }
            }
            if !existing.isEmpty {
                return result("destination_present")
            }
            if files.fileExists(atPath: transaction.path) {
                try requireDirectory(transaction)
                try files.removeItem(at: transaction)
            }
            let oldPreferences = try readPreferences(sourceID)
            guard validLegacyPreferences(oldPreferences) else { return result("no_compatible_legacy") }
            guard !legacyRunning() else { return result("legacy_running") }
            if files.fileExists(atPath: source.path) { try requireDirectory(source) }
            try privateDirectory(transaction)
            try privateDirectory(payload)
            let entries = try sourceEntries()
            let before = try snapshot(entries)
            for (relative, file) in entries {
                let target = payload.appendingPathComponent(relative)
                try privateDirectory(target.deletingLastPathComponent())
                try files.copyItem(at: file, to: target)
                try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            }
            try checkpoint("copied")
            guard !legacyRunning(), before == (try snapshot(try sourceEntries())),
                  NSDictionary(dictionary: oldPreferences).isEqual(to: try readPreferences(sourceID))
            else { try discardTransaction(); return result("legacy_changed") }
            if files.fileExists(atPath: payload.appendingPathComponent("database.sqlite").path) {
                let schema = try compactDatabase()
                guard schema > 0 && schema <= 4 else {
                    try discardTransaction()
                    return result("incompatible_database")
                }
            }
            var imported = oldPreferences.filter { $0.key.hasPrefix("flutter.") }
            imported.removeValue(forKey: "flutter.system_dns_record")
            try writePlist(imported, to: journal)
            let record: [String: Any] = [
                "version": 2, "source": sourceID, "destination": destinationID,
                "transaction": UUID().uuidString, "state": "pending", "imported": true,
            ]
            try writePlist(record, to: payload.appendingPathComponent(Self.markerName))
            try checkpoint("staged")
            guard NSDictionary(dictionary: existing).isEqual(to: try readPreferences(destinationID)) else {
                try discardTransaction()
                return result("destination_changed")
            }
            if files.fileExists(atPath: destination.path) {
                guard (try files.contentsOfDirectory(atPath: destination.path)).isEmpty else {
                    try discardTransaction()
                    return result("destination_changed")
                }
                try files.removeItem(at: destination)
            }
            try files.moveItem(at: payload, to: destination)
            return try completePending(record, existing: existing)
        } catch {
            try? rollbackPending()
            let marker = destination.appendingPathComponent(Self.markerName)
            let pending = (try? readPlist(marker))?["state"] as? String == "pending"
            if !pending { try? discardTransaction() }
            return result("migration_failed")
        }
    }

    private func result(_ status: String, imported: Bool = false) -> FengWoIdentityPreparation {
        FengWoIdentityPreparation(legacyImported: imported, status: status)
    }

    private func completePending(_ record: [String: Any], existing: [String: Any]) throws -> FengWoIdentityPreparation {
        try requireDirectory(transaction)
        let imported = try readPlist(journal)
        guard validLegacyPreferences(imported),
              !existing.keys.contains(where: { $0.hasPrefix("flutter.") }) || NSDictionary(dictionary: existing).isEqual(to: imported)
        else { return result("destination_present") }
        try checkpoint("installed")
        try writePreferences(destinationID, imported)
        try checkpoint("preferences_written")
        var complete = record
        complete["state"] = "complete"
        try writePlist(complete, to: destination.appendingPathComponent(Self.markerName))
        try? discardTransaction()
        return result("imported", imported: true)
    }

    private func rollbackPending() throws {
        let marker = destination.appendingPathComponent(Self.markerName)
        guard files.fileExists(atPath: marker.path), files.fileExists(atPath: journal.path) else { return }
        let record = try readPlist(marker)
        guard markerMatches(record), record["state"] as? String == "pending" else { return }
        let imported = try readPlist(journal)
        let current = try readPreferences(destinationID)
        if NSDictionary(dictionary: current).isEqual(to: imported) {
            try writePreferences(destinationID, [:])
        } else if current.keys.contains(where: { $0.hasPrefix("flutter.") }) {
            return
        }
        try requireDirectory(destination)
        guard !files.fileExists(atPath: payload.path) else { return }
        try files.moveItem(at: destination, to: payload)
    }

    private func markerMatches(_ record: [String: Any]) -> Bool {
        record["version"] as? Int == 2 && record["source"] as? String == sourceID &&
            record["destination"] as? String == destinationID &&
            (record["transaction"] as? String).flatMap(UUID.init(uuidString:)) != nil
    }

    private func validLegacyPreferences(_ values: [String: Any]) -> Bool {
        guard values["flutter.xboard.remember_me"] is Bool || values["flutter.xboard.credentials_enabled"] is Bool,
              let config = values["flutter.config"] as? String,
              let data = config.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !parsed.isEmpty, parsed["proxiesStyle"] == nil,
              parsed["appSettingProps"] is [String: Any], parsed["themeProps"] is [String: Any],
              PropertyListSerialization.propertyList(values, isValidFor: .binary)
        else { return false }
        if let version = values["flutter.version"] {
            guard let version = version as? Int, version >= 0 && version <= 1 else { return false }
        }
        for key in ["flutter.clash_config"] {
            if let text = values[key] {
                guard let text = text as? String, let data = text.data(using: .utf8),
                      (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return false }
            }
        }
        return true
    }

    private func sourceEntries() throws -> [(String, URL)] {
        guard files.fileExists(atPath: source.path) else { return [] }
        var result: [(String, URL)] = []
        for name in ["database.sqlite", "database.sqlite-wal"] {
            let file = source.appendingPathComponent(name)
            if files.fileExists(atPath: file.path) {
                try requireFile(file)
                result.append((name, file))
            }
        }
        for (directory, suffix) in [("profiles", ".yaml"), ("scripts", ".js"), (".secure-storage", ".secret")] {
            let base = source.appendingPathComponent(directory, isDirectory: true)
            guard files.fileExists(atPath: base.path) else { continue }
            try requireDirectory(base)
            for file in try files.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) {
                let name = file.lastPathComponent
                let isSecret = directory == ".secure-storage"
                let validSecret = name == ".master-key" || name.range(of: "^[a-f0-9]{64}\\.secret$", options: .regularExpression) != nil
                guard isSecret ? validSecret : name.hasSuffix(suffix) else { continue }
                try requireFile(file)
                result.append(("\(directory)/\(name)", file))
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    private func snapshot(_ entries: [(String, URL)]) throws -> [String: String] {
        var result: [String: String] = [:]
        for (name, file) in entries {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var digest = SHA256()
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { digest.update(data: data) }
            result[name] = digest.finalize().map { String(format: "%02x", $0) }.joined()
        }
        return result
    }

    private func compactDatabase() throws -> Int {
        let input = payload.appendingPathComponent("database.sqlite")
        let output = transaction.appendingPathComponent("database.compact.sqlite")
        var reader: OpaquePointer?
        var writer: OpaquePointer?
        defer { if let reader = reader { sqlite3_close(reader) }; if let writer = writer { sqlite3_close(writer) } }
        guard sqlite3_open_v2(input.path, &reader, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              sqlite3_open_v2(output.path, &writer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK
        else { throw CocoaError(.fileReadCorruptFile) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(reader, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw CocoaError(.fileReadCorruptFile) }
        let schema = Int(sqlite3_column_int(statement, 0))
        guard schema > 0 && schema <= 4 else { return schema }
        guard let backup = sqlite3_backup_init(writer, "main", reader, "main") else { throw CocoaError(.fileReadCorruptFile) }
        let step = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard step == SQLITE_DONE && finish == SQLITE_OK,
              sqlite3_exec(writer, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK
        else { throw CocoaError(.fileReadCorruptFile) }
        sqlite3_finalize(statement)
        statement = nil
        sqlite3_close(reader)
        reader = nil
        sqlite3_close(writer)
        writer = nil
        try files.removeItem(at: input)
        for suffix in ["-wal", "-shm"] {
            let file = URL(fileURLWithPath: input.path + suffix)
            if files.fileExists(atPath: file.path) { try files.removeItem(at: file) }
        }
        try files.moveItem(at: output, to: input)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: input.path)
        return schema
    }

    private func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadInvalidFileName) }
    }

    private func requireFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadInvalidFileName) }
    }

    private func privateDirectory(_ url: URL) throws {
        try files.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try requireDirectory(url)
    }

    private func writePlist(_ values: [String: Any], to file: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try data.write(to: file, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func readPlist(_ file: URL) throws -> [String: Any] {
        try requireFile(file)
        guard let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any]
        else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }

    private func discardTransaction() throws {
        if files.fileExists(atPath: transaction.path) { try requireDirectory(transaction); try files.removeItem(at: transaction) }
    }
}
