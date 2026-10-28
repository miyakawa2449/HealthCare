import Foundation
import Testing
@testable import WeightCore

struct SevenDayAverageSeriesTests {
    @Test("毎日記録があれば各日の平均が出て、使った日数は 1,2,…,7,7")
    func everyDay() {
        let weights = constantWeights(from: day(2026, 10, 1), days: 10, 100.0)
        let series = SevenDayAverage.series(from: day(2026, 10, 1), to: day(2026, 10, 10), in: weights)
        #expect(series.count == 10)
        #expect(series.map(\.day) == (0..<10).map { day(2026, 10, 1).adding(days: $0) })
        #expect(series.allSatisfy { $0.average?.kilograms == 100.0 })
        #expect(series.map { $0.average?.daysUsed } == [1, 2, 3, 4, 5, 6, 7, 7, 7, 7])
    }

    @Test("記録が窓に入らない日は nil")
    func gapsBecomeNil() {
        let weights = constantWeights(from: day(2026, 10, 1), days: 3, 100.0)
        let series = SevenDayAverage.series(from: day(2026, 10, 1), to: day(2026, 10, 12), in: weights)
        #expect(series.count == 12)
        #expect(series[0..<9].allSatisfy { $0.average != nil })   // 10/1〜10/9 は 10/3 が窓に入る
        #expect(series[9...].allSatisfy { $0.average == nil })    // 10/10 以降は入らない
    }

    @Test("記録がなければすべて nil")
    func empty() {
        let series = SevenDayAverage.series(from: day(2026, 10, 1), to: day(2026, 10, 3), in: [])
        #expect(series.count == 3)
        #expect(series.allSatisfy { $0.average == nil })
    }

    @Test("from が to より後なら空")
    func reversed() {
        #expect(SevenDayAverage.series(from: day(2026, 10, 5), to: day(2026, 10, 4), in: []).isEmpty)
    }

    @Test("各日の値は SevenDayAverage(endingOn:) と一致する")
    func matchesSingle() {
        let values: [Double] = [123.5, 123.1, 122.8, 123.0, 122.4, 122.6, 122.0, 121.9, 122.2, 121.5]
        var weights = dailyWeights(from: day(2026, 10, 1), values)
        weights.remove(at: 4)   // 欠けを入れる
        let from = day(2026, 9, 28), to = day(2026, 10, 15)
        for point in SevenDayAverage.series(from: from, to: to, in: weights) {
            #expect(point.average == SevenDayAverage(endingOn: point.day, in: weights))
        }
    }
}
