/// 体組成の代表値(期間の最終日に終わる7日間の平均)。
public struct CompositionSnapshot: Sendable, Equatable {
    /// 体脂肪率(0.0〜1.0)。窓にある体脂肪率の平均。
    public var bodyFat: Double?
    /// 除脂肪量(kg)。窓の中で体重と体脂肪率の両方がある日の平均。
    public var leanMass: Double?
    /// 除脂肪量と同じ日の体重の平均(脂肪の割合の一言に使う)。
    public var weight: Double?
    /// 除脂肪量と同じ日の脂肪量(体重 × 体脂肪率)の平均。
    public var fatMass: Double?
    /// 体重と体脂肪率の両方がある日の数。
    public var pairedDays: Int

    public init(bodyFat: Double?, leanMass: Double?, weight: Double?, fatMass: Double?, pairedDays: Int) {
        self.bodyFat = bodyFat
        self.leanMass = leanMass
        self.weight = weight
        self.fatMass = fatMass
        self.pairedDays = pairedDays
    }
}

/// 体組成の変化の方向。差を表示の単位に丸めてから、横ばいの幅と比べる(ちょうどは横ばい)。
public enum CompositionDirection: Sendable, Equatable {
    case down, flat, up

    /// 体脂肪率(割合)の方向。ポイント(0.1)に丸めて比べる。
    public static func bodyFat(from: Double, to: Double, settings: ReportSettings) -> CompositionDirection {
        direction(diff: Weight.rounded(to * 100) - Weight.rounded(from * 100), band: settings.bodyFatFlatBandPoints)
    }

    /// 除脂肪量(kg)の方向。0.1kg に丸めて比べる。
    public static func leanMass(from: Double, to: Double, settings: ReportSettings) -> CompositionDirection {
        direction(diff: Weight.rounded(to) - Weight.rounded(from), band: settings.leanMassFlatBandKilograms)
    }

    private static func direction(diff: Double, band: Double) -> CompositionDirection {
        // 丸めた値同士の差に残る浮動小数点の誤差を、もう一度 0.1 単位に丸めて消す
        let d = Weight.rounded(diff)
        if abs(d) <= band { return .flat }
        return d < 0 ? .down : .up
    }
}

/// 除脂肪量の計算と代表値。
public enum BodyComposition {
    /// 除脂肪量 = 体重 × (1 − 体脂肪率)。
    public static func leanMass(weight: Double, bodyFat: Double) -> Double {
        weight * (1 - bodyFat)
    }

    /// `day` に終わる7日間の代表値。体脂肪率だけの日は体脂肪率の平均に入れ、除脂肪量には入れない。
    public static func snapshot(endingOn day: CalendarDay, weights: [DailyWeight], bodyFats: [DailyBodyFat]) -> CompositionSnapshot {
        let first = day.adding(days: -(SevenDayAverage.windowDays - 1))
        let fats = bodyFats.filter { $0.day >= first && $0.day <= day }
        let weightByDay = Dictionary(weights.filter { $0.day >= first && $0.day <= day }.map { ($0.day, $0.kilograms) },
                                     uniquingKeysWith: { a, _ in a })
        let pairs = fats.compactMap { f in weightByDay[f.day].map { (weight: $0, fat: f.fraction) } }
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        return CompositionSnapshot(
            bodyFat: mean(fats.map(\.fraction)),
            leanMass: mean(pairs.map { leanMass(weight: $0.weight, bodyFat: $0.fat) }),
            weight: mean(pairs.map(\.weight)),
            fatMass: mean(pairs.map { $0.weight * $0.fat }),
            pairedDays: pairs.count
        )
    }

    /// 体重が減り、減った分のうち脂肪量の減少が `fatShareNoteThreshold`(半分)以上なら true。
    public static func mostlyFatLost(from base: CompositionSnapshot, to current: CompositionSnapshot, settings: ReportSettings) -> Bool {
        guard let w0 = base.weight, let w1 = current.weight, let f0 = base.fatMass, let f1 = current.fatMass else { return false }
        let weightLoss = w0 - w1
        guard Weight.rounded(weightLoss) > 0 else { return false }
        return Ratio.rounded((f0 - f1) / weightLoss) >= settings.fatShareNoteThreshold
    }
}
