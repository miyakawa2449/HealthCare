import Foundation
import Observation
import WeightCore

/// ホーム画面の状態。フォアグラウンドに戻るたびに HealthKit から取り直す。
/// 取り直しに失敗したときは前回の値を残し、失敗したことだけを持つ(見せ方はフェーズ4で決める)。
@MainActor
@Observable
final class HomeModel {
    private(set) var summary: DailySummary?
    /// 直近の取り直しが失敗した。成功すると false に戻る。
    private(set) var lastRefreshFailed = false
    /// HealthKit が使えない、または保存先(App Group)が取れない。
    private(set) var isUnavailable = false

    private let builder: DailySummaryBuilder?
    private let health: any HealthStore

    init(health: any HealthStore, planStore: PlanStore?, healthAvailable: Bool = true) {
        self.health = health
        if let planStore, healthAvailable {
            builder = DailySummaryBuilder(health: health, planStore: planStore, calendar: AppCalendar.tokyo, settings: .default)
        } else {
            builder = nil
            isUnavailable = true
        }
    }

    static func live() -> HomeModel {
        HomeModel(health: HealthKitStore(),
                  planStore: PlanStore.defaultDirectory().map { PlanStore(directory: $0) },
                  healthAvailable: HealthKitStore.isAvailable)
    }

    func refresh() async {
        guard let builder else { return }
        do {
            try await health.requestReadAuthorization()
            summary = try await builder.build(on: CalendarDay(date: Date(), calendar: AppCalendar.tokyo))
            lastRefreshFailed = false
        } catch {
            lastRefreshFailed = true
        }
    }
}
