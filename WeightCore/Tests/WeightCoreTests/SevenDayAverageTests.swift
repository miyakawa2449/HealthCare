import Testing
@testable import WeightCore

struct SevenDayAverageTests {
    @Test("7日揃い")
    func fullWeek() throws {
        let w = dailyWeights(from: day(2026, 10, 12), [124.1, 123.9, 123.7, 123.6, 123.4, 123.3, 123.5])
        let avg = try #require(SevenDayAverage(endingOn: day(2026, 10, 18), in: w))
        #expect(abs(avg.kilograms - 123.642857) < 0.000001)
        #expect(avg.daysUsed == 7)
    }

    @Test("欠けがあれば、ある日だけで平均し日数も返す")
    func partialWeek() throws {
        let w = dailyWeights([
            day(2026, 10, 12): 124.0, day(2026, 10, 14): 123.0, day(2026, 10, 15): 123.0,
            day(2026, 10, 17): 122.0, day(2026, 10, 18): 123.0,
        ])
        let avg = try #require(SevenDayAverage(endingOn: day(2026, 10, 18), in: w))
        #expect(avg.kilograms == 123.0)
        #expect(avg.daysUsed == 5)
    }

    @Test("窓の端: 7日前は含み、8日前は含まない")
    func windowEdges() throws {
        let w = dailyWeights([day(2026, 10, 11): 200.0, day(2026, 10, 12): 120.0, day(2026, 10, 18): 122.0])
        let avg = try #require(SevenDayAverage(endingOn: day(2026, 10, 18), in: w))
        #expect(avg.kilograms == 121.0)
        #expect(avg.daysUsed == 2)
    }

    @Test("窓にデータがなければ nil")
    func noData() {
        let w = dailyWeights([day(2026, 10, 11): 120.0, day(2026, 10, 19): 120.0])
        #expect(SevenDayAverage(endingOn: day(2026, 10, 18), in: w) == nil)
    }

    @Test("当日1件だけ")
    func single() throws {
        let avg = try #require(SevenDayAverage(endingOn: day(2026, 10, 18), in: dailyWeights([day(2026, 10, 18): 123.5])))
        #expect(avg.kilograms == 123.5)
        #expect(avg.daysUsed == 1)
    }
}
