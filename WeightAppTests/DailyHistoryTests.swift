import Foundation
import Testing
import WeightCore
@testable import WeightApp

/// DailySummary.history(グラフと記録カレンダーの元)のテスト。
struct DailyHistoryTests {
    let cal = AppCalendar.tokyo
    let start = CalendarDay(year: 2026, month: 10, day: 18)
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: .default) }

    func makeStore() throws -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DailyHistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    func samples(from first: CalendarDay, days: Int, _ kg: Double, skipping: Set<Int> = []) -> [WeightSample] {
        (0..<days).compactMap { i in
            if skipping.contains(i) { return nil }
            let d = first.adding(days: i)
            return WeightSample(kilograms: kg, measuredAt: d.startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)
        }
    }

    @Test("計画なし: 28件、古い順、最後が当日。計画値はすべて nil")
    func withoutPlan() async throws {
        let health = MockHealthStore(weights: samples(from: start.adding(days: -29), days: 30, 123.5))
        let builder = DailySummaryBuilder(health: health, planStore: try makeStore(), calendar: cal, settings: .default)
        let s = try await builder.build(on: start)
        #expect(s.history.count == HomeSettings.historyDays)
        #expect(s.history.first?.day == start.adding(days: -27))
        #expect(s.history.last?.day == start)
        #expect(s.history.allSatisfy { $0.guideline == nil })
        #expect(s.history.allSatisfy { $0.weight != nil })
        #expect(s.history.allSatisfy { $0.sevenDayAverage == 123.5 })
    }

    @Test("計画あり: 計画値は Guideline、7日平均は SevenDayAverage と一致する")
    func withPlan() async throws {
        let store = try makeStore()
        try store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        let today = start.adding(days: 43)   // 11/30
        let weights = (-6...43).map { i -> WeightSample in
            let d = start.adding(days: i)
            return WeightSample(kilograms: 123.5 - Double(i) * 0.05, measuredAt: d.startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)
        }
        let health = MockHealthStore(weights: weights)
        let builder = DailySummaryBuilder(health: health, planStore: store, calendar: cal, settings: .default)
        let s = try await builder.build(on: today)
        #expect(s.history.count == 28)
        let daily = DailyWeightResolver.resolve(weights, calendar: cal)
        for point in s.history {
            #expect(point.guideline == Guideline.expectedWeight(phase: roadmap.initialPhase!, on: point.day, settings: .default))
            #expect(point.sevenDayAverage == SevenDayAverage(endingOn: point.day, in: daily)?.kilograms)
        }
    }

    @Test("当日が開始日なら、取得範囲(開始日の6日前)より前は作らない")
    func startDay() async throws {
        let store = try makeStore()
        try store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        let health = MockHealthStore(weights: samples(from: start.adding(days: -6), days: 7, 123.5))
        let builder = DailySummaryBuilder(health: health, planStore: store, calendar: cal, settings: .default)
        let s = try await builder.build(on: start)
        #expect(s.history.map(\.day) == (-6...0).map { start.adding(days: $0) })
        // 起点より前の日は計画値なし、起点の日は開始体重
        #expect(s.history.dropLast().allSatisfy { $0.guideline == nil })
        #expect(s.history.last?.guideline == 123.5)
    }

    @Test("維持期間: 到達日より前の計画値は nil、以後は到達時体重で一定")
    func maintaining() async throws {
        let store = try makeStore()
        let arrivalDay = CalendarDay(year: 2027, month: 3, day: 23)
        let phase = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: arrivalDay)!
        try store.save(PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        let today = arrivalDay.adding(days: 18)
        let health = MockHealthStore(weights: samples(from: arrivalDay.adding(days: -30), days: 49, 111.5))
        let builder = DailySummaryBuilder(health: health, planStore: store, calendar: cal, settings: .default)
        let s = try await builder.build(on: today)
        for point in s.history {
            #expect(point.guideline == (point.day >= arrivalDay ? 111.2 : nil))
        }
    }

    @Test("ステージ1で計画見直しを採用したら、新しい起点より前の計画値は nil")
    func rebased() async throws {
        let store = try makeStore()
        let origin = CalendarDay(year: 2026, month: 12, day: 1)
        let phase = roadmap.initialPhase!.rebased(sevenDayAverage: 120.0, on: origin)!
        try store.save(PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: roadmap, declinedEarlyArrivalOn: nil))
        let today = origin.adding(days: 9)
        let health = MockHealthStore(weights: samples(from: start.adding(days: -6), days: 60, 120.0))
        let builder = DailySummaryBuilder(health: health, planStore: store, calendar: cal, settings: .default)
        let s = try await builder.build(on: today)
        #expect(s.history.filter { $0.day < origin }.allSatisfy { $0.guideline == nil })
        #expect(s.history.first { $0.day == origin }?.guideline == 120.0)
    }

    @Test("記録のない日は weight が nil。7日平均は窓に記録があれば出る")
    func gaps() async throws {
        let health = MockHealthStore(weights: samples(from: start.adding(days: -29), days: 30, 123.5, skipping: [28]))  // 前日だけ欠け
        let builder = DailySummaryBuilder(health: health, planStore: try makeStore(), calendar: cal, settings: .default)
        let s = try await builder.build(on: start)
        let yesterday = try #require(s.history.first { $0.day == start.adding(days: -1) })
        #expect(yesterday.weight == nil)
        #expect(yesterday.sevenDayAverage == 123.5)
    }

    @Test("PlanStatus に roadmap と最初の区切りの到達日が入る")
    func planStatusCarriesRoadmap() async throws {
        let store = try makeStore()
        let reached = start.adding(days: 50)
        try store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil, firstMilestoneReachedOn: reached))
        let health = MockHealthStore(weights: samples(from: start, days: 60, 117.0))
        let builder = DailySummaryBuilder(health: health, planStore: store, calendar: cal, settings: .default)
        let s = try await builder.build(on: start.adding(days: 59))
        #expect(s.plan?.roadmap == roadmap)
        #expect(s.plan?.firstMilestoneReachedOn == reached)
    }
}
