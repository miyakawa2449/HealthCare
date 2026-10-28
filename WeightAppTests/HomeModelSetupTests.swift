import Foundation
import Testing
import WeightCore
@testable import WeightApp

/// HomeModel の初回設定と最初の区切りの保存。
@MainActor
struct HomeModelSetupTests {
    let cal = AppCalendar.tokyo
    var today: CalendarDay { CalendarDay(date: Date(), calendar: cal) }

    func makeStore() throws -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HomeModelSetupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    func samples(from first: CalendarDay, days: Int, _ kg: Double) -> [WeightSample] {
        (0..<days).map { i in
            let d = first.adding(days: i)
            return WeightSample(kilograms: kg, measuredAt: d.startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)
        }
    }

    @Test("生成直後は hasRefreshed が false。refresh 後は失敗でも true")
    func hasRefreshed() async throws {
        let health = MockHealthStore(weights: [])
        let model = HomeModel(health: health, planStore: try makeStore())
        #expect(!model.hasRefreshed)
        await health.setFailure(HomeModelTests.Failure())
        await model.refresh()
        #expect(model.hasRefreshed)
    }

    @Test("直近7日に記録があれば7日平均が初期値")
    func suggestionAverage() async throws {
        let model = HomeModel(health: MockHealthStore(weights: samples(from: today.adding(days: -2), days: 3, 123.5)), planStore: try makeStore())
        await model.refresh()
        #expect(model.startWeightSuggestion == .sevenDayAverage(123.5))
    }

    @Test("直近7日に記録がなければ最新の1件")
    func suggestionLatest() async throws {
        var weights = samples(from: today.adding(days: -20), days: 5, 124.0)
        weights.append(contentsOf: samples(from: today.adding(days: -10), days: 1, 123.0))
        let model = HomeModel(health: MockHealthStore(weights: weights), planStore: try makeStore())
        await model.refresh()
        #expect(model.startWeightSuggestion == .latest(123.0))
    }

    @Test("記録がなければ none")
    func suggestionNone() async throws {
        let model = HomeModel(health: MockHealthStore(weights: []), planStore: try makeStore())
        await model.refresh()
        #expect(model.startWeightSuggestion == .none)
    }

    @Test("startPlan で計画が保存され、ステージ1の減量中になる。起点は今日")
    func startPlan() async throws {
        let store = try makeStore()
        let model = HomeModel(health: MockHealthStore(weights: samples(from: today.adding(days: -6), days: 7, 123.5)), planStore: store)
        await model.refresh()
        try await model.startPlan(startWeight: 123.5, targetWeight: 67.4)
        let record = try #require(try store.load())
        #expect(record.phase == .losing(stage: 1, origin: StageOrigin(weight: 123.5, day: today)))
        #expect(record.roadmap.startDay == today)
        #expect(record.roadmap.targetWeight == 67.4)
        #expect(model.summary?.plan?.stageNumber == 1)
        #expect(model.summary?.plan?.progress == .settlingIn)
    }

    @Test("検証に通らなければ投げて保存しない")
    func startPlanInvalid() async throws {
        let store = try makeStore()
        let model = HomeModel(health: MockHealthStore(weights: []), planStore: store)
        await #expect(throws: HomeModel.StartPlanError.invalid(.targetNotBelowStart)) {
            try await model.startPlan(startWeight: 67.4, targetWeight: 67.4)
        }
        #expect(try store.load() == nil)
    }

    @Test("ステージ1で7日平均(丸め)が最初の区切り以下になったら到達日を保存し、戻っても消えない")
    func recordsFirstMilestone() async throws {
        let store = try makeStore()
        let startDay = today.adding(days: -60)
        let roadmap = Roadmap(startWeight: 123.5, startDay: startDay, targetWeight: 67.4, settings: .default)
        try store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        let health = MockHealthStore(weights: samples(from: today.adding(days: -6), days: 7, 117.3))
        let model = HomeModel(health: health, planStore: store)
        await model.refresh()
        #expect(try store.load()?.firstMilestoneReachedOn == today)
        #expect(model.summary?.plan?.firstMilestoneReachedOn == today)

        // 翌日以降に区切りを上回っても消えない(今日の値で再取得)
        await health.replaceWeights(samples(from: today.adding(days: -6), days: 7, 118.0))
        await model.refresh()
        #expect(try store.load()?.firstMilestoneReachedOn == today)
    }

    @Test("ステージ2では最初の区切りを保存しない")
    func noMilestoneOnStage2() async throws {
        let store = try makeStore()
        let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -300), targetWeight: 67.4, settings: .default)
        let maintaining = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: today.adding(days: -100))!
        let stage2 = roadmap.phaseOnAdvance(from: maintaining, sevenDayAverage: 111.0, on: today.adding(days: -40))!
        try store.save(PlanRecord(roadmap: roadmap, phase: stage2, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        let model = HomeModel(health: MockHealthStore(weights: samples(from: today.adding(days: -6), days: 7, 105.0)), planStore: store)
        await model.refresh()
        #expect(try store.load()?.firstMilestoneReachedOn == nil)
    }

    @Test("保存した計画が読めなければ失敗になり、初回設定には進まない")
    func unreadablePlanIsFailure() async throws {
        let store = try makeStore()
        try Data(#"{"schemaVersion": 2}"#.utf8).write(to: store.fileURL)
        let model = HomeModel(health: MockHealthStore(weights: []), planStore: store)
        await model.refresh()
        #expect(model.lastRefreshFailed)
        #expect(model.summary == nil)
        #expect(RootRoute.route(for: model) == .failed)
    }
}
