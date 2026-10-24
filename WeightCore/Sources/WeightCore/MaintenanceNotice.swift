/// 維持中(維持期間・維持モード)に、7日平均が範囲外に続いているときの一言。
public enum MaintenanceNotice: Sendable, Equatable {
    /// 到達時体重の +maintenanceBand より上に、この日数連続で外れている。
    case aboveBand(consecutiveDays: Int)
    /// 到達時体重の −maintenanceBand より下に、この日数連続で外れている。
    case belowBand(consecutiveDays: Int)
}

/// 維持中の一言の判定。
public enum MaintenanceNoticeJudgment {
    /// 到達日から `day` まで1日ずつ、7日平均(丸め)が到達時体重の ±maintenanceBand の外にある連続日数を数え、
    /// `maintenanceNoticeDays`(14)以上なら返す。範囲内の日、7日平均が出ない日、上下が入れ替わった日で数え直す。
    /// 減量中は nil。85日目の提案カード(`MaintenanceState.exceededMaximum`)との優先は表示側で決める。
    public static func notice(phase: PlanPhase, through day: CalendarDay, weights: [DailyWeight], settings: PlanSettings) -> MaintenanceNotice? {
        let arrival: StageOrigin
        switch phase {
        case .maintaining(_, let a), .maintenanceMode(let a): arrival = a
        case .losing: return nil
        }
        var current: MaintenanceNotice?
        var cursor = arrival.day
        while cursor <= day {
            let next: MaintenanceNotice?
            if let avg = SevenDayAverage(endingOn: cursor, in: weights) {
                let ratio = Ratio.rounded((Weight.rounded(avg.kilograms) - arrival.weight) / arrival.weight)
                if ratio > settings.maintenanceBand {
                    if case .aboveBand(let n) = current { next = .aboveBand(consecutiveDays: n + 1) } else { next = .aboveBand(consecutiveDays: 1) }
                } else if ratio < -settings.maintenanceBand {
                    if case .belowBand(let n) = current { next = .belowBand(consecutiveDays: n + 1) } else { next = .belowBand(consecutiveDays: 1) }
                } else {
                    next = nil
                }
            } else {
                next = nil
            }
            current = next
            cursor = cursor.adding(days: 1)
        }
        switch current {
        case .aboveBand(let n) where n >= settings.maintenanceNoticeDays, .belowBand(let n) where n >= settings.maintenanceNoticeDays:
            return current
        default:
            return nil
        }
    }
}

/// 早期到達の提案を出すかどうか(断った日からの再提案)。
public enum EarlyArrivalProposal {
    /// 早期到達があり、断っていないか、断った日から `earlyArrivalRetryDays`(14)以上たっていれば true。
    /// 85日目の提案カードと重なったらカードを優先する(表示側)。
    public static func shouldPropose(earlyArrivalStage: Int?, declinedOn: CalendarDay?, today: CalendarDay, settings: PlanSettings) -> Bool {
        guard earlyArrivalStage != nil else { return false }
        guard let declinedOn else { return true }
        return declinedOn.days(until: today) >= settings.earlyArrivalRetryDays
    }
}
