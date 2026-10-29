import Foundation
import Testing
import WeightCore
@testable import WeightApp

/// HomeModel のカードの操作(モック経由)。
@MainActor
struct HomeModelActionsTests {
    let cal = AppCalendar.tokyo
    let s = PlanSettings.default
    var today: CalendarDay { CalendarDay(date: Date(), calendar: cal) }

    func makeStore() throws -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HomeModelActionsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    func samples(from first: CalendarDay, days: Int, _ kg: Double) -> [WeightSample] {
        (0..<days).map { i in
            let d = first.adding(days: i)
            return WeightSample(kilograms: kg, measuredAt: d.startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)
        }
    }

    /// 到達から85日たった維持期間(範囲外が続いて卒業していない)。
    func exceededModel(store: PlanStore) async throws -> HomeModel {
        let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -300), targetWeight: 67.4, settings: s)
        let arrivalDay = today.adding(days: -85)
        let phase = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: arrivalDay)!
        try store.save(PlanRecord(roadmap: roadmap.rescheduled(from: phase), phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil, firstMilestoneReachedOn: today.adding(days: -200)))
        let model = HomeModel(health: MockHealthStore(weights: samples(from: arrivalDay.adding(days: -6), days: 92, 115.0)), planStore: store)
        await model.refresh()
        return model
    }

    func cards(_ model: HomeModel) -> [HomeCard] {
        guard let s = model.summary, let plan = s.plan else { return [] }
        return HomeCards.cards(for: plan, sevenDayAverage: s.sevenDayAverage?.kilograms, on: s.day, settings: self.s)
    }

    @Test("85日目: 次へ進むと保存されたフェーズがステージ2になり、カードが出来事に変わる")
    func advance() async throws {
        let store = try makeStore()
        let model = try await exceededModel(store: store)
        #expect(cards(model) == [.maintenanceMaximum(canAdvance: true)])
        try await model.advanceAfterMaximum()
        #expect(model.summary?.plan?.stageNumber == 2)
        #expect(try store.load()?.phase.losingStage == 2)
        #expect(cards(model).count == 1)
        if case .event(let e) = cards(model)[0], case .graduated(let to, _, _) = e.kind { #expect(to == 2) } else { Issue.record("卒業の出来事ではない") }
    }

    @Test("85日目: 維持を続けるとカードが消える")
    func continueMaintenance() async throws {
        let store = try makeStore()
        let model = try await exceededModel(store: store)
        try await model.continueMaintenance()
        // 85日目のカードが消えると、隠れていた維持の一言(範囲外が14日以上)が出る
        let after = cards(model)
        #expect(after.count == 1)
        if case .maintenanceNotice(.aboveBand) = after.first {} else { Issue.record("維持の一言(上)ではない: \(after)") }
        #expect(try store.load()?.continuedMaintenanceOn == today)
    }

    @Test("計画見直しを採用し、元の計画に戻すと起点と予定日が戻る")
    func adoptAndRevert() async throws {
        let store = try makeStore()
        let startDay = today.adding(days: -60)
        let roadmap = Roadmap(startWeight: 123.5, startDay: startDay, targetWeight: 67.4, settings: s)
        try store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        // 2%以上ずれた状態(計画値より上)が続く: ずっと 123.5
        let model = HomeModel(health: MockHealthStore(weights: samples(from: startDay.adding(days: -6), days: 67, 123.5)), planStore: store)
        await model.refresh()
        guard case .planReview = cards(model).first else { Issue.record("見直しのカードが出ていない: \(cards(model))"); return }
        try await model.adoptPlanReview()
        let adopted = try #require(try store.load())
        #expect(adopted.phase.origin == StageOrigin(weight: 123.5, day: today))
        #expect(adopted.canRevertToOriginalPlan)
        #expect(cards(model).isEmpty)   // 起点を取り直したので、ずれは消える
        try await model.revertToOriginalPlan()
        let reverted = try #require(try store.load())
        #expect(reverted.roadmap == roadmap)
        #expect(reverted.phase == roadmap.initialPhase)
        #expect(reverted.declinedPlanReviewOn == today)
        #expect(cards(model).isEmpty)   // 戻した直後は提案しない
    }

    @Test("出来事を閉じると消える")
    func dismiss() async throws {
        let store = try makeStore()
        let model = try await exceededModel(store: store)
        try await model.advanceAfterMaximum()
        guard case .event(let e) = cards(model).first else { Issue.record("出来事がない"); return }
        try await model.dismissEvent(e.id)
        #expect(cards(model).isEmpty)
        #expect(try store.load()?.unreadEvents.isEmpty == true)
    }

    @Test("条件外の操作は notApplicable を投げ、保存は変わらない")
    func notApplicable() async throws {
        let store = try makeStore()
        let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -10), targetWeight: 67.4, settings: s)
        try store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        let model = HomeModel(health: MockHealthStore(weights: samples(from: today.adding(days: -16), days: 17, 123.0)), planStore: store)
        await model.refresh()
        let before = try store.load()
        await #expect(throws: PlanActionError.notApplicable) { try await model.advanceAfterMaximum() }
        await #expect(throws: PlanActionError.notApplicable) { try await model.adoptEarlyArrival() }
        await #expect(throws: PlanActionError.notApplicable) { try await model.adoptPlanReview() }
        await #expect(throws: PlanActionError.notApplicable) { try await model.revertToOriginalPlan() }
        #expect(try store.load() == before)
    }
}
