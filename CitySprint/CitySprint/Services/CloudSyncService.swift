import CloudKit
import Foundation
import CitySprintCore

/// Optional progress sync through the user's own CloudKit *private* database.
/// The developer cannot read this data. A single record holds the encoded
/// progress; conflicts are resolved with the conflict-free `ProgressMerge`.
actor CloudSyncService {
    enum SyncError: Error {
        case unavailable
    }

    private let recordType = "PlayerProgress"
    private let recordID = CKRecord.ID(recordName: "player-progress")
    private let payloadKey = "payload"
    private let enabled: Bool
    private lazy var database: CKDatabase = CKContainer(identifier: AppConfig.cloudContainerID).privateCloudDatabase

    init(enabled: Bool = AppConfig.appleServicesEnabled) {
        self.enabled = enabled
    }

    /// Merges local progress with the cloud copy and uploads the result.
    /// Returns the merged progress, or throws when iCloud is unavailable (the
    /// caller keeps playing on local data).
    func sync(local: PlayerProgress) async throws -> PlayerProgress {
        guard enabled else { throw SyncError.unavailable }
        let status = try await CKContainer(identifier: AppConfig.cloudContainerID).accountStatus()
        guard status == .available else { throw SyncError.unavailable }

        for _ in 0..<3 {
            let existing = try await fetchRecord()
            var merged = local
            if let existing, let remote = decode(existing) {
                merged = ProgressMerge.merge(local, remote)
                if merged == remote { return merged }
            }
            let record = existing ?? CKRecord(recordType: recordType, recordID: recordID)
            record[payloadKey] = try ProgressCoding.encode(merged) as CKRecordValue
            do {
                _ = try await database.save(record)
                return merged
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue // Someone else wrote first: fetch again and re-merge.
            }
        }
        throw SyncError.unavailable
    }

    func deleteCloudCopy() async throws {
        guard enabled else { return }
        do {
            _ = try await database.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }

    private func fetchRecord() async throws -> CKRecord? {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// Cloud data is treated as untrusted input and validated like a local file.
    private func decode(_ record: CKRecord) -> PlayerProgress? {
        guard let data = record[payloadKey] as? Data else { return nil }
        return try? ProgressCoding.decode(data)
    }
}
