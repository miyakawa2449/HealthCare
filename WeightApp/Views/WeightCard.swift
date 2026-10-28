import SwiftUI
import WeightCore

/// 7日平均(大)、当日の測定(小)、グラフ。
struct WeightCard: View {
    let summary: DailySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("直近7日間の平均")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)

            if let average = summary.sevenDayAverage {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(DisplayFormat.kilogramsNumber(average.kilograms))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                    Text("kg").font(.title3).foregroundStyle(AppTheme.secondaryText)
                }
                todayLine
            } else {
                Text("直近7日間に記録がありません")
                    .font(.title3.weight(.semibold))
                Text("HealthPlanet で同期すると、ここに表示されます。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            WeightChart(points: summary.history)
                .frame(height: 96)
                .padding(.top, 4)

            legend

            Text("点線は計画のペースです。日々の上下は気にしなくて大丈夫です。")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .card()
    }

    private var todayLine: some View {
        Group {
            if let today = summary.todayWeight {
                Text("今日の測定 \(DisplayFormat.kilograms(today.kilograms)) ・ \(DisplayFormat.time(today.measuredAt))")
            } else {
                Text("今日はまだ測っていません")
            }
        }
        .font(.subheadline)
        .foregroundStyle(AppTheme.secondaryText)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Rectangle().fill(AppTheme.accent).frame(width: 18, height: 2)
                Text("7日平均")
            }
            HStack(spacing: 6) {
                Line().stroke(AppTheme.secondaryText, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).frame(width: 18, height: 2)
                Text("計画")
            }
        }
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryText)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
