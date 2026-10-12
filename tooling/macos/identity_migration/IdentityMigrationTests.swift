import Cocoa
import SQLite3

private struct TestFailure: Error { let message: String }

private final class Fixture {
    let files = FileManager.default
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("fengwo-identity-\(UUID().uuidString)", isDirectory: true)
    let sourceID = "com.follow.clash"
    let targetID = "com.fengwo.accelerator"
    var domains: [String: [String: Any]] = [:]
    var running = false
    var failWrite = false
    var checkpoint: (String) throws -> Void = { _ in }
    var source: URL { root.appendingPathComponent(sourceID) }
    var target: URL { root.appendingPathComponent(targetID) }

    init() throws { try files.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? files.removeItem(at: root) }

    func migration() -> FengWoIdentityMigration {
        FengWoIdentityMigration(
            root: root, sourceID: sourceID, destinationID: targetID,
            readPreferences: { self.domains[$0] ?? [:] },
            writePreferences: { domain, values in
                if self.failWrite { throw TestFailure(message: "injected") }
                self.domains[domain] = values
            },
            legacyRunning: { self.running }, checkpoint: { try self.checkpoint($0) }
        )
    }

    func legacy(schema: Int = 4, wal: Bool = false) throws {
        domains[sourceID] = [
            "flutter.xboard.remember_me": true,
            "flutter.config": "{\"appSettingProps\":{\"autoLaunch\":false},\"themeProps\":{}}",
            "flutter.version": 1,
        ]
        try files.createDirectory(at: source, withIntermediateDirectories: true)
        var database: OpaquePointer?
        guard sqlite3_open(source.appendingPathComponent("database.sqlite").path, &database) == SQLITE_OK else {
            throw TestFailure(message: "fixture database")
        }
        defer { sqlite3_close(database) }
        if wal { sqlite3_exec(database, "PRAGMA journal_mode=WAL", nil, nil, nil) }
        guard sqlite3_exec(database, "CREATE TABLE fixture(value TEXT); INSERT INTO fixture VALUES('preserved'); PRAGMA user_version=\(schema)", nil, nil, nil) == SQLITE_OK else {
            throw TestFailure(message: "fixture data")
        }
        try write("profiles/fixture.yaml", "proxies: []")
        try write("scripts/fixture.js", "function main(config) { return config; }")
    }

    func write(_ relative: String, _ value: String) throws {
        let file = source.appendingPathComponent(relative)
        try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: file)
    }
}

