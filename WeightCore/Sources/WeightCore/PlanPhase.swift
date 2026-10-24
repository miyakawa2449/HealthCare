/// 減量ステージや維持期間の起点(その日の7日平均を 0.1kg に丸めた体重と、その日付)。
public struct StageOrigin: Sendable, Equatable, Codable {
    /// 0.1kg に丸めた体重。
    public var weight: Double
    public var day: CalendarDay

    public init(weight: Double, day: CalendarDay) {
        self.weight = Weight.rounded(weight)
        self.day = day
    }
}

/// いま計画のどこにいるか。アプリが保存し、判定はすべてこれを基準にする。
///
/// 計画値(目安)はこのフェーズに従う: 減量中はそのステージの起点から月2%で日割り、
/// 維持中と維持モードは到達時の体重で一定。進み具合・実績ペース・計画見直しは減量中だけ判定する。
public enum PlanPhase: Sendable, Equatable, Codable {
    /// 減量中。`origin` はステージ開始時(ステージ1なら計画の開始、以降は次のステージへ進んだ日)の7日平均と日付。
    case losing(stage: Int, origin: StageOrigin)
    /// 維持期間。`arrival` は到達日の7日平均と日付。
    case maintaining(stage: Int, arrival: StageOrigin)
    /// 最終目標の後の、終わりのない維持モード。
    case maintenanceMode(arrival: StageOrigin)

    /// 減量中のステージ番号。減量中でなければ nil。
    public var losingStage: Int? {
        if case .losing(let stage, _) = self { return stage }
        return nil
    }

    /// 起点(減量中はステージの起点、それ以外は到達時)。
    public var origin: StageOrigin {
        switch self {
        case .losing(_, let origin): return origin
        case .maintaining(_, let arrival), .maintenanceMode(let arrival): return arrival
        }
    }

    /// 計画見直しを採用したときの起点の取り直し。減量中だけ。境界は変えない。
    public func rebased(sevenDayAverage: Double, on day: CalendarDay) -> PlanPhase? {
        guard case .losing(let stage, _) = self else { return nil }
        return .losing(stage: stage, origin: StageOrigin(weight: sevenDayAverage, day: day))
    }
}
