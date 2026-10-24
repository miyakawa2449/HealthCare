import Foundation
import WeightCore

/// アプリで使うカレンダー。日付の境界は Asia/Tokyo に固定する(AGENTS.md)。`Calendar.current` は使わない。
enum AppCalendar {
    static let tokyo: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()
}

extension CalendarDay {
    /// その日の 0 時(`calendar` のタイムゾーン)。
    func startDate(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
