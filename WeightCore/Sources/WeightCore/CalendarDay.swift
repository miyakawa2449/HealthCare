import Foundation

/// 年・月・日だけを持つ日付。時刻とタイムゾーンを持たない。
///
/// `Date` からの変換はアプリ側が渡す `Calendar`(Asia/Tokyo)で行い、
/// 日数の加減算は暦日の差分なので UTC 固定のカレンダーで計算する。
public struct CalendarDay: Sendable, Hashable, Comparable, Codable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// `date` を `calendar` のタイムゾーンで日付に落とす。
    public init(date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public func adding(days: Int) -> CalendarDay {
        let base = Self.utc.date(from: DateComponents(year: year, month: month, day: day))!
        let moved = Self.utc.date(byAdding: .day, value: days, to: base)!
        return CalendarDay(date: moved, calendar: Self.utc)
    }

    /// self から other までの日数。other が過去なら負。
    public func days(until other: CalendarDay) -> Int {
        let a = Self.utc.date(from: DateComponents(year: year, month: month, day: day))!
        let b = Self.utc.date(from: DateComponents(year: other.year, month: other.month, day: other.day))!
        return Self.utc.dateComponents([.day], from: a, to: b).day!
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
