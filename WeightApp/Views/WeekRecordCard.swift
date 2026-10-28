import SwiftUI
import WeightCore

/// 今週(月曜始まり)の記録。印だけで、連続日数や記録した日数は出さない。
struct WeekRecordCard: View {
    let day: CalendarDay
    let history: [DailyPoint]

    /// `day` を含む週の月曜日。
    static func weekStart(of day: CalendarDay) -> CalendarDay {
        let weekday = AppCalendar.tokyo.component(.weekday, from: day.startDate(in: AppCalendar.tokyo))  // 1 = 日
        return day.adding(days: -((weekday + 5) % 7))
    }

    private var days: [CalendarDay] {
        let monday = Self.weekStart(of: day)
        return (0..<7).map { monday.adding(days: $0) }
    }

    private var recorded: Set<CalendarDay> {
        Set(history.filter { $0.weight != nil }.map(\.day))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今週の記録").font(.headline)
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    VStack(spacing: 6) {
                        Text(DisplayFormat.weekdaySymbol(d))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        DayMark(number: d.day, recorded: recorded.contains(d), isToday: d == day, isFuture: d > day)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("記録した日に印がつきます。途切れても、また今日から。")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .card()
    }
}

private struct DayMark: View {
    let number: Int
    let recorded: Bool
    let isToday: Bool
    let isFuture: Bool

    var body: some View {
        Text("\(number)")
            .font(.subheadline.weight(isToday ? .bold : .regular))
            .frame(width: 34, height: 34)
            .background {
                if recorded {
                    Circle().fill(AppTheme.accent)
                } else {
                    Circle().stroke(isToday ? AppTheme.accent : AppTheme.track, lineWidth: isToday ? 2 : 1)
                }
            }
            .foregroundStyle(recorded ? Color.white : (isFuture ? AppTheme.secondaryText.opacity(0.5) : Color.primary))
            .accessibilityLabel("\(number)日\(recorded ? " 記録あり" : "")")
    }
}

#Preview("週の途中(今日が水曜)") {
    let today = CalendarDay(year: 2026, month: 10, day: 14)
    WeekRecordCard(day: today, history: PreviewData.points(days: 10, endingOn: today, start: 123.5, slopePerDay: -0.1, withGuideline: false, gap: 7..<8))
        .padding()
}

#Preview("全日記録") {
    let today = CalendarDay(year: 2026, month: 10, day: 18)
    WeekRecordCard(day: today, history: PreviewData.points(days: 10, endingOn: today, start: 123.5, slopePerDay: -0.1, withGuideline: false))
        .padding()
}

#Preview("記録なし") {
    WeekRecordCard(day: CalendarDay(year: 2026, month: 10, day: 18), history: [])
        .padding()
}
