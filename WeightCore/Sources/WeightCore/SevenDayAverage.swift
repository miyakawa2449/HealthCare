/// 直近7日間(当日を含む)の単純平均。窓にある日だけで平均し、使った日数も持つ。
public struct SevenDayAverage: Sendable, Equatable {
    public static let windowDays = 7

    public var kilograms: Double
    /// 平均に使った日数(1〜7)。
    public var daysUsed: Int

    /// 窓に1件もなければ nil。
    public init?(endingOn day: CalendarDay, in weights: [DailyWeight]) {
        let first = day.adding(days: -(Self.windowDays - 1))
        let inWindow = weights.filter { $0.day >= first && $0.day <= day }
        guard !inWindow.isEmpty else { return nil }
        kilograms = inWindow.map(\.kilograms).reduce(0, +) / Double(inWindow.count)
        daysUsed = inWindow.count
    }
}
