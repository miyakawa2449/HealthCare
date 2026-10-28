import Foundation
import Testing
import WeightCore
@testable import WeightApp

struct SetupFormStateTests {
    let today = CalendarDay(year: 2026, month: 10, day: 28)

    /// `first` から `days` 日、毎日 08:00 の記録。
    func weights(from first: CalendarDay, days: Int, _ values: [Double]) -> [DailyWeight] {
        (0..<days).map { i in
            let d = first.adding(days: i)
            return DailyWeight(day: d, kilograms: values[i % values.count], measuredAt: d.startDate(in: AppCalendar.tokyo).addingTimeInterval(8 * 3600), source: .healthPlanet)
        }
    }

    @Test("初期値: 開始日は今日、開始体重は今日までの7日平均、身長 175、最終目標は BMI 22")
    func initial() {
        let s = SetupFormState(today: today, weights: weights(from: today.adding(days: -6), days: 7, [123.5]))
        #expect(s.startDay == today)
        #expect(s.startText == "123.5")
        #expect(s.heightText == "175")
        #expect(s.targetText == "67.4")
        #expect(s.canStart)
        #expect(s.firstMilestoneWeight == 117.3)
        #expect(s.earliestStartDay == today.adding(days: -6))
    }

    @Test("記録がなければ開始体重は空欄で、開始日は今日しか選べず、ボタンは無効")
    func noRecords() {
        let s = SetupFormState(today: today, weights: [])
        #expect(s.startText == "")
        #expect(s.problem == .notNumber)
        #expect(!s.canStart)
        #expect(s.earliestStartDay == today)
        #expect(s.startSuggestion == .none)
    }

    @Test("開始日を過去にすると、その日に終わる7日平均が開始体重の初期値になる")
    func startDayChangesSuggestion() {
        // 10/24 に 123.1、10/27 に 122.3、10/28 に 121.9(25・26 は記録なし)
        let w = [
            DailyWeight(day: today.adding(days: -4), kilograms: 123.1, measuredAt: Date(), source: .healthPlanet),
            DailyWeight(day: today.adding(days: -1), kilograms: 122.3, measuredAt: Date(), source: .healthPlanet),
            DailyWeight(day: today, kilograms: 121.9, measuredAt: Date(), source: .healthPlanet),
        ]
        var s = SetupFormState(today: today, weights: w)
        #expect(s.earliestStartDay == today.adding(days: -4))
        s.startDayChanged(today.adding(days: -4))
        #expect(s.startText == "123.1")
        #expect(s.startSuggestion == .sevenDayAverage(123.1))
        #expect(s.firstMilestoneWeight == Weight.rounded(123.1 * 0.95))
    }

    @Test("開始日は最初の記録の日と今日の間に収める")
    func startDayClamped() {
        var s = SetupFormState(today: today, weights: weights(from: today.adding(days: -3), days: 4, [123.0]))
        s.startDayChanged(today.adding(days: 5))
        #expect(s.startDay == today)
        s.startDayChanged(today.adding(days: -30))
        #expect(s.startDay == today.adding(days: -3))
    }

    @Test("開始体重を手で直したあとは開始日を変えても上書きしない")
    func startEdited() {
        var s = SetupFormState(today: today, weights: weights(from: today.adding(days: -6), days: 7, [123.5]))
        s.startChanged("124.0")
        s.startDayChanged(today.adding(days: -3))
        #expect(s.startText == "124.0")
    }

    @Test("身長を変えると最終目標の初期値を計算し直す")
    func heightChange() {
        var s = SetupFormState(today: today, weights: [])
        s.heightChanged("170")
        #expect(s.targetText == "63.6")
    }

    @Test("最終目標を手で直したあとは身長を変えても上書きしない")
    func targetEdited() {
        var s = SetupFormState(today: today, weights: [])
        s.targetChanged("70.0")
        s.heightChanged("170")
        #expect(s.targetText == "70.0")
    }

    @Test("数字でなければ notNumber。inf も同じ。身長が inf でも最終目標に反映しない")
    func notNumber() {
        var s = SetupFormState(today: today, weights: weights(from: today, days: 1, [123.5]))
        s.startChanged("abc")
        #expect(s.problem == .notNumber)
        s.startChanged("inf")
        #expect(s.problem == .notNumber)
        s.startChanged("123.5")
        s.heightChanged("inf")
        #expect(s.targetText == "67.4")
    }

    @Test("最終目標が開始体重以上なら targetNotBelowStart")
    func targetNotBelow() {
        var s = SetupFormState(today: today, weights: weights(from: today, days: 1, [67.0]))
        #expect(s.problem == .targetNotBelowStart)
        s.targetChanged("66.9")
        #expect(s.canStart)
    }

    @Test("0 以下は notPositive")
    func notPositive() {
        var s = SetupFormState(today: today, weights: weights(from: today, days: 1, [123.5]))
        s.targetChanged("0")
        #expect(s.problem == .notPositive)
    }
}
