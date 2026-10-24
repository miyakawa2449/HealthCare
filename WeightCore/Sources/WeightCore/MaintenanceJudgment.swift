/// 維持期間の状態。
public enum MaintenanceState: Sendable, Equatable {
    /// 維持中。範囲内に収まっている連続日数つき。
    case inProgress(consecutiveDaysInBand: Int)
    /// 卒業(範囲内が maintenanceMinDays 連続した最初の日)。
    case graduated(on: CalendarDay)
    /// maintenanceMaxDays を超えても卒業していない。カードで「次へ進む/維持を続ける」を提案する。
    case exceededMaximum(consecutiveDaysInBand: Int)
}

/// 維持期間の卒業判定。
public enum MaintenanceJudgment {
    /// 到達日から `day` まで1日ずつ、7日平均(丸め済み)が到達時体重の ±maintenanceBand 以内かを数える。
    /// 範囲外の日と7日平均が出ない日でカウントを 0 に戻す。
    ///
    /// 卒業は、到達日から `maintenanceMaxDays`(84日)以内に `maintenanceMinDays`(28日)連続を満たした場合だけ。
    /// 84日以内に卒業しなければ、その後に28日連続を満たしても自動では卒業せず `exceededMaximum` のまま
    /// (次へ進むか維持を続けるかはユーザーが選ぶ)。連続日数はカードの表示用に数え続ける。
    public static func evaluate(arrivalDay: CalendarDay, arrivalWeight: Double, through day: CalendarDay,
                                weights: [DailyWeight], settings: PlanSettings) -> MaintenanceState {
        var streak = 0
        var cursor = arrivalDay
        while cursor <= day {
            if let avg = SevenDayAverage(endingOn: cursor, in: weights), isInBand(avg.kilograms, around: arrivalWeight, settings: settings) {
                streak += 1
                if streak >= settings.maintenanceMinDays, arrivalDay.days(until: cursor) <= settings.maintenanceMaxDays {
                    return .graduated(on: cursor)
                }
            } else {
                streak = 0
            }
            cursor = cursor.adding(days: 1)
        }
        if arrivalDay.days(until: day) > settings.maintenanceMaxDays {
            return .exceededMaximum(consecutiveDaysInBand: streak)
        }
        return .inProgress(consecutiveDaysInBand: streak)
    }

    private static func isInBand(_ average: Double, around arrivalWeight: Double, settings: PlanSettings) -> Bool {
        let diff = abs(Weight.rounded(average) - arrivalWeight)
        return Ratio.rounded(diff / arrivalWeight) <= settings.maintenanceBand
    }
}
