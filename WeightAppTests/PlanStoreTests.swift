import Foundation
import Testing
import WeightCore
@testable import WeightApp

struct PlanStoreTests {
    func makeStore() throws -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PlanStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    var record: PlanRecord {
        let roadmap = Roadmap(startWeight: 123.5, startDay: CalendarDay(year: 2026, month: 10, day: 18), targetWeight: 67.4, settings: .default)
        return PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil)
    }

    @Test("保存して読み戻すと等しい")
    func roundTrip() throws {
        let store = try makeStore()
        var r = record
        r.originalRoadmap = r.roadmap
        r.declinedEarlyArrivalOn = CalendarDay(year: 2027, month: 4, day: 10)
        r.phase = r.roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: CalendarDay(year: 2027, month: 3, day: 23))!
        try store.save(r)
        #expect(try store.load() == r)
    }

    @Test("未保存なら nil")
    func empty() throws {
        #expect(try makeStore().load() == nil)
    }

    @Test("上書きすると後の値")
    func overwrite() throws {
        let store = try makeStore()
        try store.save(record)
        var r = record
        r.phase = r.phase.rebased(sevenDayAverage: 118.0, on: CalendarDay(year: 2026, month: 11, day: 30))!
        try store.save(r)
        #expect(try store.load()?.phase == r.phase)
    }

    @Test("壊れたファイルはエラーを投げる(黙って nil にしない)")
    func corrupted() throws {
        let store = try makeStore()
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(throws: (any Error).self) { try store.load() }
    }

    @Test("JSON にスキーマのバージョン番号が入る")
    func schemaVersion() throws {
        let store = try makeStore()
        try store.save(record)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any]
        #expect(json?["schemaVersion"] as? Int == PlanRecord.currentSchemaVersion)
        #expect(PlanRecord.currentSchemaVersion == 1)
    }

    @Test("スキーマのバージョンが違えば専用のエラーを投げる", arguments: [0, 2, 999])
    func rejectsOtherSchemaVersions(version: Int) throws {
        let store = try makeStore()
        try store.save(record)
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as! [String: Any]
        json["schemaVersion"] = version
        try JSONSerialization.data(withJSONObject: json).write(to: store.fileURL)
        #expect(throws: PlanStoreError.unsupportedSchemaVersion(version)) { try store.load() }
    }

    @Test("項目の構成が違う将来のバージョンでも、本体を読む前にバージョンのエラーになる")
    func futureSchemaWithDifferentFields() throws {
        let store = try makeStore()
        try Data(#"{"schemaVersion": 2, "analysis": {"notes": "ai"}}"#.utf8).write(to: store.fileURL)
        #expect(throws: PlanStoreError.unsupportedSchemaVersion(2)) { try store.load() }
    }
}
