import Foundation
import HealthKit
import Testing
import WeightCore
@testable import WeightApp

struct HealthSampleMapperTests {
    let healthPlanet: Set<String> = ["jp.co.tanita.healthplanet"]
    let at = ISO8601DateFormatter().date(from: "2026-10-17T23:00:00Z")!

    @Test("Bundle ID の集合に含まれれば HealthPlanet、それ以外は other、未設定ならすべて other")
    func source() {
        #expect(HealthSampleMapper.source(bundleIdentifier: "jp.co.tanita.healthplanet", healthPlanetBundleIDs: healthPlanet) == .healthPlanet)
        #expect(HealthSampleMapper.source(bundleIdentifier: "com.apple.Health", healthPlanetBundleIDs: healthPlanet) == .other)
        #expect(HealthSampleMapper.source(bundleIdentifier: nil, healthPlanetBundleIDs: healthPlanet) == .other)
        #expect(HealthSampleMapper.source(bundleIdentifier: "jp.co.tanita.healthplanet", healthPlanetBundleIDs: []) == .other)
    }

    @Test("体重は kg で取り出す")
    func weight() {
        let q = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 123.5)
        let s = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: q, start: at, end: at)
        let w = HealthSampleMapper.weight(s, bundleIdentifier: "jp.co.tanita.healthplanet", healthPlanetBundleIDs: healthPlanet)
        #expect(w.kilograms == 123.5)
        #expect(w.measuredAt == at)
        #expect(w.source == .healthPlanet)
    }

    @Test("体脂肪率は 0.0〜1.0 の割合で取り出す")
    func bodyFat() {
        let q = HKQuantity(unit: .percent(), doubleValue: 0.352)
        let s = HKQuantitySample(type: HKQuantityType(.bodyFatPercentage), quantity: q, start: at, end: at)
        let f = HealthSampleMapper.bodyFat(s, bundleIdentifier: nil, healthPlanetBundleIDs: healthPlanet)
        #expect(abs(f.fraction - 0.352) < 1e-9)
        #expect(f.source == .other)
    }
}
