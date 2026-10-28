import Foundation
import WeightCore

/// 画面に出す文字列への整形。日付と時刻は Asia/Tokyo に固定し、端末の設定に依存しない。
enum DisplayFormat {
    private static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = AppCalendar.tokyo.timeZone
        f.dateFormat = "HH:mm"
        return f
    }()

    /// "123.5 kg"。丸めは WeightCore と同じ。
    static func kilograms(_ value: Double) -> String {
        String(format: "%.1f kg", Weight.rounded(value))
    }

    /// "123.5"(単位なし。入力欄の初期値用)。
    static func kilogramsNumber(_ value: Double) -> String {
        String(format: "%.1f", Weight.rounded(value))
    }

    /// "月" など1文字の曜日。
    static func weekdaySymbol(_ day: CalendarDay) -> String {
        let weekday = AppCalendar.tokyo.component(.weekday, from: day.startDate(in: AppCalendar.tokyo))
        return weekdaySymbols[weekday - 1]
    }

    /// "10月18日(日)"。0 埋めしない。
    static func dayWithWeekday(_ day: CalendarDay) -> String {
        "\(day.month)月\(day.day)日(\(weekdaySymbol(day)))"
    }

    /// "2029年2月3日"。
    static func fullDate(_ day: CalendarDay) -> String {
        "\(day.year)年\(day.month)月\(day.day)日"
    }

    /// "2027年1月上旬"。1〜10日は上旬、11〜20日は中旬、21日以降は下旬。
    static func approximateDate(_ day: CalendarDay) -> String {
        let part: String
        switch day.day {
        case ...10: part = "上旬"
        case 11...20: part = "中旬"
        default: part = "下旬"
        }
        return "\(day.year)年\(day.month)月\(part)"
    }

    /// "17:47"(Asia/Tokyo)。
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
