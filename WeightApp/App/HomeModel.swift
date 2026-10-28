import Foundation
import Observation
import WeightCore

/// 画面の状態。フォアグラウンドに戻るたびに HealthKit から取り直す。
/// 取り直しに失敗したときは前回の値を残し、失敗したことだけを持つ。
@MainActor
@Observable
final class HomeModel {
    private(set) var summary: DailySummary?
    /// 直近の取り直しが失敗した。成功すると false に戻る。
    private(set) var lastRefreshFailed = false
    /// HealthKit が使えない、または保存先(App Group)が取れない。
    private(set) var isUnavailable = false
    enum UnavailableReason: Equatable { case healthKit, planStore }
    /// 利用不可の理由(文言の出し分け用)。
    private(set) var unavailableReason: UnavailableReason?
    /// 最初の `refresh()` が終わった(失敗でも true)。終わるまでは画面を振り分けない。
    private(set) var hasRefreshed = false

    private let builder: DailySummaryBuilder?
    private let health: any HealthStore
    private let planStore: PlanStore?
    private let calendar = AppCalendar.tokyo
    private let settings = PlanSettings.default

    init(health: any HealthStore, planStore: PlanStore?, healthAvailable: Bool = true) {
        self.health = health
        self.planStore = planStore
        if let planStore, healthAvailable {
            builder = DailySummaryBuilder(health: health, planStore: planStore, calendar: AppCalendar.tokyo, settings: .default)
        } else {
            builder = nil
            isUnavailable = true
            unavailableReason = healthAvailable ? .planStore : .healthKit
        }
    }

    static func live() -> HomeModel {
        HomeModel(health: HealthKitStore(),
                  planStore: PlanStore.defaultDirectory().map { PlanStore(directory: $0) },
                  healthAvailable: HealthKitStore.isAvailable)
    }

    private var today: CalendarDay { CalendarDay(date: Date(), calendar: calendar) }

    /// 取り直しの世代。起動時・復帰時・初回設定からの呼び出しが重なったとき、最新の要求だけが状態を反映する。
    private var refreshGeneration = 0

    func refresh() async {
        guard let builder else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let result: Result<DailySummary, any Error>
        do {
            try await health.requestReadAuthorization()
            var built = try await builder.build(on: today)
            if try recordFirstMilestoneIfReached(built) {
                built = try await builder.build(on: built.day)
            }
            result = .success(built)
        } catch {
            result = .failure(error)
        }
        // 後から始まった取り直しが先に終わっていたら、古い結果で上書きしない
        guard generation == refreshGeneration else { return }
        hasRefreshed = true
        switch result {
        case .success(let built):
            summary = built
            lastRefreshFailed = false
        case .failure:
            lastRefreshFailed = true
        }
    }

    /// 減量中のステージ1で、7日平均(丸め)が最初の区切り以下になった日を保存する(到達後は戻らない)。保存したら true。
    private func recordFirstMilestoneIfReached(_ summary: DailySummary) throws -> Bool {
        guard let planStore, let plan = summary.plan, plan.firstMilestoneReachedOn == nil,
              case .losing(let stage, _) = plan.phase, stage == 1,
              let average = summary.sevenDayAverage,
              plan.roadmap.hasReachedFirstMilestone(sevenDayAverage: average.kilograms),
              var record = try planStore.load() else { return false }
        record.firstMilestoneReachedOn = summary.day
        try planStore.save(record)
        return true
    }

    // MARK: 初回設定

    enum StartWeightSuggestion: Equatable {
        /// 直近7日平均。
        case sevenDayAverage(Double)
        /// 直近7日に記録がなく、取得した範囲の最新の1件。
        case latest(Double)
        /// 記録がない。
        case none
    }

    /// 初回設定に示す開始体重の初期値。履歴(直近 HomeSettings.historyDays 日)から決める。
    var startWeightSuggestion: StartWeightSuggestion {
        guard let summary else { return .none }
        let weights = summary.history.compactMap(\.weight)
        if let average = summary.sevenDayAverage { return .sevenDayAverage(average.kilograms) }
        if let latest = InitialWeightSuggestion.suggest(on: summary.day, weights: weights) { return .latest(latest) }
        return .none
    }

    enum StartPlanError: Error, Equatable {
        case invalid(PlanSetup.ValidationError)
        /// 保存先がない(利用不可のとき)。
        case unavailable
        /// 計画はすでに保存されている(初回設定から上書きしない)。
        case alreadyStarted
        /// 計画は保存できたが、そのあとの取り直しに失敗した。次に開いたときに取り直す。
        case savedButRefreshFailed
    }

    /// 計画を作って保存し、取り直す。開始日は今日(Asia/Tokyo)。
    /// すでに計画があれば(保存済みなのに画面が初回設定のままの場合など)上書きせずに投げる。
    func startPlan(startWeight: Double, targetWeight: Double) async throws {
        if let error = PlanSetup.validate(startWeight: startWeight, targetWeight: targetWeight) { throw StartPlanError.invalid(error) }
        guard let planStore else { throw StartPlanError.unavailable }
        guard try planStore.load() == nil else { throw StartPlanError.alreadyStarted }
        let roadmap = Roadmap(startWeight: startWeight, startDay: today, targetWeight: targetWeight, settings: settings)
        guard let phase = roadmap.initialPhase else { throw StartPlanError.invalid(.targetNotBelowStart) }
        try planStore.save(PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        await refresh()
        if summary?.plan == nil { throw StartPlanError.savedButRefreshFailed }
    }
}
