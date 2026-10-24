import Foundation
import HealthKit
import WeightCore

/// HealthKit をこの背後に置く。アプリ本体はこのプロトコルだけを見て、テストとシミュレーターではモックに差し替える。
protocol HealthStore: Sendable {
    /// 体重と体脂肪率の読み取り権限を求める(書き込みは求めない)。
    func requestReadAuthorization() async throws
    /// `from` 以上 `to` 未満の体重サンプル。
    func weightSamples(from: Date, to: Date) async throws -> [WeightSample]
    /// `from` 以上 `to` 未満の体脂肪率サンプル。
    func bodyFatSamples(from: Date, to: Date) async throws -> [BodyFatSample]
}

/// テストとシミュレーター用。
actor MockHealthStore: HealthStore {
    var weights: [WeightSample]
    var bodyFats: [BodyFatSample]
    private(set) var authorizationRequests = 0
    private(set) var requestedRanges: [(from: Date, to: Date)] = []
    /// 設定すると取得時にこのエラーを投げる(失敗時の挙動のテスト用)。
    var failure: (any Error)?

    func setFailure(_ error: (any Error)?) { failure = error }

    init(weights: [WeightSample], bodyFats: [BodyFatSample] = []) {
        self.weights = weights
        self.bodyFats = bodyFats
    }

    func requestReadAuthorization() async throws { authorizationRequests += 1 }

    func weightSamples(from: Date, to: Date) async throws -> [WeightSample] {
        requestedRanges.append((from, to))
        if let failure { throw failure }
        return weights.filter { $0.measuredAt >= from && $0.measuredAt < to }
    }

    func bodyFatSamples(from: Date, to: Date) async throws -> [BodyFatSample] {
        bodyFats.filter { $0.measuredAt >= from && $0.measuredAt < to }
    }
}

/// 実機・シミュレーターの HealthKit。取得と変換だけを行い、1日の値の決定は WeightCore に任せる。
final class HealthKitStore: HealthStore, @unchecked Sendable {
    private let store = HKHealthStore()
    private let bodyMass = HKQuantityType(.bodyMass)
    private let bodyFat = HKQuantityType(.bodyFatPercentage)

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestReadAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: [bodyMass, bodyFat])
    }

    func weightSamples(from: Date, to: Date) async throws -> [WeightSample] {
        try await quantitySamples(of: bodyMass, from: from, to: to).map {
            HealthSampleMapper.weight($0, bundleIdentifier: $0.sourceRevision.source.bundleIdentifier)
        }
    }

    func bodyFatSamples(from: Date, to: Date) async throws -> [BodyFatSample] {
        try await quantitySamples(of: bodyFat, from: from, to: to).map {
            HealthSampleMapper.bodyFat($0, bundleIdentifier: $0.sourceRevision.source.bundleIdentifier)
        }
    }

    private func quantitySamples(of type: HKQuantityType, from: Date, to: Date) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
        #if DEBUG
        // HealthPlanet の Bundle ID を実機で確認するための出力(DataSourceSettings に入れたら不要になる)
        let sources = Set(samples.map { $0.sourceRevision.source.bundleIdentifier })
        if !sources.isEmpty { print("[HealthKit] \(type.identifier) sources: \(sources.sorted())") }
        #endif
        return samples
    }
}
