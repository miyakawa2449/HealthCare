import Foundation
import WeightCore

/// 保存する計画の記録。ロードマップ、いまのフェーズ、元の計画(見直しを採用したとき)、早期到達を断った日。
struct PlanRecord: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = PlanRecord.currentSchemaVersion
    var roadmap: Roadmap
    var phase: PlanPhase
    /// 計画見直しを採用したときの「元の計画に戻す」用。採用前は nil。
    var originalRoadmap: Roadmap?
    /// 早期到達の提案を断った日。その日から earlyArrivalRetryDays 後に再提案する。
    var declinedEarlyArrivalOn: CalendarDay?

    init(roadmap: Roadmap, phase: PlanPhase, originalRoadmap: Roadmap?, declinedEarlyArrivalOn: CalendarDay?) {
        self.roadmap = roadmap
        self.phase = phase
        self.originalRoadmap = originalRoadmap
        self.declinedEarlyArrivalOn = declinedEarlyArrivalOn
    }
}

enum PlanStoreError: Error, Equatable {
    /// 保存した JSON のスキーマのバージョンが、このビルドが扱える版と違う(移行が要る)。
    case unsupportedSchemaVersion(Int)
}

/// 計画の記録を JSON で保存する。保存先は App Group のコンテナ(ウィジェットが後で読む)。
final class PlanStore: Sendable {
    static let appGroupIdentifier = "group.com.miyakawa.weightapp"

    let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("plan.json")
    }

    /// App Group のコンテナ。取れなければ nil(退避先は作らない。別の場所に保存すると後で見えなくなるため)。
    static func defaultDirectory() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// 未保存なら nil。壊れていればエラー、スキーマのバージョンが違えば `PlanStoreError` を投げる。
    func load() throws -> PlanRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let record = try JSONDecoder().decode(PlanRecord.self, from: Data(contentsOf: fileURL))
        guard record.schemaVersion == PlanRecord.currentSchemaVersion else {
            throw PlanStoreError.unsupportedSchemaVersion(record.schemaVersion)
        }
        return record
    }

    func save(_ record: PlanRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: fileURL, options: .atomic)
    }
}
