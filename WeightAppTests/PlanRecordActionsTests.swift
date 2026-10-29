import Foundation
import Testing
import WeightCore
@testable import WeightApp

struct PlanRecordActionsTests {
    let s = PlanSettings.default
    let start = CalendarDay(year: 2026, month: 10, day: 18)
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: s) }
    var losing: PlanRecord { PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil) }
    let arrivalDay = CalendarDay(year: 2027, month: 3, day: 23)
    var maintaining: PlanRecord {
        let phase = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: arrivalDay)!
        return PlanRecord(roadmap: roadmap.rescheduled(from: phase), phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil)
    }

    @Test("85日目: 次へ進むと、その日の7日平均を起点にステージ2の減量中。予定日は起点から。出来事 graduated")
    func advanceAfterMaximum() throws {
        var r = maintaining
        r.continuedMaintenanceOn = arrivalDay.adding(days: 85)
        let day = arrivalDay.adding(days: 100)
        try r.advanceAfterMaximum(sevenDayAverage: 112.0, on: day)
        #expect(r.phase == .losing(stage: 2, origin: StageOrigin(weight: 112.0, day: day)))
        let days = Pace.days(toReach: 100.0 / 112.0, monthlyRate: s.monthlyRate, settings: s)
        #expect(r.roadmap.stages[1].estimatedArrival == day.adding(days: days))
        #expect(r.roadmap.stages[0].estimatedArrival == arrivalDay)
        #expect(r.continuedMaintenanceOn == nil)
        #expect(r.unreadEvents.map(\.kind) == [.graduated(toStage: 2, keptWeight: 111.2, nextBoundary: 100.0)])
        #expect(r.unreadEvents.first?.day == day)
    }

    @Test("85日目の操作を減量中に呼ぶと notApplicable")
    func advanceNotApplicable() {
        var r = losing
        #expect(throws: PlanActionError.notApplicable) { try r.advanceAfterMaximum(sevenDayAverage: 120.0, on: start) }
        #expect(throws: PlanActionError.notApplicable) { try r.continueMaintenance(on: start) }
    }

    @Test("維持を続ける")
    func continueMaintenance() throws {
        var r = maintaining
        try r.continueMaintenance(on: arrivalDay.adding(days: 85))
        #expect(r.continuedMaintenanceOn == arrivalDay.adding(days: 85))
        #expect(r.phase == maintaining.phase)
    }

    @Test("早期到達を採用: 次のステージの維持期間へ。出来事 stageArrived")
    func adoptEarlyArrival() throws {
        var r = maintaining
        r.declinedEarlyArrivalOn = arrivalDay.adding(days: 5)
        let day = arrivalDay.adding(days: 20)
        try r.adoptEarlyArrival(sevenDayAverage: 99.96, on: day)
        #expect(r.phase == .maintaining(stage: 2, arrival: StageOrigin(weight: 100.0, day: day)))
        #expect(r.roadmap.stages[1].estimatedArrival == day)
        #expect(r.declinedEarlyArrivalOn == nil)
        #expect(r.unreadEvents.map(\.kind) == [.stageArrived(stage: 2, weight: 100.0)])
    }

    @Test("早期到達でステージ5の維持期間から最終へ: 維持モード、出来事 targetReached")
    func adoptEarlyArrivalToFinal() throws {
        let phase = roadmap.phaseOnArrival(stage: 5, sevenDayAverage: 72.9, on: arrivalDay)!
        var r = PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil)
        let day = arrivalDay.adding(days: 10)
        try r.adoptEarlyArrival(sevenDayAverage: 67.4, on: day)
        #expect(r.phase == .maintenanceMode(arrival: StageOrigin(weight: 67.4, day: day)))
        #expect(r.unreadEvents.map(\.kind) == [.targetReached(weight: 67.4)])
    }

    @Test("早期到達が成立していなければ notApplicable")
    func adoptEarlyArrivalNotApplicable() {
        var r = maintaining
        #expect(throws: PlanActionError.notApplicable) { try r.adoptEarlyArrival(sevenDayAverage: 105.0, on: arrivalDay.adding(days: 20)) }
        var l = losing
        #expect(throws: PlanActionError.notApplicable) { try l.declineEarlyArrival(on: start) }
    }

    @Test("計画見直しを採用: 元の計画を保持し、起点を取り直し、境界は不変、予定日は新しい起点から")
    func adoptPlanReview() throws {
        var r = losing
        r.declinedPlanReviewOn = start.adding(days: 40)
        let day = start.adding(days: 60)
        try r.adoptPlanReview(sevenDayAverage: 121.0, on: day)
        #expect(r.originalRoadmap == roadmap)
        #expect(r.originalPhase == roadmap.initialPhase)
        #expect(r.phase == .losing(stage: 1, origin: StageOrigin(weight: 121.0, day: day)))
        #expect(r.roadmap.stages.map(\.boundaryWeight) == roadmap.stages.map(\.boundaryWeight))
        let days = Pace.days(toReach: 111.2 / 121.0, monthlyRate: s.monthlyRate, settings: s)
        #expect(r.roadmap.stages[0].estimatedArrival == day.adding(days: days))
        #expect(r.declinedPlanReviewOn == nil)
        #expect(r.canRevertToOriginalPlan)
    }

    @Test("2回採用しても元の計画は最初の採用前のまま")
    func adoptTwice() throws {
        var r = losing
        try r.adoptPlanReview(sevenDayAverage: 121.0, on: start.adding(days: 60))
        try r.adoptPlanReview(sevenDayAverage: 119.0, on: start.adding(days: 90))
        #expect(r.originalRoadmap == roadmap)
        #expect(r.originalPhase == roadmap.initialPhase)
        #expect(r.phase.origin == StageOrigin(weight: 119.0, day: start.adding(days: 90)))
    }

    @Test("元の計画のままにする")
    func declinePlanReview() throws {
        var r = losing
        try r.declinePlanReview(on: start.adding(days: 60))
        #expect(r.declinedPlanReviewOn == start.adding(days: 60))
        var m = maintaining
        #expect(throws: PlanActionError.notApplicable) { try m.declinePlanReview(on: arrivalDay) }
        #expect(throws: PlanActionError.notApplicable) { try m.adoptPlanReview(sevenDayAverage: 110.0, on: arrivalDay) }
    }

    @Test("元の計画に戻す: 採用前に戻り、断った日が当日になる(直後に提案が出ないように)")
    func revert() throws {
        var r = losing
        try r.adoptPlanReview(sevenDayAverage: 121.0, on: start.adding(days: 60))
        let day = start.adding(days: 70)
        try r.revertToOriginalPlan(on: day)
        #expect(r.roadmap == roadmap)
        #expect(r.phase == roadmap.initialPhase)
        #expect(r.originalRoadmap == nil)
        #expect(r.originalPhase == nil)
        #expect(r.declinedPlanReviewOn == day)
        #expect(!r.canRevertToOriginalPlan)
    }

    @Test("元の計画に戻せるのは、採用時と同じステージの減量中だけ")
    func revertNotApplicable() throws {
        var r = losing
        #expect(throws: PlanActionError.notApplicable) { try r.revertToOriginalPlan(on: start) }   // 採用していない
        try r.adoptPlanReview(sevenDayAverage: 121.0, on: start.adding(days: 60))
        let arrived = PhaseProgression.Result(phase: roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.0, on: start.adding(days: 100))!,
                                              roadmap: r.roadmap, steps: [])
        r.phase = arrived.phase
        #expect(!r.canRevertToOriginalPlan)
        #expect(throws: PlanActionError.notApplicable) { try r.revertToOriginalPlan(on: start.adding(days: 100)) }
    }

    @Test("出来事を閉じると、それだけ消える")
    func dismissEvent() {
        var r = losing
        r.appendEvent(.firstMilestoneReached(weight: 117.3, nextBoundary: 111.2), on: start.adding(days: 50))
        r.appendEvent(.stageArrived(stage: 1, weight: 111.2), on: start.adding(days: 150))
        let first = r.unreadEvents[0].id
        r.dismissEvent(id: first)
        #expect(r.unreadEvents.map(\.kind) == [.stageArrived(stage: 1, weight: 111.2)])
    }

    @Test("自動遷移の反映: 到達 → 卒業の列から出来事を作る(卒業の保てた体重は到達時体重)")
    func applyProgression() {
        var r = losing
        let arrival = StageOrigin(weight: 111.2, day: arrivalDay)
        let gradDay = arrivalDay.adding(days: 27)
        let maintainingPhase = PlanPhase.maintaining(stage: 1, arrival: arrival)
        let nextPhase = PlanPhase.losing(stage: 2, origin: StageOrigin(weight: 111.0, day: gradDay))
        let result = PhaseProgression.Result(
            phase: nextPhase, roadmap: roadmap.rescheduled(from: maintainingPhase).rescheduled(from: nextPhase),
            steps: [
                .init(transition: .arrived(stage: 1, on: arrivalDay, sevenDayAverage: 111.2), phaseAfter: maintainingPhase),
                .init(transition: .graduated(fromStage: 1, on: gradDay, sevenDayAverage: 111.0), phaseAfter: nextPhase),
            ])
        r.apply(result)
        #expect(r.phase == nextPhase)
        #expect(r.roadmap == result.roadmap)
        #expect(r.unreadEvents.map(\.kind) == [.stageArrived(stage: 1, weight: 111.2), .graduated(toStage: 2, keptWeight: 111.2, nextBoundary: 100.0)])
        #expect(r.unreadEvents.map(\.day) == [arrivalDay, gradDay])
    }

    @Test("最終ステージの到達は targetReached")
    func applyFinalArrival() {
        let phase = PlanPhase.losing(stage: 6, origin: StageOrigin(weight: 72.9, day: arrivalDay))
        var r = PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil)
        let mode = PlanPhase.maintenanceMode(arrival: StageOrigin(weight: 67.4, day: arrivalDay.adding(days: 100)))
        r.apply(.init(phase: mode, roadmap: roadmap, steps: [.init(transition: .arrived(stage: 6, on: arrivalDay.adding(days: 100), sevenDayAverage: 67.4), phaseAfter: mode)]))
        #expect(r.unreadEvents.map(\.kind) == [.targetReached(weight: 67.4)])
    }

    // MARK: 保存

    func makeStore() throws -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PlanRecordActionsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    @Test("新しい項目を含めて往復で等しい")
    func roundTrip() throws {
        var r = losing
        try r.adoptPlanReview(sevenDayAverage: 121.0, on: start.adding(days: 60))
        r.declinedPlanReviewOn = start.adding(days: 61)
        r.continuedMaintenanceOn = start.adding(days: 62)
        r.appendEvent(.firstMilestoneReached(weight: 117.3, nextBoundary: 111.2), on: start.adding(days: 50))
        let store = try makeStore()
        try store.save(r)
        #expect(try store.load() == r)
    }

    /// フェーズ4の形の plan.json(実機で 2026-10-24 に作った計画と同じ項目。新しい項目はない)。03-decisions.md #10 の追加。
    static let phase4Fixture = """
    {
      "schemaVersion" : 1,
      "phase" : { "losing" : { "stage" : 1, "origin" : { "weight" : 123.1, "day" : { "year" : 2026, "month" : 10, "day" : 24 } } } },
      "roadmap" : {
        "startWeight" : 123.1,
        "startDay" : { "year" : 2026, "month" : 10, "day" : 24 },
        "targetWeight" : 67.4,
        "firstMilestoneWeight" : 116.9,
        "stages" : [
          { "number" : 1, "startWeight" : 123.1, "boundaryWeight" : 110.8, "estimatedArrival" : { "year" : 2027, "month" : 3, "day" : 30 } },
          { "number" : 2, "startWeight" : 110.8, "boundaryWeight" : 99.7, "estimatedArrival" : { "year" : 2027, "month" : 11, "day" : 1 } },
          { "number" : 3, "startWeight" : 99.7, "boundaryWeight" : 89.7, "estimatedArrival" : { "year" : 2028, "month" : 6, "day" : 5 } },
          { "number" : 4, "startWeight" : 89.7, "boundaryWeight" : 80.8, "estimatedArrival" : { "year" : 2029, "month" : 1, "day" : 7 } },
          { "number" : 5, "startWeight" : 80.8, "boundaryWeight" : 72.7, "estimatedArrival" : { "year" : 2029, "month" : 8, "day" : 11 } },
          { "number" : 6, "startWeight" : 72.7, "boundaryWeight" : 67.4, "estimatedArrival" : { "year" : 2030, "month" : 2, "day" : 1 } }
        ],
        "settings" : {
          "monthlyRate" : 0.02, "daysPerMonth" : 30, "weeklySafeLimit" : 0.005, "weeklyCautionLimit" : 0.01,
          "actualPaceWindowDays" : 28, "fastPaceMonthlyLimit" : 0.03, "stageRatio" : 0.1, "firstMilestoneRatio" : 0.05,
          "maintenanceMinDays" : 28, "maintenanceMaxDays" : 84, "maintenanceBand" : 0.02, "progressBand" : 0.005,
          "reviewDeviation" : 0.02, "reviewWindowDays" : 14, "defaultTargetBMI" : 22, "assumedMaintenanceDays" : 60,
          "initialPeriodDays" : 30, "actualPaceWindowStartFloor" : 13, "actualPaceMinimumWindowDays" : 14,
          "maintenanceNoticeDays" : 14, "earlyArrivalRetryDays" : 14
        }
      }
    }
    """

    @Test("フェーズ4の形の plan.json(新しい項目なし)を読める")
    func decodesPhase4Fixture() throws {
        let store = try makeStore()
        try Data(Self.phase4Fixture.utf8).write(to: store.fileURL)
        let r = try #require(try store.load())
        #expect(r.schemaVersion == 1)
        #expect(r.roadmap.startDay == CalendarDay(year: 2026, month: 10, day: 24))
        #expect(r.roadmap.startWeight == 123.1)
        #expect(r.phase == .losing(stage: 1, origin: StageOrigin(weight: 123.1, day: CalendarDay(year: 2026, month: 10, day: 24))))
        #expect(r.roadmap.settings == .default)
        #expect(r.events == nil)
        #expect(r.unreadEvents.isEmpty)
        #expect(r.originalPhase == nil)
        #expect(r.declinedPlanReviewOn == nil)
        #expect(r.continuedMaintenanceOn == nil)
        #expect(r.firstMilestoneReachedOn == nil)
        // 読んだ記録をそのまま保存し直しても読める
        try store.save(r)
        #expect(try store.load() == r)
    }
}
