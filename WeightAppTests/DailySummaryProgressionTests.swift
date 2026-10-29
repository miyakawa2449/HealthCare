import Foundation
import Testing
import WeightCore
@testable import WeightApp

/// DailySummaryBuilder が自動遷移を反映して保存することのテスト。
struct DailySummaryProgressionTests {
    let cal = AppCalendar.tokyo
    let s = PlanSettings.default
    let start = CalendarDay(year: 2026, month: 10, day: 18)
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: s) }

    func makeStore() throws -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DailySummaryProgressionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    func samples(from first: CalendarDay, days: Int, _ kg: Double) -> [WeightSample] {
        (0..<days).map { i in
            let d = first.adding(days: i)
            return WeightSample(kilograms: kg, measuredAt: d.startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)
        }
    }

    @Test("減量中に境界以下になったら、維持期間へ遷移して保存し、出来事と予定日が更新される。2回目は変化なし")
    func arrivalIsSavedOnce() async throws {
        let store = try makeStore()
        try store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        // 10/18〜 は 118.0(最初の区切り 117.3 は未到達)、12/1〜 は 111.0
        var weights = samples(from: start.adding(days: -6), days: 50, 118.0)
        weights += samples(from: start.adding(days: 44), days: 30, 111.0)
        let daily = DailyWeightResolver.resolve(weights, calendar: cal)
        let today = start.adding(days: 70)
        let builder = DailySummaryBuilder(health: MockHealthStore(weights: weights), planStore: store, calendar: cal, settings: s)
        let summary = try await builder.build(on: today)

        let saved = try #require(try store.load())
        guard case .maintaining(let stage, let arrival) = saved.phase else { Issue.record("維持期間ではない"); return }
        #expect(stage == 1)
        let expectedArrival = (44..<70).map { start.adding(days: $0) }.first { Weight.rounded(SevenDayAverage(endingOn: $0, in: daily)!.kilograms) <= 111.2 }!
        #expect(arrival.day == expectedArrival)
        #expect(saved.roadmap.stages[0].estimatedArrival == expectedArrival)
        let milestoneDay = (44..<70).map { start.adding(days: $0) }.first { Weight.rounded(SevenDayAverage(endingOn: $0, in: daily)!.kilograms) <= 117.3 }!
        #expect(saved.firstMilestoneReachedOn == milestoneDay)
        #expect(saved.unreadEvents.map(\.kind) == [.firstMilestoneReached(weight: 117.3, nextBoundary: 111.2), .stageArrived(stage: 1, weight: arrival.weight)])
        #expect(summary.plan?.stageNumber == 1)
        if case .inProgress = summary.plan?.maintenance {} else { Issue.record("maintenance が inProgress ではない") }

        let again = try await builder.build(on: today)
        #expect(try store.load() == saved)
        #expect(again.plan?.record == saved)
    }

    @Test("記録が後から変わっても、保存した到達日は変わらない")
    func savedArrivalIsKept() async throws {
        let store = try makeStore()
        try store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        let health = MockHealthStore(weights: samples(from: start.adding(days: -6), days: 40, 111.0))
        let builder = DailySummaryBuilder(health: health, planStore: store, calendar: cal, settings: s)
        _ = try await builder.build(on: start.adding(days: 33))
        let first = try #require(try store.load())
        // 記録を書き換えて(到達が遅くなるように)再 build
        await health.replaceWeights(samples(from: start.adding(days: -6), days: 20, 120.0) + samples(from: start.adding(days: 14), days: 20, 111.0))
        _ = try await builder.build(on: start.adding(days: 33))
        #expect(try store.load()?.phase == first.phase)
    }

    @Test("維持期間で28日範囲内なら卒業して次のステージへ。出来事 graduated")
    func graduation() async throws {
        let store = try makeStore()
        let arrivalDay = start.adding(days: 150)
        let phase = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: arrivalDay)!
        try store.save(PlanRecord(roadmap: roadmap.rescheduled(from: phase), phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil, firstMilestoneReachedOn: start.adding(days: 80)))
        let builder = DailySummaryBuilder(health: MockHealthStore(weights: samples(from: arrivalDay.adding(days: -6), days: 40, 111.0)), planStore: store, calendar: cal, settings: s)
        let summary = try await builder.build(on: arrivalDay.adding(days: 33))
        let saved = try #require(try store.load())
        #expect(saved.phase == .losing(stage: 2, origin: StageOrigin(weight: 111.0, day: arrivalDay.adding(days: 27))))
        #expect(saved.unreadEvents.map(\.kind) == [.graduated(toStage: 2, keptWeight: 111.2, nextBoundary: 100.0)])
        #expect(summary.plan?.stageNumber == 2)
    }
}
