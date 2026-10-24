/// 進み具合の判定(表示用)。目安と7日平均の差を目安に対する割合で見る。
public enum ProgressJudgment: Sendable, Equatable {
    /// 最初の1か月。水分が抜けて大きく減りやすいので判定しない。
    case settlingIn
    /// 計画どおり(±progressBand 以内)。
    case onTrack
    /// 予定より早いペース(目安より progressBand 超 下回る)。
    case aheadOfSchedule
    /// ゆっくりペース(目安より progressBand 超 上回る)。
    case slowerPace

    public static func judge(sevenDayAverage: Double, guideline: Double, daysElapsed: Int, settings: PlanSettings) -> ProgressJudgment {
        guard daysElapsed >= settings.initialPeriodDays else { return .settlingIn }
        let ratio = Ratio.rounded((sevenDayAverage - guideline) / guideline)
        if abs(ratio) <= settings.progressBand { return .onTrack }
        return ratio < 0 ? .aheadOfSchedule : .slowerPace
    }
}
