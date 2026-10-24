import Foundation
import Testing
@testable import WeightCore

struct ActualPaceTests {
    let s = PlanSettings.default
    let start = day(2026, 10, 18)
    var stage1: PlanPhase { .losing(stage: 1, origin: StageOrigin(weight: 123.5, day: start)) }

    /// 起点から `thenOffset` 日までの7日を `before`、`nowOffset` 日までの7日を `after` にしたデータ。
    /// 窓が重なる日は `after` が優先(1日1件)。
    func weights(origin: CalendarDay, thenOffset: Int, before: Double, nowOffset: Int, after: Double) -> [DailyWeight] {
        var entries: [CalendarDay: Double] = [:]
        for i in (thenOffset - 6)...thenOffset { entries[origin.adding(days: i)] = before }
        for i in (nowOffset - 6)...nowOffset { entries[origin.adding(days: i)] = after }
        return dailyWeights(entries)
    }

    /// データから実際の7日平均の比を取り、30/n 乗で月換算した期待値。
    func expectedRate(_ w: [DailyWeight], origin: CalendarDay, windowStart: Int, end: Int) -> Double {
        let now = SevenDayAverage(endingOn: origin.adding(days: end), in: w)!.kilograms
        let then = SevenDayAverage(endingOn: origin.adding(days: windowStart), in: w)!.kilograms
        return 1 - pow(now / then, 30.0 / Double(end - windowStart))
    }

    func pace(_ phase: PlanPhase, on day: CalendarDay, _ w: [DailyWeight]) -> ActualPace? {
        ActualPace(endingOn: day, phase: phase, weights: w, settings: s)
    }

    // MARK: ステージ1(最初の1か月と14日目の下限)

    @Test("ちょうど月3%は速すぎではない")
    func exactlyThreePercent() throws {
        let w = weights(origin: start, thenOffset: 13, before: 100.0, nowOffset: 41, after: 97.197)
        let p = try #require(pace(stage1, on: start.adding(days: 41), w))
        #expect(p.windowDays == 28)
        #expect(Ratio.rounded(p.monthlyRate) == 0.03)
        #expect(!p.isTooFast(settings: s))
    }

    @Test("月3%超は速すぎ")
    func tooFast() throws {
        let w = weights(origin: start, thenOffset: 13, before: 100.0, nowOffset: 41, after: 97.0)
        let p = try #require(pace(stage1, on: start.adding(days: 41), w))
        #expect(abs(p.monthlyRate - 0.0321) < 0.0001)
        #expect(p.isTooFast(settings: s))
    }

    @Test("増えているときは負の値で、速すぎではない")
    func gaining() throws {
        let w = weights(origin: start, thenOffset: 13, before: 100.0, nowOffset: 41, after: 101.0)
        let p = try #require(pace(stage1, on: start.adding(days: 41), w))
        #expect(p.monthlyRate < 0)
        #expect(!p.isTooFast(settings: s))
    }

    @Test("窓の始まりの7日平均が出なければ nil")
    func missingThen() {
        let w = constantWeights(from: start.adding(days: 35), days: 7, 97.0)
        #expect(pace(stage1, on: start.adding(days: 41), w) == nil)
    }

    @Test("ステージ1の最初の1か月(経過29日)は nil")
    func firstMonth() {
        let w = weights(origin: start, thenOffset: 13, before: 100.0, nowOffset: 29, after: 97.0)
        #expect(pace(stage1, on: start.adding(days: 29), w) == nil)
    }

    @Test("31日目(経過30日)は窓が14日目から始まり、n = 17")
    func day31() throws {
        let w = weights(origin: start, thenOffset: 13, before: 100.0, nowOffset: 30, after: 98.0)
        let p = try #require(pace(stage1, on: start.adding(days: 30), w))
        #expect(p.windowDays == 17)
        #expect(abs(p.monthlyRate - (1 - pow(0.98, 30.0 / 17.0))) < 1e-9)
    }

    @Test("41日目(経過40日)は n = 27")
    func day41() throws {
        let w = weights(origin: start, thenOffset: 13, before: 100.0, nowOffset: 40, after: 98.0)
        #expect(try #require(pace(stage1, on: start.adding(days: 40), w)).windowDays == 27)
    }

