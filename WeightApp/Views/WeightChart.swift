import Charts
import SwiftUI
import WeightCore

/// 7日平均の実線と計画の点線。軸の目盛り・数値・グリッドは出さない(ホームに目安の数値を出さない方針)。
struct WeightChart: View {
    let points: [DailyPoint]

    /// 実線は記録が途切れたところで切る。切れ目ごとに系列番号を振る。
    private var averageSegments: [(segment: Int, day: CalendarDay, value: Double)] {
        var result: [(Int, CalendarDay, Double)] = []
        var segment = 0
        var previousWasNil = true
        for p in points {
            if let v = p.sevenDayAverage {
                if previousWasNil { segment += 1 }
                result.append((segment, p.day, v))
                previousWasNil = false
            } else {
                previousWasNil = true
            }
        }
        return result
    }

    private var guidelinePoints: [(day: CalendarDay, value: Double)] {
        points.compactMap { p in p.guideline.map { (p.day, $0) } }
    }

    private var yDomain: ClosedRange<Double>? {
        let values = points.compactMap(\.sevenDayAverage) + points.compactMap(\.guideline)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        let pad = max((hi - lo) * 0.2, 0.5)
        return (lo - pad)...(hi + pad)
    }

    private func date(_ day: CalendarDay) -> Date { day.startDate(in: AppCalendar.tokyo) }

    var body: some View {
        let segments = averageSegments
        let guideline = guidelinePoints
        let singlePoint = segments.count == 1
        Chart {
            ForEach(Array(guideline.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("日", date(p.day)), y: .value("計画", p.value), series: .value("系列", "計画"))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                if guideline.count == 1 {
                    PointMark(x: .value("日", date(p.day)), y: .value("計画", p.value))
                        .foregroundStyle(AppTheme.secondaryText)
                        .symbolSize(24)
                }
            }
            ForEach(Array(segments.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("日", date(p.day)), y: .value("7日平均", p.value), series: .value("系列", "7日平均 \(p.segment)"))
                    .foregroundStyle(AppTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                if singlePoint || p.day == points.last?.day {
                    PointMark(x: .value("日", date(p.day)), y: .value("7日平均", p.value))
                        .foregroundStyle(AppTheme.accent)
                        .symbolSize(48)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .modifier(YDomain(domain: yDomain))
        // 各点の値(計画の数値を含む)は読み上げない。グラフは形だけを見せる
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("直近\(points.count)日の7日平均と計画のグラフ")
    }

    private struct YDomain: ViewModifier {
        let domain: ClosedRange<Double>?
        func body(content: Content) -> some View {
            if let domain { content.chartYScale(domain: domain) } else { content }
        }
    }
}

#Preview("1点だけ(計画初日)") {
    WeightChart(points: PreviewData.points(days: 1, start: 123.5, slopePerDay: 0, withGuideline: true))
        .frame(height: 96).padding()
}

#Preview("28日分") {
    WeightChart(points: PreviewData.points(days: 28, start: 123.5, slopePerDay: -0.08, withGuideline: true))
        .frame(height: 96).padding()
}

#Preview("途中に欠けあり") {
    WeightChart(points: PreviewData.points(days: 28, start: 123.5, slopePerDay: -0.08, withGuideline: true, gap: 10..<16))
        .frame(height: 96).padding()
}

#Preview("維持期間(水平の点線)") {
    WeightChart(points: PreviewData.points(days: 28, start: 111.0, slopePerDay: 0.01, withGuideline: true, flatGuideline: 111.2))
        .frame(height: 96).padding()
}
