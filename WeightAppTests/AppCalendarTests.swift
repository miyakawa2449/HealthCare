import Foundation
import Testing
import WeightCore
@testable import WeightApp

struct AppCalendarTests {
    @Test("カレンダーは Asia/Tokyo 固定")
    func timeZone() {
        #expect(AppCalendar.tokyo.timeZone.identifier == "Asia/Tokyo")
        #expect(AppCalendar.tokyo.identifier == .gregorian)
    }

    @Test("10-18 08:00 JST(10-17 23:00 UTC)は 10-18")
    func dayFromDate() {
        let utc = ISO8601DateFormatter().date(from: "2026-10-17T23:00:00Z")!
        #expect(CalendarDay(date: utc, calendar: AppCalendar.tokyo) == CalendarDay(year: 2026, month: 10, day: 18))
    }

    @Test("CalendarDay から JST の 0時の Date に戻せる")
    func startDate() {
        let d = CalendarDay(year: 2026, month: 10, day: 18).startDate(in: AppCalendar.tokyo)
        #expect(d == ISO8601DateFormatter().date(from: "2026-10-17T15:00:00Z"))
    }
}
