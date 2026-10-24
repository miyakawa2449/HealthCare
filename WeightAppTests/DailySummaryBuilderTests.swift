import Foundation
import Testing
import WeightCore
@testable import WeightApp

struct DailySummaryBuilderTests {
    let cal = AppCalendar.tokyo
    let start = CalendarDay(year: 2026, month: 10, day: 18)
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: .default) }

    func makeStore() throws -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DailySummaryBuilderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    /// start から count 日、値を一定にした HealthPlanet 由来のサンプル(08:00 JST)。
    func samples(from first: CalendarDay, days: Int, _ kg: Double) -> [WeightSample] {
        (0..<days).map { i in
            let d = first.adding(days: i)
            return WeightSample(kilograms: kg, measuredAt: d.startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)
        }
    }

    @Test("計画がなくても 7日平均と当日の体重は出す。計画の判定は nil")
    func noPlan() async throws {
        let health = MockHealthStore(weights: samples(from: start.adding(days: -6), days: 7, 123.5))
        let builder = DailySummaryBuilder(health: health, planStore: try makeStore(), calendar: cal, settings: .default)
        let s = try #require(try await builder.build(on: start))
        #expect(s.sevenDayAverage?.kilograms == 123.5)
        #expect(s.sevenDayAverage?.daysUsed == 7)
        #expect(s.todayWeight?.kilograms == 123.5)
        #expect(s.plan == nil)
    }

    @Test("計画がなければ直近30日を取得する")
    func fetchRangeWithoutPlan() async throws {
        let health = MockHealthStore(weights: [])
        let builder = DailySummaryBuilder(health: health, planStore: try makeStore(), calendar: cal, settings: .default)
        _ = try await builder.build(on: start)
        let range = try #require(await health.requestedRanges.first)
        #expect(range.from == start.adding(days: -29).startDate(in: cal))   // 当日を含む30日
        #expect(range.to == start.adding(days: 1).startDate(in: cal))
    }

    @Test("維持期間の85日目: 直近7日の体重がなくても exceededMaximum のカードの判定は出る")
    func exceededMaximumWithoutRecentWeights() async throws {
        let store = try makeStore()
        let arrivalDay = CalendarDay(year: 2027, month: 3, day: 23)
        let phase = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: arrivalDay)!
        try store.save(PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        // 到達後に範囲外(115.0)が続き、直近10日はデータなし
        let health = MockHealthStore(weights: samples(from: arrivalDay.adding(days: -6), days: 80, 115.0))
        let builder = DailySummaryBuilder(health: health, planStore: store, calendar: cal, settings: .default)
        let s = try #require(try await builder.build(on: arrivalDay.adding(days: 85)))
        #expect(s.sevenDayAverage == nil)
        let plan = try #require(s.plan)
        #expect(plan.maintenance == .exceededMaximum(consecutiveDaysInBand: 0))
        #expect(plan.earlyArrivalStage == nil)
        #expect(!plan.shouldProposeEarlyArrival)
    }

    @Test("減量中ステージ1、経過45日: 計画値・進み具合・実績ペース(窓28日)が出て、維持の判定は nil")
    func losingStage1() async throws {
        let store = try makeStore()
        try store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        let today = start.adding(days: 45)
        // 目安どおりに減らす: 各日の体重 = 目安
        let weights = (-6...45).map { i -> WeightSample in
            let d = start.adding(days: i)
            let kg = Guideline.expectedWeight(startWeight: 123.5, daysElapsed: i, settings: .default)
            return WeightSample(kilograms: kg, measuredAt: d.startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)
        }
        let health = MockHealthStore(weights: weights)
        let builder = DailySummaryBuilder(health: health, planStore: store, calendar: cal, settings: .default)
        let s = try #require(try await builder.build(on: today))
        let plan = try #require(s.plan)
        #expect(plan.stageNumber == 1)
        #expect(plan.progress == .onTrack)
        #expect(plan.actualPace?.windowDays == 28)
        #expect(plan.maintenance == nil)
        #expect(plan.maintenanceNotice == nil)
        #expect(plan.earlyArrivalStage == nil)
        #expect(!plan.shouldProposePlanReview)
        // 取得期間は開始日の6日前から今日の翌日0時まで
        let range = try #require(await health.requestedRanges.first)
        #expect(range.from == start.adding(days: -6).startDate(in: cal))
        #expect(range.to == today.adding(days: 1).startDate(in: cal))
    }

    @Test("維持期間: 進み具合は nil、維持の判定と早期到達が出る。ステージ番号はフェーズの番号")
    func maintaining() async throws {
        let store = try makeStore()
        let arrivalDay = CalendarDay(year: 2027, month: 3, day: 23)
        let phase = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: arrivalDay)!
        try store.save(PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        // 維持中に 99.0 まで減ってしまった(次の境界 100.0 以下)。stage(containing:) ならステージ3だが、表示はフェーズの番号1
        let health = MockHealthStore(weights: samples(from: arrivalDay.adding(days: -6), days: 30, 99.0))
        let builder = DailySummaryBuilder(health: health, planStore: store, calendar: cal, settings: .default)
        let s = try #require(try await builder.build(on: arrivalDay.adding(days: 20)))
        let plan = try #require(s.plan)
        #expect(plan.stageNumber == 1)
        #expect(plan.progress == nil)
        #expect(plan.actualPace == nil)
        if case .inProgress = plan.maintenance {} else { Issue.record("維持中は inProgress") }
        #expect(plan.earlyArrivalStage == 2)
        #expect(plan.shouldProposeEarlyArrival)
        #expect(plan.maintenanceNotice == .belowBand(consecutiveDays: 21))
    }

    @Test("当日の体重がなくても 7日平均は過去6日から出る")
    func todayMissing() async throws {
        let health = MockHealthStore(weights: samples(from: start.adding(days: -6), days: 6, 124.0))
        let builder = DailySummaryBuilder(health: health, planStore: try makeStore(), calendar: cal, settings: .default)
        let s = try #require(try await builder.build(on: start))
        #expect(s.todayWeight == nil)
        #expect(s.sevenDayAverage?.kilograms == 124.0)
        #expect(s.sevenDayAverage?.daysUsed == 6)
    }

    @Test("体脂肪率も当日の値を返す")
    func bodyFat() async throws {
        let at = start.startDate(in: cal).addingTimeInterval(8 * 3600)
        let health = MockHealthStore(weights: samples(from: start, days: 1, 123.5),
                                     bodyFats: [BodyFatSample(fraction: 0.352, measuredAt: at, source: .healthPlanet)])
        let builder = DailySummaryBuilder(health: health, planStore: try makeStore(), calendar: cal, settings: .default)
        let s = try #require(try await builder.build(on: start))
        #expect(s.todayBodyFat?.fraction == 0.352)
    }
}
