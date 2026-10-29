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

    enum RefreshOutcome: Equatable {
        /// 取り直せて、状態に反映した。
        case succeeded
        /// 取り直せなかった(前回の値を残す)。利用不可のときもこれ。
        case failed
        /// 後から始まった取り直しに置き換えられ、結果を捨てた。最新の結果は `awaitLatestRefresh()` で待つ。
        case superseded
    }

    /// 取り直しの世代。起動時・復帰時・初回設定からの呼び出しが重なったとき、最新の要求だけが状態を反映する。
    private var refreshGeneration = 0
    /// 進行中(または直近)の取り直し。置き換えられた呼び出し元はこれを待てば最新の結果を得られる。
    private var latestRefresh: Task<RefreshOutcome, Never>?

    @discardableResult
    func refresh() async -> RefreshOutcome {
        guard let builder else { return .failed }
        refreshGeneration += 1
        let generation = refreshGeneration
        let task = Task<RefreshOutcome, Never> { @MainActor [self] in
            let result = await fetch(with: builder)
            // 後から始まった取り直しが先に終わっていたら、古い結果で上書きしない
            guard generation == refreshGeneration else { return .superseded }
            hasRefreshed = true
            switch result {
            case .success(let built):
                summary = built
                lastRefreshFailed = false
                return .succeeded
            case .failure:
                lastRefreshFailed = true
                return .failed
            }
        }
        latestRefresh = task
        return await task.value
    }

    /// 最新の取り直しが終わるまで待ち、その結果を返す。途中で置き換えられたら新しい方を待ち直す。
    /// 待った Task が終わってから再開するまでの間に別の取り直しが始まっていることがあるので、
    /// 結果の種類ではなく「今も最新の Task か」で判断する。
    func awaitLatestRefresh() async -> RefreshOutcome {
        while let task = latestRefresh {
            let outcome = await task.value
            if task == latestRefresh { return outcome }
        }
        return .failed
    }

    private func fetch(with builder: DailySummaryBuilder) async -> Result<DailySummary, any Error> {
        do {
            try await health.requestReadAuthorization()
            // 自動遷移(最初の区切り、到達、卒業)は builder の中で反映して保存する
            return .success(try await builder.build(on: today))
        } catch {
            return .failure(error)
        }
    }

    // MARK: カードの操作

    /// 保存されている計画を読み、操作を適用して保存し、取り直す。
    private func mutatePlan(_ body: (inout PlanRecord) throws -> Void) async throws {
        guard let planStore else { throw PlanActionError.unavailable }
        guard var record = try planStore.load() else { throw PlanActionError.notApplicable }
        try body(&record)
        try planStore.save(record)
        await refresh()
    }

    private var currentCards: [HomeCard] {
        guard let summary, let plan = summary.plan else { return [] }
        return HomeCards.cards(for: plan, sevenDayAverage: summary.sevenDayAverage?.kilograms, on: summary.day, settings: settings)
    }

    private func requireCard(_ matches: (HomeCard) -> Bool) throws -> DailySummary {
        guard let summary, currentCards.contains(where: matches) else { throw PlanActionError.notApplicable }
        return summary
    }

    /// 85日目のカード: 次のステージへ進む。当日の7日平均が要る。
    func advanceAfterMaximum() async throws {
        let summary = try requireCard { if case .maintenanceMaximum(canAdvance: true) = $0 { return true } else { return false } }
        guard let average = summary.sevenDayAverage else { throw PlanActionError.notApplicable }
        try await mutatePlan { try $0.advanceAfterMaximum(sevenDayAverage: average.kilograms, on: summary.day) }
    }

    /// 85日目のカード: 維持を続ける。
    func continueMaintenance() async throws {
        let summary = try requireCard { if case .maintenanceMaximum = $0 { return true } else { return false } }
        try await mutatePlan { try $0.continueMaintenance(on: summary.day) }
    }

    /// 早期到達のカード: 次のステージの到達として扱う。
    func adoptEarlyArrival() async throws {
        let summary = try requireCard { if case .earlyArrival = $0 { return true } else { return false } }
        guard let average = summary.sevenDayAverage else { throw PlanActionError.notApplicable }
        try await mutatePlan { try $0.adoptEarlyArrival(sevenDayAverage: average.kilograms, on: summary.day) }
    }

    /// 早期到達のカード: 維持を続ける。
    func declineEarlyArrival() async throws {
        let summary = try requireCard { if case .earlyArrival = $0 { return true } else { return false } }
        try await mutatePlan { try $0.declineEarlyArrival(on: summary.day) }
    }

    /// 計画見直しのカード: この計画で進める。
    func adoptPlanReview() async throws {
        let summary = try requireCard { if case .planReview = $0 { return true } else { return false } }
        guard let average = summary.sevenDayAverage else { throw PlanActionError.notApplicable }
        try await mutatePlan { try $0.adoptPlanReview(sevenDayAverage: average.kilograms, on: summary.day) }
    }

    /// 計画見直しのカード: 元の計画のままにする。
    func declinePlanReview() async throws {
        let summary = try requireCard { if case .planReview = $0 { return true } else { return false } }
        try await mutatePlan { try $0.declinePlanReview(on: summary.day) }
    }

    /// ロードマップ画面: 元の計画に戻す。
    func revertToOriginalPlan() async throws {
        guard let summary, summary.plan?.record.canRevertToOriginalPlan == true else { throw PlanActionError.notApplicable }
        try await mutatePlan { try $0.revertToOriginalPlan(on: summary.day) }
    }

    /// 出来事のカードを閉じる。
    func dismissEvent(_ id: PlanEvent.ID) async throws {
        try await mutatePlan { $0.dismissEvent(id: id) }
    }

    // MARK: 初回設定

    enum StartWeightSuggestion: Equatable, Sendable {
        /// 直近7日平均。
        case sevenDayAverage(Double)
        /// 直近7日に記録がなく、取得した範囲の最新の1件。
        case latest(Double)
        /// 記録がない。
        case none
    }

    /// 取得した範囲にある1日の記録すべて(計画がなければ HealthKit の全履歴)。初回設定の初期値と開始日の範囲に使う。
    var recordedWeights: [DailyWeight] { summary?.recordedWeights ?? [] }

    /// `day` に終わる7日平均があればそれ、なければその日までの最新値、それもなければ none。
    nonisolated static func startWeightSuggestion(on day: CalendarDay, weights: [DailyWeight]) -> StartWeightSuggestion {
        if let average = SevenDayAverage(endingOn: day, in: weights) { return .sevenDayAverage(average.kilograms) }
        if let latest = InitialWeightSuggestion.suggest(on: day, weights: weights) { return .latest(latest) }
        return .none
    }

    /// 初回設定に示す開始体重の初期値(今日の分)。
    var startWeightSuggestion: StartWeightSuggestion {
        guard let summary else { return .none }
        return Self.startWeightSuggestion(on: summary.day, weights: recordedWeights)
    }

    enum StartPlanError: Error, Equatable {
        case invalid(PlanSetup.ValidationError)
        /// 保存先がない(利用不可のとき)。
        case unavailable
        /// 計画はすでに保存されている(初回設定から上書きしない)。
        case alreadyStarted
        /// 計画は保存できたが、そのあとの取り直しに失敗した。次に開いたときに取り直す。
        case savedButRefreshFailed
        /// 開始日が今日より後。
        case startDayInFuture
    }

    /// 計画を作って保存し、取り直す。開始日は指定がなければ今日(Asia/Tokyo)。今日より後は受け付けない。
    /// すでに計画があれば(保存済みなのに画面が初回設定のままの場合など)上書きせずに投げる。
    func startPlan(startWeight: Double, targetWeight: Double, startDay: CalendarDay? = nil) async throws {
        if let error = PlanSetup.validate(startWeight: startWeight, targetWeight: targetWeight) { throw StartPlanError.invalid(error) }
        guard let planStore else { throw StartPlanError.unavailable }
        let startDay = startDay ?? today
        guard startDay <= today else { throw StartPlanError.startDayInFuture }
        guard try planStore.load() == nil else { throw StartPlanError.alreadyStarted }
        let roadmap = Roadmap(startWeight: startWeight, startDay: startDay, targetWeight: targetWeight, settings: settings)
        guard let phase = roadmap.initialPhase else { throw StartPlanError.invalid(.targetNotBelowStart) }
        try planStore.save(PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        // 自分の取り直しが別の取り直しに置き換えられても、最新の結果が出るまで待ってから判断する
        await refresh()
        if await awaitLatestRefresh() != .succeeded || summary?.plan == nil { throw StartPlanError.savedButRefreshFailed }
    }
}
