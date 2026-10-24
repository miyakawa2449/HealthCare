import Foundation
import HealthKit
import WeightCore

/// データ元の設定。HealthPlanet が HealthKit に書き込むときの Bundle ID。
/// 2026-10-24 に実機(デバッグビルドで `HealthKitStore` がコンソールに出力する一覧)で確認した値。
/// 集合に含まれない ID はすべて `.other` として扱う。
enum DataSourceSettings {
    static let healthPlanetBundleIDs: Set<String> = ["jp.co.tanita-thl.HealthPlanet"]
}

/// HealthKit のサンプルを WeightCore の値型に変換する。
enum HealthSampleMapper {
    static func source(bundleIdentifier: String?, healthPlanetBundleIDs: Set<String> = DataSourceSettings.healthPlanetBundleIDs) -> SampleSource {
        guard let bundleIdentifier, healthPlanetBundleIDs.contains(bundleIdentifier) else { return .other }
        return .healthPlanet
    }

    static func weight(_ sample: HKQuantitySample, bundleIdentifier: String?, healthPlanetBundleIDs: Set<String> = DataSourceSettings.healthPlanetBundleIDs) -> WeightSample {
        WeightSample(kilograms: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                     measuredAt: sample.startDate,
                     source: source(bundleIdentifier: bundleIdentifier, healthPlanetBundleIDs: healthPlanetBundleIDs))
    }

    static func bodyFat(_ sample: HKQuantitySample, bundleIdentifier: String?, healthPlanetBundleIDs: Set<String> = DataSourceSettings.healthPlanetBundleIDs) -> BodyFatSample {
        BodyFatSample(fraction: sample.quantity.doubleValue(for: .percent()),
                      measuredAt: sample.startDate,
                      source: source(bundleIdentifier: bundleIdentifier, healthPlanetBundleIDs: healthPlanetBundleIDs))
    }
}
