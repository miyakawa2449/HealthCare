/// 進み具合の判定(表示用)。目安と7日平均の差を目安に対する割合で見る。
public enum ProgressJudgment: Sendable, Equatable {
    /// 最初の1か月(ステージ1の起点から initialPeriodDays 未満)。水分が抜けて大きく減りやすいので判定しない。
    case settlingIn
    /// 計画どおり(±progressBand 以内)。
    case onTrack
    /// 予定より早いペース(目安より progressBand 超 下回る)。
    case aheadOfSchedule
    /// ゆっくりペース(目安より progressBand 超 上回る)。
    case slowerPace

    /// フェーズに従って判定する。減量中でなければ nil(維持中は MaintenanceJudgment が代わり)。
    /// 最初の1か月の除外は計画の開始(ステージ1)にだけ適用し、ステージ2以降は起点の日から判定する。
    public static func judge(phase: PlanPhase, sevenDayAverage: Double, on day: CalendarDay, settings: PlanSettings) -> ProgressJudgment? {
        guard case .losing(let stage, let origin) = phase else { return nil }
        if stage == 1, origin.day.days(until: day) < settings.initialPeriodDays { return .settlingIn }
        let guideline = Guideline.expectedWeight(phase: phase, on: day, settings: settings)
        return judge(sevenDayAverage: sevenDayAverage, guideline: guideline, settings: settings)
    }

    /// 目安との差の割合(分母は目安)を丸めてから ±progressBand と比べる。
    public static func judge(sevenDayAverage: Double, guideline: Double, settings: PlanSettings) -> ProgressJudgment {
        let ratio = Ratio.rounded((sevenDayAverage - guideline) / guideline)
        if abs(ratio) <= settings.progressBand { return .onTrack }
        return ratio < 0 ? .aheadOfSchedule : .slowerPace
    }
}