    @Test("42日目(経過41日)で初めて28日の窓になる")
    func day42() throws {
        let w = weights(origin: start, thenOffset: 13, before: 100.0, nowOffset: 41, after: 98.0)
        let p = try #require(pace(stage1, on: start.adding(days: 41), w))
        #expect(p.windowDays == 28)
        #expect(abs(p.monthlyRate - (1 - pow(0.98, 30.0 / 28.0))) < 1e-9)
    }

    @Test("43日目(経過42日)は窓が経過14日から、n = 28")
    func day43() throws {
        let w = weights(origin: start, thenOffset: 14, before: 100.0, nowOffset: 42, after: 98.0)
        #expect(try #require(pace(stage1, on: start.adding(days: 42), w)).windowDays == 28)
    }

    // MARK: ステージ2以降(窓の始まりはステージ開始日より前にしない)

    let stage2Origin = day(2027, 5, 22)
    var stage2: PlanPhase { .losing(stage: 2, origin: StageOrigin(weight: 110.9, day: day(2027, 5, 22))) }

    @Test("ステージ開始日(経過0日)は窓がないので nil")
    func stageStartDay() {
        let w = constantWeights(from: stage2Origin.adding(days: -6), days: 7, 110.9)
        #expect(pace(stage2, on: stage2Origin, w) == nil)
    }

    @Test("ステージ開始直後(経過1日)は n = 1 で、30/1 乗で換算する")
    func dayAfterStageStart() throws {
        let w = weights(origin: stage2Origin, thenOffset: 0, before: 110.9, nowOffset: 1, after: 110.8)
        let p = try #require(pace(stage2, on: stage2Origin.adding(days: 1), w))
        #expect(p.windowDays == 1)
        // 窓が重なるので、期待値はデータの実際の7日平均から 30/1 乗で出す
        #expect(abs(p.monthlyRate - expectedRate(w, origin: stage2Origin, windowStart: 0, end: 1)) < 1e-9)
    }

    @Test("ステージの28日目(経過27日)は n = 27、29日目(経過28日)で初めて n = 28")
    func stageDay28And29() throws {
        let w27 = weights(origin: stage2Origin, thenOffset: 0, before: 110.9, nowOffset: 27, after: 109.0)
        #expect(try #require(pace(stage2, on: stage2Origin.adding(days: 27), w27)).windowDays == 27)
        let w28 = weights(origin: stage2Origin, thenOffset: 0, before: 110.9, nowOffset: 28, after: 109.0)
        let p = try #require(pace(stage2, on: stage2Origin.adding(days: 28), w28))
        #expect(p.windowDays == 28)
        #expect(abs(p.monthlyRate - (1 - pow(109.0 / 110.9, 30.0 / 28.0))) < 1e-9)
    }

    @Test("ステージの30日目(経過29日)は窓が経過1日に動き、n = 28 のまま")
    func stageDay30() throws {
        let w = weights(origin: stage2Origin, thenOffset: 1, before: 110.9, nowOffset: 29, after: 109.0)
        #expect(try #require(pace(stage2, on: stage2Origin.adding(days: 29), w)).windowDays == 28)
    }

    @Test("ステージ2以降に最初の1か月の除外はない(経過10日でも計算する)")
    func noFirstMonthBlackoutInLaterStages() throws {
        let w = weights(origin: stage2Origin, thenOffset: 0, before: 110.9, nowOffset: 10, after: 110.0)
        #expect(try #require(pace(stage2, on: stage2Origin.adding(days: 10), w)).windowDays == 10)
    }

    @Test("維持中と維持モードでは nil")
    func notWhileMaintaining() {
        let arrival = StageOrigin(weight: 111.2, day: day(2027, 3, 23))
        let w = constantWeights(from: day(2027, 3, 1), days: 90, 111.0)
        #expect(pace(.maintaining(stage: 1, arrival: arrival), on: day(2027, 5, 1), w) == nil)
        #expect(pace(.maintenanceMode(arrival: arrival), on: day(2027, 5, 1), w) == nil)
    }
}
