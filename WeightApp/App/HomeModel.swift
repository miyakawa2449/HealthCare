import Foundation
import Observation
import WeightCore

/// ホーム画面の状態。フォアグラウンドに戻るたびに HealthKit から取り直す。
@MainActor
@Observable
final class HomeModel {
    private(set) var summary: DailySummary?
    private(set) var isUnavailable = false

    private let builder: DailySummaryBuilder
    private let health: any HealthStore

    init(health: any HealthStore, planStore: PlanStore) {
        self.health = health
        self.builder = DailySummaryBuilder(health: health, planStore: planStore, calendar: AppCalendar.tokyo, settings: .default)
    }

    static func live() -> HomeModel {
        HomeModel(health: HealthKitStore(), planStore: PlanStore(directory: PlanStore.defaultDirectory()))
    }

    func refresh() async {
        guard HealthKitStore.isAvailable || !(health is HealthKitStore) else { isUnavailable = true; return }
        do {
            try await health.requestReadAuthorization()
            summary = try await builder.build(on: CalendarDay(date: Date(), calendar: AppCalendar.tokyo))
        } catch {
            // 読めなかったときは前回の値を残す。文言はフェーズ4で決める
        }
    }
}
