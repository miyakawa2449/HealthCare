import Foundation
import Testing
@testable import WeightCore

struct CalendarDayTests {
    @Test("JST の日付に落ちる(UTC では前日の時刻)")
    func fromDateInTokyo() {
        let d = CalendarDay(date: jst(2026, 10, 18, 8), calendar: TestCalendar.tokyo)
        #expect(d == day(2026, 10, 18))
    }

    @Test("日付の境界: 23:59:59 と翌 00:00:00 は別の日")
    func boundary() {
        let a = CalendarDay(date: jst(2026, 10, 18, 23, 59, 59), calendar: TestCalendar.tokyo)
        let b = CalendarDay(date: jst(2026, 10, 19, 0, 0, 0), calendar: TestCalendar.tokyo)
        #expect(a == day(2026, 10, 18))
        #expect(b == day(2026, 10, 19))
    }

    @Test("日数の加算")
    func adding() {
        #expect(day(2026, 10, 18).adding(days: 14) == day(2026, 11, 1))
        #expect(day(2028, 2, 28).adding(days: 2) == day(2028, 3, 1))
        #expect(day(2026, 10, 18).adding(days: -18) == day(2026, 9, 30))
    }

    @Test("日数差")
    func daysUntil() {
        #expect(day(2026, 10, 18).days(until: day(2026, 11, 1)) == 14)
        #expect(day(2026, 11, 1).days(until: day(2026, 10, 18)) == -14)
        #expect(day(2026, 10, 18).days(until: day(2026, 10, 18)) == 0)
    }

    @Test("順序")
    func ordering() {
        #expect(day(2026, 10, 18) < day(2026, 10, 19))
        #expect(day(2026, 12, 31) < day(2027, 1, 1))
    }
}
