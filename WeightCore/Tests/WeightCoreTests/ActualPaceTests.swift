import Foundation
import Testing
@testable import WeightCore

struct ActualPaceTests {
    let s = PlanSettings.default
    let start = day(2026, 10, 18)

    /// 経過 `thenOffset` 日の7日平均が `before`、経過 `nowOffset` 日の7日平均が `after` になるデータ。
    func weights(thenOffset: Int, before: Double, nowOffset: Int, after: Double) -> [DailyWeight] {
        constantWeights(from: start.adding(days: thenOffset - 6), days: 7, before)
            + constantWeights(from: start.adding(days: nowOffset - 6), days: 7, after)
    }

    @Test("ちょうど月3%は速すぎではない")
    func exactlyThreePercent() throws {
        let w = weights(thenOffset: 13, before: 100.0, nowOffset: 41, after: 97.197)
        let pace = try #require(ActualPace(endingOn: start.adding(days: 41), startDay: start, weights: w, settings: s))
        #expect(pace.windowDays == 28)
        #expect(Ratio.rounded(pace.monthlyRate) == 0.03)
        #expect(!pace.isTooFast(settings: s))
    }

    @Test("月3%超は速すぎ")
    func tooFast() throws {
        let w = weights(thenOffset: 13, before: 100.0, nowOffset: 41, after: 97.0)
        let pace = try #require(ActualPace(endingOn: start.adding(days: 41), startDay: start, weights: w, settings: s))
        #expect(abs(pace.monthlyRate - 0.0321) < 0.0001)
        #expect(pace.isTooFast(settings: s))
    }

    @Test("増えているときは負の値で、速すぎではない")
    func gaining() throws {
        let w = weights(thenOffset: 13, before: 100.0, nowOffset: 41, after: 101.0)
        let pace = try #require(ActualPace(endingOn: start.adding(days: 41), startDay: start, weights: w, settings: s))
        #expect(pace.monthlyRate < 0)
        #expect(!pace.isTooFast(settings: s))
    }

    @Test("窓の始まりの7日平均が出なければ nil")
    func missingThen() {
        let w = constantWeights(from: start.adding(days: 35), days: 7, 97.0)
        #expect(ActualPace(endingOn: start.adding(days: 41), startDay: start, weights: w, settings: s) == nil)
    }

    @Test("最初の1か月(経過29日)は nil")
    func firstMonth() {
        let w = weights(thenOffset: 13, before: 100.0, nowOffset: 29, after: 97.0)
        #expect(ActualPace(endingOn: start.adding(days: 29), startDay: start, weights: w, settings: s) == nil)
    }

    @Test("31日目(経過30日)は窓が14日目から始まり、n = 17")
    func day31() throws {
        let w = weights(thenOffset: 13, before: 100.0, nowOffset: 30, after: 98.0)
        let pace = try #require(ActualPace(endingOn: start.adding(days: 30), startDay: start, weights: w, settings: s))
        #expect(pace.windowDays == 17)
        #expect(abs(pace.monthlyRate - (1 - pow(0.98, 30.0 / 17.0))) < 1e-9)
    }

    @Test("41日目(経過40日)は n = 27")
    func day41() throws {
        let w = weights(thenOffset: 13, before: 100.0, nowOffset: 40, after: 98.0)
        let pace = try #require(ActualPace(endingOn: start.adding(days: 40), startDay: start, weights: w, settings: s))
        #expect(pace.windowDays == 27)
    }

    @Test("42日目(経過41日)で初めて28日の窓になる")
    func day42() throws {
        let w = weights(thenOffset: 13, before: 100.0, nowOffset: 41, after: 98.0)
        let pace = try #require(ActualPace(endingOn: start.adding(days: 41), startDay: start, weights: w, settings: s))
        #expect(pace.windowDays == 28)
        #expect(abs(pace.monthlyRate - (1 - pow(0.98, 30.0 / 28.0))) < 1e-9)
    }

    @Test("43日目(経過42日)は窓が経過14日から、n = 28")
    func day43() throws {
        let w = weights(thenOffset: 14, before: 100.0, nowOffset: 42, after: 98.0)
        let pace = try #require(ActualPace(endingOn: start.adding(days: 42), startDay: start, weights: w, settings: s))
        #expect(pace.windowDays == 28)
    }
}
