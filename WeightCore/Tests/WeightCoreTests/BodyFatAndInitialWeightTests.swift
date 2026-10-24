import Foundation
import Testing
@testable import WeightCore

struct DailyBodyFatResolverTests {
    let cal = TestCalendar.tokyo
    func sample(_ f: Double, _ date: Date, _ source: SampleSource = .other) -> BodyFatSample {
        BodyFatSample(fraction: f, measuredAt: date, source: source)
    }

    @Test("HealthPlanet 由来を優先")
    func healthPlanetWins() {
        let r = DailyBodyFatResolver.resolve([
            sample(0.350, jst(2026, 10, 18, 7), .other),
            sample(0.352, jst(2026, 10, 18, 8), .healthPlanet),
        ], calendar: cal)
        #expect(r.map(\.fraction) == [0.352])
        #expect(r[0].source == .healthPlanet)
        #expect(r[0].day == day(2026, 10, 18))
    }

    @Test("同じ日は最初の測定値")
    func firstOfDay() {
        let r = DailyBodyFatResolver.resolve([
            sample(0.345, jst(2026, 10, 18, 20), .healthPlanet),
            sample(0.352, jst(2026, 10, 18, 8), .healthPlanet),
        ], calendar: cal)
        #expect(r.map(\.fraction) == [0.352])
    }

    @Test("JST の日付境界で別の日")
    func boundary() {
        let r = DailyBodyFatResolver.resolve([
            sample(0.35, jst(2026, 10, 18, 23, 30)),
            sample(0.34, jst(2026, 10, 19, 0, 30)),
        ], calendar: cal)
        #expect(r.map(\.day) == [day(2026, 10, 18), day(2026, 10, 19)])
    }

    @Test("体重と体脂肪率は独立に決まる")
    func independent() {
        let w = DailyWeightResolver.resolve([WeightSample(kilograms: 123.5, measuredAt: jst(2026, 10, 18, 8), source: .healthPlanet)], calendar: cal)
        let f = DailyBodyFatResolver.resolve([sample(0.35, jst(2026, 10, 19, 8))], calendar: cal)
        #expect(w.map(\.day) == [day(2026, 10, 18)])
        #expect(f.map(\.day) == [day(2026, 10, 19)])
    }
}

struct InitialWeightSuggestionTests {
    @Test("7日揃いなら平均")
    func fullWeek() {
        let w = dailyWeights(from: day(2026, 10, 12), [124.1, 123.9, 123.7, 123.6, 123.4, 123.3, 123.5])
        #expect(abs(InitialWeightSuggestion.suggest(on: day(2026, 10, 18), weights: w)! - 123.642857) < 0.000001)
    }

    @Test("3日分なら3件の平均")
    func partial() {
        let w = dailyWeights([day(2026, 10, 16): 124.0, day(2026, 10, 17): 123.0, day(2026, 10, 18): 122.0])
        #expect(InitialWeightSuggestion.suggest(on: day(2026, 10, 18), weights: w) == 123.0)
    }

    @Test("窓に0件なら最新の1件")
    func latest() {
        let w = dailyWeights([day(2026, 10, 1): 125.0, day(2026, 10, 8): 124.2])
        #expect(InitialWeightSuggestion.suggest(on: day(2026, 10, 18), weights: w) == 124.2)
    }

    @Test("データがなければ nil")
    func none() {
        #expect(InitialWeightSuggestion.suggest(on: day(2026, 10, 18), weights: []) == nil)
    }
}
