import Foundation
import WeightCore

/// 初回設定の入力欄の状態。View から切り離してテストする。
struct SetupFormState: Equatable {
    /// 今日(Asia/Tokyo)。開始日の上限。
    let today: CalendarDay
    /// 開始日として選べる最初の日(記録の最初の日。記録がなければ今日)。
    let earliestStartDay: CalendarDay
    private(set) var startDay: CalendarDay
    var startText: String
    var heightText: String
    var targetText: String
    /// 開始体重を手で直した。以後は開始日を変えても上書きしない。
    private(set) var startEdited = false
    /// 最終目標を手で直した。以後は身長を変えても上書きしない。
    private(set) var targetEdited = false

    private let weights: [DailyWeight]
    private let settings: PlanSettings

    init(today: CalendarDay, weights: [DailyWeight], settings: PlanSettings = .default) {
        self.today = today
        self.weights = weights
        self.settings = settings
        earliestStartDay = weights.map(\.day).min() ?? today
        startDay = today
        startText = Self.startText(on: today, weights: weights) ?? ""
        heightText = String(Int(PlanSetup.defaultHeightCentimeters))
        targetText = Self.targetText(heightText: heightText, settings: settings) ?? ""
    }

    static func == (lhs: SetupFormState, rhs: SetupFormState) -> Bool {
        lhs.startDay == rhs.startDay && lhs.startText == rhs.startText && lhs.heightText == rhs.heightText
            && lhs.targetText == rhs.targetText && lhs.startEdited == rhs.startEdited && lhs.targetEdited == rhs.targetEdited
    }

    /// 開始日に終わる7日平均、なければその日までの最新値。
    private static func startText(on day: CalendarDay, weights: [DailyWeight]) -> String? {
        switch HomeModel.startWeightSuggestion(on: day, weights: weights) {
        case .sevenDayAverage(let kg), .latest(let kg): DisplayFormat.kilogramsNumber(kg)
        case .none: nil
        }
    }

    /// 選んだ開始日の開始体重の初期値の出どころ(文言の出し分け用)。
    var startSuggestion: HomeModel.StartWeightSuggestion {
        HomeModel.startWeightSuggestion(on: startDay, weights: weights)
    }

    private static func targetText(heightText: String, settings: PlanSettings) -> String? {
        guard let height = Double(heightText), height.isFinite, height > 0 else { return nil }
        return DisplayFormat.kilogramsNumber(PlanSetup.defaultTargetWeight(heightCentimeters: height, settings: settings))
    }

    /// 開始日を変えたら、範囲に収めてから、開始体重が未編集なら初期値を計算し直す。
    mutating func startDayChanged(_ day: CalendarDay) {
        startDay = min(max(day, earliestStartDay), today)
        if !startEdited, let text = Self.startText(on: startDay, weights: weights) { startText = text }
    }

    mutating func startChanged(_ text: String) {
        startText = text
        startEdited = true
    }

    /// 身長を変えたら、最終目標が未編集なら初期値を計算し直す。
    mutating func heightChanged(_ text: String) {
        heightText = text
        if !targetEdited, let target = Self.targetText(heightText: text, settings: settings) { targetText = target }
    }

    mutating func targetChanged(_ text: String) {
        targetText = text
        targetEdited = true
    }

    var startWeight: Double? { Double(startText) }
    var targetWeight: Double? { Double(targetText) }

    enum Problem: Equatable {
        case notNumber
        case targetNotBelowStart
        case notPositive
    }

    /// 入力の問題。なければ nil(ボタンを有効にする)。
    var problem: Problem? {
        guard let startWeight, let targetWeight else { return .notNumber }
        switch PlanSetup.validate(startWeight: startWeight, targetWeight: targetWeight) {
        case nil: return nil
        case .notFinite: return .notNumber
        case .targetNotBelowStart: return .targetNotBelowStart
        case .startWeightNotPositive, .targetWeightNotPositive: return .notPositive
        }
    }

    var canStart: Bool { problem == nil }

    /// 要約に出す最初の区切り(開始体重 × 0.95、丸め)。入力が有効でなければ nil。
    var firstMilestoneWeight: Double? {
        guard canStart, let startWeight else { return nil }
        return Weight.rounded(startWeight * (1 - settings.firstMilestoneRatio))
    }
}
