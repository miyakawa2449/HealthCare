import Foundation
@testable import WeightCore

/// テストで使う固定のカレンダー(gregorian、Asia/Tokyo)。
enum TestCalendar {
    static let tokyo: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()
}

/// JST の日時を Date にする。
func jst(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    TestCalendar.tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
    CalendarDay(year: year, month: month, day: day)
}

/// 連続する日に体重を1件ずつ置く(HealthPlanet 由来、08:00 測定)。
func dailyWeights(from start: CalendarDay, _ values: [Double]) -> [DailyWeight] {
    values.enumerated().map { offset, kg in
        let d = start.adding(days: offset)
        return DailyWeight(day: d, kilograms: kg, measuredAt: jst(d.year, d.month, d.day, 8), source: .healthPlanet)
    }
}

/// 日ごとの値を辞書で指定して DailyWeight にする。
func dailyWeights(_ entries: [CalendarDay: Double]) -> [DailyWeight] {
    entries.keys.sorted().map { d in
        DailyWeight(day: d, kilograms: entries[d]!, measuredAt: jst(d.year, d.month, d.day, 8), source: .healthPlanet)
    }
}

/// start から count 日分、すべて同じ値。
func constantWeights(from start: CalendarDay, days count: Int, _ kg: Double) -> [DailyWeight] {
    dailyWeights(from: start, Array(repeating: kg, count: count))
}
