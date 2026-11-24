import Foundation
import Testing
import WeightCore
@testable import WeightApp

/// フェーズの履歴(06-reports/01-design.md 4.)。
struct PhaseHistoryTests {
    let s = PlanSettings.default
    let start = CalendarDay(year: 2026, month: 10, day: 18)
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: s) }
    var stage1: PlanPhase { roadmap.initialPhase! }
    var losing: PlanRecord { PlanRecord(roadmap: roadmap, phase: stage1, originalRoadmap: nil, declinedEarlyArrivalOn: nil) }
    let arrivalDay = CalendarDay(year: 2027, month: 3, day: 23)
    var maintainingPhase: PlanPhase { roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: arrivalDay)! }
    var maintaining: PlanRecord {
        PlanRecord(roadmap: roadmap.rescheduled(from: maintainingPhase), phase: maintainingPhase, originalRoadmap: nil, declinedEarlyArrivalOn: nil)
    }

    func makeStore() throws -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    @Test("フェーズ4・5の形の plan.json(履歴なし)は開始時のフェーズだけの履歴として読む")
    func fixtureWithoutHistory() throws {
        let store = try makeStore()
        try Data(PlanRecordActionsTests.phase4Fixture.utf8).write(to: store.fileURL)
        let r = try #require(try store.load())
        #expect(r.phaseHistory == nil)
        let origin = StageOrigin(weight: 123.1, day: CalendarDay(year: 2026, month: 10, day: 24))
        #expect(r.timeline.entries == [.init(from: origin.day, phase: .losing(stage: 1, origin: origin))])
    }

    @Test("履歴なしで今が維持期間なら、開始時と到達日からの維持期間に補完する")
    func reconstructedMaintaining() {
        #expect(maintaining.timeline.entries == [.init(from: start, phase: stage1), .init(from: arrivalDay, phase: maintainingPhase)])
    }

    @Test("履歴なしでステージ1の見直しを採用中なら、開始時 → 見直した計画(元のフェーズは開始時と同じ)")
    func reconstructedAdopted() throws {
        var r = losing
        let adopt = start.adding(days: 50)
        try r.adoptPlanReview(sevenDayAverage: 120.0, on: adopt)
        r.phaseHistory = nil   // 履歴のない古い形を再現
        #expect(r.timeline.entries == [.init(from: start, phase: stage1), .init(from: adopt, phase: r.phase)])
    }

    @Test("自動遷移で到達と卒業が連鎖したら、到達日と卒業日の2項目を足す")
    func progressionAppends() throws {
        var r = losing
        // 3/23 から記録があり 111.2、28日間保つ(到達 → 卒業)
        let weights = (0..<40).map { offset -> DailyWeight in
            let d = arrivalDay.adding(days: offset)
            return DailyWeight(day: d, kilograms: 111.2, measuredAt: d.startDate(in: AppCalendar.tokyo), source: .healthPlanet)
        }
        let result = PhaseProgression.advance(phase: r.phase, roadmap: r.roadmap, weights: weights, through: arrivalDay.adding(days: 33), settings: s)
        #expect(result.steps.count == 2)
        r.apply(result)
        let froms = r.timeline.entries.map(\.from)
        #expect(froms == [start, arrivalDay, arrivalDay.adding(days: 27)])
        #expect(r.timeline.entries.last?.phase == r.phase)
    }

    @Test("見直しの採用 → 元の計画に戻すと、採用日と戻した日の項目が残る")
    func adoptAndRevert() throws {
        var r = losing
        let adopt = start.adding(days: 50)
        try r.adoptPlanReview(sevenDayAverage: 120.0, on: adopt)
        let rebased = r.phase
        let revert = start.adding(days: 60)
        try r.revertToOriginalPlan(on: revert)
        #expect(r.timeline.entries == [
            .init(from: start, phase: stage1),
            .init(from: adopt, phase: rebased),
            .init(from: revert, phase: stage1),
        ])
        #expect(r.timeline.changes(from: start, through: revert).map(\.kind) == [.planRebased(stage: 1), .planReverted(stage: 1)])
    }

    @Test("85日目に次へ進む・早期到達の採用でも足す")
    func userActionsAppend() throws {
        var r = maintaining
        let day = arrivalDay.adding(days: 90)
        try r.advanceAfterMaximum(sevenDayAverage: 112.0, on: day)
        #expect(r.timeline.entries.last == .init(from: day, phase: r.phase))
        #expect(r.timeline.entries.count == 3)

        var e = maintaining
        let earlyDay = arrivalDay.adding(days: 20)
        try e.adoptEarlyArrival(sevenDayAverage: 99.9, on: earlyDay)
        #expect(e.timeline.entries.last == .init(from: earlyDay, phase: e.phase))
    }

    @Test("同じ日に2回変わったら、その日の項目は後のもの1つ")
    func sameDay() throws {
        var r = losing
        let d = start.adding(days: 50)
        try r.adoptPlanReview(sevenDayAverage: 120.0, on: d)
        try r.adoptPlanReview(sevenDayAverage: 119.0, on: d)
        #expect(r.timeline.entries.count == 2)
        #expect(r.timeline.entries.last == .init(from: d, phase: r.phase))
    }

    @Test("履歴を保存して読み直しても同じ")
    func roundTrip() throws {
        var r = losing
        try r.adoptPlanReview(sevenDayAverage: 120.0, on: start.adding(days: 50))
        #expect(r.phaseHistory != nil)
        let store = try makeStore()
        try store.save(r)
        #expect(try store.load() == r)
    }
}
