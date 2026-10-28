import Foundation
import Testing
import WeightCore
@testable import WeightApp

struct DisplayFormatTests {
    @Test("日付と曜日。0 埋めしない")
    func dayWithWeekday() {
        #expect(DisplayFormat.dayWithWeekday(CalendarDay(year: 2026, month: 10, day: 18)) == "10月18日(日)")
        #expect(DisplayFormat.dayWithWeekday(CalendarDay(year: 2026, month: 1, day: 5)) == "1月5日(月)")
        #expect(DisplayFormat.dayWithWeekday(CalendarDay(year: 2026, month: 10, day: 31)) == "10月31日(土)")
    }

    @Test("上旬・中旬・下旬の境界", arguments: [
        (1, "上旬"), (10, "上旬"), (11, "中旬"), (20, "中旬"), (21, "下旬"), (31, "下旬"),
    ])
    func approximate(day: Int, part: String) {
        #expect(DisplayFormat.approximateDate(CalendarDay(year: 2027, month: 1, day: day)) == "2027年1月\(part)")
    }

    @Test("時刻は端末のタイムゾーンによらず Asia/Tokyo")
    func time() {
        // 2026-10-18 08:47 UTC = 17:47 JST
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 8, minute: 47))!
        #expect(DisplayFormat.time(date) == "17:47")
    }

    @Test("体重の整形は WeightCore と同じ丸め")
    func kilograms() {
        #expect(DisplayFormat.kilograms(123.45) == "123.5 kg")
        #expect(DisplayFormat.kilograms(123.5) == "123.5 kg")
        #expect(DisplayFormat.kilogramsNumber(67.375) == "67.4")
    }

    @Test("年月日")
    func fullDate() {
        #expect(DisplayFormat.fullDate(CalendarDay(year: 2029, month: 2, day: 3)) == "2029年2月3日")
    }

    @Test("曜日の1文字")
    func weekday() {
        #expect(DisplayFormat.weekdaySymbol(CalendarDay(year: 2026, month: 10, day: 12)) == "月")
        #expect(DisplayFormat.weekdaySymbol(CalendarDay(year: 2026, month: 10, day: 18)) == "日")
    }
}

struct WeekRecordTests {
    @Test("週は月曜始まり", arguments: [
        (CalendarDay(year: 2026, month: 10, day: 12), CalendarDay(year: 2026, month: 10, day: 12)),  // 月
        (CalendarDay(year: 2026, month: 10, day: 14), CalendarDay(year: 2026, month: 10, day: 12)),  // 水
        (CalendarDay(year: 2026, month: 10, day: 18), CalendarDay(year: 2026, month: 10, day: 12)),  // 日
        (CalendarDay(year: 2026, month: 10, day: 19), CalendarDay(year: 2026, month: 10, day: 19)),  // 翌週の月
    ])
    func weekStart(day: CalendarDay, monday: CalendarDay) {
        #expect(WeekRecordCard.weekStart(of: day) == monday)
    }

    @Test("進み具合のバーの割合は 0〜1 に収め、7日平均がなければ 0、起点がめざす体重以下なら 1")
    func fraction() {
        #expect(StageCard.fraction(origin: 123.5, target: 117.3, current: 120.4) == (123.5 - 120.4) / (123.5 - 117.3))
        #expect(StageCard.fraction(origin: 123.5, target: 117.3, current: nil) == 0)
        #expect(StageCard.fraction(origin: 123.5, target: 117.3, current: 125.0) == 0)
        #expect(StageCard.fraction(origin: 123.5, target: 117.3, current: 110.0) == 1)
        #expect(StageCard.fraction(origin: 117.0, target: 117.3, current: 117.0) == 1)
    }
}
