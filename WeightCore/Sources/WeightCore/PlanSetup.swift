/// 初回設定で使う純粋なロジック。最終目標の初期値と、入力の検証。
public enum PlanSetup {
    /// 身長の初期値(cm)。最終目標の初期値を決めるためだけに使い、保存しない。
    public static let defaultHeightCentimeters = 175.0

    /// 最終目標の初期値 = 設定の BMI × 身長(m)²。丸めない(`Roadmap` が 0.1kg に丸める)。
    public static func defaultTargetWeight(heightCentimeters: Double, settings: PlanSettings) -> Double {
        let meters = heightCentimeters / 100
        return settings.defaultTargetBMI * meters * meters
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case startWeightNotPositive
        case targetWeightNotPositive
        case targetNotBelowStart
    }

    /// 開始体重と最終目標が正の数で、最終目標が開始体重より小さければ nil。
    public static func validate(startWeight: Double, targetWeight: Double) -> ValidationError? {
        guard startWeight > 0 else { return .startWeightNotPositive }
        guard targetWeight > 0 else { return .targetWeightNotPositive }
        guard targetWeight < startWeight else { return .targetNotBelowStart }
        return nil
    }
}
