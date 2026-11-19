import Foundation

public protocol ProgressStoring: AnyObject, Sendable {
    func load() throws -> PlayerProgress?
    func save(_ progress: PlayerProgress) throws
    func reset() throws
}

public enum ProgressCoding {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func encode(_ progress: PlayerProgress) throws -> Data {
        try encoder().encode(progress)
    }

    /// Decodes and sanity-checks a payload (local file or CloudKit record).
    /// Rejects future schema versions and out-of-range values rather than
    /// trusting them.
    public static func decode(_ data: Data) throws -> PlayerProgress {
        guard data.count <= 2_000_000 else { throw ProgressStoreError.payloadTooLarge }
        let progress = try decoder().decode(PlayerProgress.self, from: data)
        guard progress.version <= PlayerProgress.currentVersion else { throw ProgressStoreError.unsupportedVersion }
        for record in Array(progress.levels.values) + Array(progress.daily.values) {
            guard (0...3).contains(record.bestStars), record.bestScore >= 0, record.completions >= 0,
                  record.bestTime.map({ $0.isFinite && $0 >= 0 }) ?? true else {
                throw ProgressStoreError.invalidData
            }
        }
        return progress
    }
}

public enum ProgressStoreError: Error, Equatable {
    case payloadTooLarge
    case unsupportedVersion
    case invalidData
}

/// Codable JSON file in Application Support. Writes are atomic and the
/// previous good copy is kept as a backup. A corrupt file is quarantined
/// instead of crashing the game.
public final class FileProgressStore: ProgressStoring, @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("CitySprint", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("progress.json")
    }

    private var backupURL: URL { url.deletingPathExtension().appendingPathExtension("backup.json") }

    public func load() throws -> PlayerProgress? {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            do {
                return try ProgressCoding.decode(Data(contentsOf: url))
            } catch {
                quarantine(url)
            }
        }
        if fm.fileExists(atPath: backupURL.path) {
            do {
                return try ProgressCoding.decode(Data(contentsOf: backupURL))
            } catch {
                quarantine(backupURL)
            }
        }
        return nil
    }

    public func save(_ progress: PlayerProgress) throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try ProgressCoding.encode(progress)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: url, to: backupURL)
        }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    public func reset() throws {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        for u in [url, backupURL] where fm.fileExists(atPath: u.path) {
            try fm.removeItem(at: u)
        }
    }

    private func quarantine(_ file: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = file.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: file, to: dest)
    }
}

/// Used by tests and UI tests.
public final class InMemoryProgressStore: ProgressStoring, @unchecked Sendable {
    private var stored: PlayerProgress?
    private let lock = NSLock()

    public init(_ initial: PlayerProgress? = nil) {
        stored = initial
    }

    public func load() throws -> PlayerProgress? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    public func save(_ progress: PlayerProgress) throws {
        lock.lock()
        defer { lock.unlock() }
        stored = progress
    }

    public func reset() throws {
        lock.lock()
        defer { lock.unlock() }
        stored = nil
    }
}
