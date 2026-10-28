import Foundation
import WeightCore

/// 初回設定の入力欄の状態。View から切り離してテストする。
struct SetupFormState: Equatable {
    var startText: String
    var heightText: String
    var targetText: String
    /// 最終目標を手で直した。以後は身長を変えても上書きしない。
    private(set) var targetEdited = false

    private let settings: PlanSettings

    init(suggestedStartWeight: Double?, settings: PlanSettings = .default) {
        self.settings = settings
        startText = suggestedStartWeight.map(DisplayFormat.kilogramsNumber) ?? ""
        heightText = String(Int(PlanSetup.defaultHeightCentimeters))
        targetText = Self.targetText(heightText: heightText, settings: settings) ?? ""
    }

    static func == (lhs: SetupFormState, rhs: SetupFormState) -> Bool {
        lhs.startText == rhs.startText && lhs.heightText == rhs.heightText && lhs.targetText == rhs.targetText && lhs.targetEdited == rhs.targetEdited
    }

    private static func targetText(heightText: String, settings: PlanSettings) -> String? {
        guard let height = Double(heightText), height.isFinite, height > 0 else { return nil }
        return DisplayFormat.kilogramsNumber(PlanSetup.defaultTargetWeight(heightCentimeters: height, settings: settings))
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
