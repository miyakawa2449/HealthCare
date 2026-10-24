import Foundation
import Testing
@testable import WeightCore

struct DailyWeightResolverTests {
    let cal = TestCalendar.tokyo

    func sample(_ kg: Double, _ date: Date, _ source: SampleSource = .other) -> WeightSample {
        WeightSample(kilograms: kg, measuredAt: date, source: source)
    }

    @Test("同じ日に2件なら早い方")
    func firstOfDay() {
        let r = DailyWeightResolver.resolve([
            sample(122.9, jst(2026, 10, 18, 19)),
            sample(123.8, jst(2026, 10, 18, 7)),
        ], calendar: cal)
        #expect(r.map(\.kilograms) == [123.8])
    }

    @Test("HealthPlanet 由来を優先(時刻が遅くても)")
    func healthPlanetWins() {
        let r = DailyWeightResolver.resolve([
            sample(123.0, jst(2026, 10, 18, 7), .other),
            sample(123.5, jst(2026, 10, 18, 8), .healthPlanet),
        ], calendar: cal)
        #expect(r.count == 1)
        #expect(r[0].kilograms == 123.5)
        #expect(r[0].source == .healthPlanet)
    }

    @Test("HealthPlanet が複数なら、その中で早い方")
    func firstHealthPlanet() {
        let r = DailyWeightResolver.resolve([
            sample(122.8, jst(2026, 10, 18, 20), .healthPlanet),
            sample(123.5, jst(2026, 10, 18, 8), .healthPlanet),
        ], calendar: cal)
        #expect(r.map(\.kilograms) == [123.5])
    }

    @Test("HealthPlanet がない日は他ソースを使う")
    func fallbackToOther() {
        let r = DailyWeightResolver.resolve([sample(123.0, jst(2026, 10, 18, 7), .other)], calendar: cal)
        #expect(r.map(\.kilograms) == [123.0])
        #expect(r[0].source == .other)
    }

    @Test("JST の日付境界で別の日になる")
    func splitsAtMidnightTokyo() {
        let r = DailyWeightResolver.resolve([
            sample(123.0, jst(2026, 10, 18, 23, 30)),
            sample(122.5, jst(2026, 10, 19, 0, 30)),
        ], calendar: cal)
        #expect(r.map(\.day) == [day(2026, 10, 18), day(2026, 10, 19)])
    }

    @Test("UTC では前日になる時刻でも JST の日に入る")
    func utcPreviousDay() {
        // 10-18 08:00 JST = 10-17 23:00 UTC
        let r = DailyWeightResolver.resolve([sample(123.5, jst(2026, 10, 18, 8))], calendar: cal)
        #expect(r.map(\.day) == [day(2026, 10, 18)])
    }

    @Test("空なら空")
    func empty() {
        #expect(DailyWeightResolver.resolve([], calendar: cal).isEmpty)
    }

    @Test("日付の昇順で返る")
    func sorted() {
        let r = DailyWeightResolver.resolve([
            sample(122.0, jst(2026, 10, 20, 8)),
            sample(123.5, jst(2026, 10, 18, 8)),
            sample(122.7, jst(2026, 10, 19, 8)),
        ], calendar: cal)
        #expect(r.map(\.day) == [day(2026, 10, 18), day(2026, 10, 19), day(2026, 10, 20)])
    }
}