@main
private enum IdentityMigrationTests {
    static var passed = 0

    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw TestFailure(message: message) }
    }

    static func test(_ name: String, _ body: (Fixture) throws -> Void) throws {
        let fixture = try Fixture()
        try body(fixture)
        passed += 1
        print("PASS \(name)")
    }

    static func main() throws {
        try test("fresh install never imports original preferences") { f in
            f.domains[f.sourceID] = ["flutter.config": "{\"themeProps\":{}}"]
            let result = try f.migration().prepare()
            try expect(!result.legacyImported && result.status == "no_compatible_legacy", "fresh result")
            try expect(f.domains[f.targetID] == nil, "original preferences copied")
        }
        try test("compatible Honey data copied once with original preserved") { f in
            try f.legacy()
            let original = try Data(contentsOf: f.source.appendingPathComponent("database.sqlite"))
            let result = try f.migration().prepare()
            try expect(result.legacyImported && result.status == "imported", "import result")
            try expect(try Data(contentsOf: f.source.appendingPathComponent("database.sqlite")) == original, "source database changed")
            try expect(f.files.fileExists(atPath: f.target.appendingPathComponent("profiles/fixture.yaml").path), "profile missing")
            try expect(f.files.fileExists(atPath: f.target.appendingPathComponent("scripts/fixture.js").path), "script missing")
            f.domains[f.targetID]?["flutter.xboard.remember_me"] = false
            try expect(try f.migration().prepare().status == "already_imported", "idempotence")
            try expect(f.domains[f.targetID]?["flutter.xboard.remember_me"] as? Bool == false, "preferences overwritten")
        }
        try test("WAL commits preserved from private snapshot without touching source") { f in
            try f.legacy()
            var sourceDatabase: OpaquePointer?
            guard sqlite3_open(f.source.appendingPathComponent("database.sqlite").path, &sourceDatabase) == SQLITE_OK else {
                throw TestFailure(message: "WAL fixture")
            }
            defer { sqlite3_close(sourceDatabase) }
            guard sqlite3_exec(sourceDatabase, "PRAGMA journal_mode=WAL; INSERT INTO fixture VALUES('latest')", nil, nil, nil) == SQLITE_OK else {
                throw TestFailure(message: "WAL fixture write")
            }
            let sourceFile = f.source.appendingPathComponent("database.sqlite")
            let walFile = f.source.appendingPathComponent("database.sqlite-wal")
            let databaseBefore = try Data(contentsOf: sourceFile)
            let walBefore = try Data(contentsOf: walFile)
            try expect(try f.migration().prepare().legacyImported, "WAL not imported")
            try expect(try Data(contentsOf: sourceFile) == databaseBefore, "source database modified")
            try expect(try Data(contentsOf: walFile) == walBefore, "source WAL modified")
            var targetDatabase: OpaquePointer?
            guard sqlite3_open_v2(f.target.appendingPathComponent("database.sqlite").path, &targetDatabase, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                throw TestFailure(message: "WAL result")
            }
            defer { sqlite3_close(targetDatabase) }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(targetDatabase, "SELECT count(*) FROM fixture", -1, &statement, nil) == SQLITE_OK else {
                throw TestFailure(message: "WAL query: \(String(cString: sqlite3_errmsg(targetDatabase)))")
            }
            defer { sqlite3_finalize(statement) }
            try expect(sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement, 0) == 2, "latest WAL commit lost")
            try expect(!f.files.fileExists(atPath: f.target.appendingPathComponent("database.sqlite-wal").path), "WAL copied as active file")
        }
        try test("schema10 despite Honey preferences never copied") { f in
            try f.legacy(schema: 10)
            let result = try f.migration().prepare()
            try expect(result.status == "incompatible_database" && !result.legacyImported, "schema10 accepted")
            try expect(!f.files.fileExists(atPath: f.target.path) && f.domains[f.targetID] == nil, "schema10 partial import")
            try expect(f.files.fileExists(atPath: f.source.appendingPathComponent("database.sqlite").path), "source deleted")
        }
        try test("invalid config and empty Xboard keys do not prove ownership") { f in
            f.domains[f.sourceID] = ["flutter.xboard.email": "", "flutter.config": "{}"]
            try expect(try f.migration().prepare().status == "no_compatible_legacy", "empty proof accepted")
            f.domains[f.sourceID] = ["flutter.xboard.remember_me": true, "flutter.config": "bad-json"]
            try expect(try f.migration().prepare().status == "no_compatible_legacy", "bad config accepted")
        }
        try test("existing new data preserved") { f in
            try f.legacy()
            try f.files.createDirectory(at: f.target, withIntermediateDirectories: true)
            let marker = f.target.appendingPathComponent("keep")
            try Data("current".utf8).write(to: marker)
            try expect(try f.migration().prepare().status == "destination_present", "existing data imported")
            try expect(try String(contentsOf: marker, encoding: .utf8) == "current", "new data overwritten")
        }
        try test("existing new preference domain preserved") { f in
            try f.legacy()
            f.domains[f.targetID] = ["NSWindow Frame": "current"]
            try expect(try f.migration().prepare().status == "destination_present", "existing preferences imported")
            try expect(f.domains[f.targetID]?["NSWindow Frame"] as? String == "current", "new preferences overwritten")
        }
        try test("running original is not stopped and migration does not block startup") { f in
            try f.legacy()
            f.running = true
            try expect(try f.migration().prepare().status == "legacy_running", "running original accepted")
            try expect(f.running && !f.files.fileExists(atPath: f.target.path), "running original affected")
        }
        try test("volatile locks logs providers and temporary data excluded") { f in
            try f.legacy()
            try f.write("FlClash.lock", "old-lock")
            try f.write("logs/old.log", "unreadable")
            try f.files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.source.appendingPathComponent("logs/old.log").path)
            try f.write("profiles/providers/temporary", "cache")
            try f.write("config.yaml", "runtime")
            try f.write("unknown.tmp", "temporary")
            try expect(try f.migration().prepare().legacyImported, "volatile file blocked startup")
            for relative in ["FlClash.lock", "logs", "profiles/providers", "config.yaml", "unknown.tmp"] {
                try expect(!f.files.fileExists(atPath: f.target.appendingPathComponent(relative).path), "volatile data copied")
            }
        }
        try test("profile symlink cannot escape approved source") { f in
            try f.legacy()
            let outside = f.root.appendingPathComponent("foreign")
            try Data("private".utf8).write(to: outside)
            try f.files.createSymbolicLink(at: f.source.appendingPathComponent("profiles/escape.yaml"), withDestinationURL: outside)
            try expect(try f.migration().prepare().status == "migration_failed", "symlink accepted")
            try expect(try String(contentsOf: outside, encoding: .utf8) == "private", "foreign file affected")
        }
        try test("source changes rejected without partial target") { f in
            try f.legacy()
            f.checkpoint = { if $0 == "copied" { try f.write("profiles/fixture.yaml", "changed") } }
            try expect(try f.migration().prepare().status == "legacy_changed", "changed source imported")
            try expect(!f.files.fileExists(atPath: f.target.path) && f.domains[f.targetID] == nil, "partial target committed")
        }
        try test("new destination preferences appearing during staging preserved") { f in
            try f.legacy()
            f.checkpoint = {
                if $0 == "staged" { f.domains[f.targetID] = ["flutter.xboard.email": "new-account"] }
            }
            try expect(try f.migration().prepare().status == "destination_changed", "new preference race accepted")
            try expect(f.domains[f.targetID]?["flutter.xboard.email"] as? String == "new-account", "new preference overwritten")
            try expect(!f.files.fileExists(atPath: f.target.path), "old database committed")
        }
        try test("copy failure safe fresh startup and retry") { f in
            try f.legacy()
            f.checkpoint = { if $0 == "copied" { throw TestFailure(message: "injected") } }
            try expect(try f.migration().prepare().status == "migration_failed", "copy failure propagated")
            try expect(!f.files.fileExists(atPath: f.target.path), "partial copied target")
            f.checkpoint = { _ in }
            try expect(try f.migration().prepare().legacyImported, "retry did not import")
        }
        try test("preference failure rolls back newly committed data") { f in
            try f.legacy()
            f.failWrite = true
            try expect(try f.migration().prepare().status == "migration_failed", "preference error propagated")
            try expect(!f.files.fileExists(atPath: f.target.path), "half migration left active")
            f.failWrite = false
            try expect(try f.migration().prepare().legacyImported, "retry blocked")
        }
        try test("completed preference write failure rolls back both stores") { f in
            try f.legacy()
            f.checkpoint = { if $0 == "preferences_written" { throw TestFailure(message: "injected") } }
            try expect(try f.migration().prepare().status == "migration_failed", "completion error propagated")
            try expect(!f.files.fileExists(atPath: f.target.path) && f.domains[f.targetID]?.isEmpty == true, "half preference import")
            f.checkpoint = { _ in }
            try expect(try f.migration().prepare().legacyImported, "completion retry blocked")
        }
        try test("failed rollback retains journal for next atomic completion") { f in
            try f.legacy()
            f.checkpoint = {
                if $0 == "preferences_written" {
                    f.failWrite = true
                    throw TestFailure(message: "injected")
                }
            }
            try expect(try f.migration().prepare().status == "migration_failed", "failure not reported")
            let journal = f.root.appendingPathComponent(".\(f.targetID).identity-v2/preferences.plist")
            try expect(f.files.fileExists(atPath: journal.path), "retry journal deleted")
            f.failWrite = false
            f.checkpoint = { _ in }
            try expect(try f.migration().prepare().legacyImported, "pending state not resumed")
        }
        try test("pending atomic directory commit resumes") { f in
            try f.legacy()
            let pending = f.root.appendingPathComponent(".\(f.targetID).identity-v2")
            try f.files.createDirectory(at: pending, withIntermediateDirectories: true)
            try f.files.createDirectory(at: f.target, withIntermediateDirectories: true)
            let record: [String: Any] = ["version": 2, "source": f.sourceID, "destination": f.targetID, "transaction": UUID().uuidString, "state": "pending", "imported": true]
            try PropertyListSerialization.data(fromPropertyList: record, format: .binary, options: 0).write(to: f.target.appendingPathComponent(FengWoIdentityMigration.markerName))
            try PropertyListSerialization.data(fromPropertyList: f.domains[f.sourceID]!, format: .binary, options: 0).write(to: pending.appendingPathComponent("preferences.plist"))
            try expect(try f.migration().prepare().legacyImported, "pending migration not resumed")
            try expect(!f.files.fileExists(atPath: pending.path), "transaction remained")
        }
        print("\(passed) identity migration tests passed")
    }
}
