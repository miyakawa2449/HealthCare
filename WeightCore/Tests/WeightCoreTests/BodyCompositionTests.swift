import Foundation
import Testing
@testable import WeightCore

/// 連続する日に体脂肪率を1件ずつ置く(HealthPlanet 由来、08:00 測定)。
func dailyBodyFats(from start: CalendarDay, _ values: [Double]) -> [DailyBodyFat] {
    values.enumerated().map { offset, f in
        let d = start.adding(days: offset)
        return DailyBodyFat(day: d, fraction: f, measuredAt: jst(d.year, d.month, d.day, 8), source: .healthPlanet)
    }
}

struct BodyCompositionTests {
    let s = ReportSettings.default

    @Test("除脂肪量 = 体重 × (1 − 体脂肪率)")
    func leanMass() {
        #expect(abs(BodyComposition.leanMass(weight: 100.0, bodyFat: 0.30) - 70.0) < 1e-9)
    }

    @Test("代表値は最終日に終わる7日間の平均。除脂肪量は体重と体脂肪率の両方がある日だけ")
    func snapshot() throws {
        let end = day(2026, 11, 15)
        // 11/9〜11/15 が窓。11/8 は窓の外
        let weights = dailyWeights([day(2026, 11, 8): 200, day(2026, 11, 10): 100, day(2026, 11, 12): 110, day(2026, 11, 14): 90])
        let fats = dailyBodyFats(from: day(2026, 11, 8), [0.9, 0, 0.30, 0, 0.20, 0, 0.40])
            .filter { $0.fraction > 0 }   // 11/8, 11/10, 11/12, 11/14
            + dailyBodyFats(from: day(2026, 11, 15), [0.10])   // 体脂肪率だけの日
        let snap = BodyComposition.snapshot(endingOn: end, weights: weights, bodyFats: fats)
        // 体脂肪率: 11/10, 11/12, 11/14, 11/15 の平均
        let expectedFat: Double = (0.30 + 0.20 + 0.40 + 0.10) / 4
        let fat: Double = try #require(snap.bodyFat)
        #expect(abs(fat - expectedFat) < 1e-12)
        // 除脂肪量: 11/10(70), 11/12(88), 11/14(54)
        let expectedLean: Double = (70.0 + 88.0 + 54.0) / 3
        let lean: Double = try #require(snap.leanMass)
        #expect(abs(lean - expectedLean) < 1e-9)
        #expect(snap.pairedDays == 3)
    }

    @Test("窓に0件なら代表値なし")
    func empty() {
        let snap = BodyComposition.snapshot(endingOn: day(2026, 11, 15), weights: [], bodyFats: [])
        #expect(snap.bodyFat == nil)
        #expect(snap.leanMass == nil)
    }

    @Test("体脂肪率の方向(ちょうど0.5ポイントは横ばい)", arguments: [
        (0.300, 0.295, CompositionDirection.flat),
        (0.300, 0.294, CompositionDirection.down),
        (0.300, 0.305, CompositionDirection.flat),
        (0.300, 0.306, CompositionDirection.up),
        (0.3005, 0.2955, CompositionDirection.flat),   // 浮動小数点の誤差: 30.1 → 29.6(差 0.5)
    ])
    func fatDirection(from: Double, to: Double, expected: CompositionDirection) {
        #expect(CompositionDirection.bodyFat(from: from, to: to, settings: s) == expected)
    }

    @Test("除脂肪量の方向(ちょうど0.5kgは横ばい)", arguments: [
        (80.0, 79.5, CompositionDirection.flat),
        (80.0, 79.4, CompositionDirection.down),
        (80.0, 80.5, CompositionDirection.flat),
        (80.0, 80.6, CompositionDirection.up),
        (80.04, 79.55, CompositionDirection.flat),   // 丸めて 80.0 → 79.6(差 0.4)
    ])
    func leanDirection(from: Double, to: Double, expected: CompositionDirection) {
        #expect(CompositionDirection.leanMass(from: from, to: to, settings: s) == expected)
    }

    func snap(weight: Double, fat: Double) -> CompositionSnapshot {
        CompositionSnapshot(bodyFat: fat, leanMass: weight * (1 - fat), weight: weight, fatMass: weight * fat, pairedDays: 7)
    }

    @Test("減った体重の半分以上が脂肪(ちょうど半分を含む)")
    func fatShare() {
        // 100kg・30% → 96kg: 脂肪量 30 → 28 で 2kg(体重 4kg のちょうど半分)
        let base = snap(weight: 100, fat: 0.30)
        let half = snap(weight: 96, fat: 28.0 / 96)
        #expect(BodyComposition.mostlyFatLost(from: base, to: half, settings: s))
        // 脂肪量 30 → 28.5 で 1.5kg(半分未満)
        let less = snap(weight: 96, fat: 28.5 / 96)
        #expect(!BodyComposition.mostlyFatLost(from: base, to: less, settings: s))
    }

    @Test("体重が増えた・同じなら脂肪の一言なし")
    func fatShareWhenGained() {
        let base = snap(weight: 100, fat: 0.30)
        #expect(!BodyComposition.mostlyFatLost(from: base, to: snap(weight: 101, fat: 0.25), settings: s))
        #expect(!BodyComposition.mostlyFatLost(from: base, to: snap(weight: 100, fat: 0.25), settings: s))
    }
}
