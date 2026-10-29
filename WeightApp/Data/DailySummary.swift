import Foundation
import WeightCore

/// 画面が使う、その日のまとめ。WeightCore の判定を順に呼ぶだけで、判断は足さない。
struct DailySummary: Equatable {
    var day: CalendarDay
    var todayWeight: DailyWeight?
    var todayBodyFat: DailyBodyFat?
    var sevenDayAverage: SevenDayAverage?
    /// 計画がなければ nil。
    var plan: PlanStatus?
    /// `day` を含む直近 HomeSettings.historyDays 日(古い順)。取得した範囲より前の日は作らない。
    var history: [DailyPoint]
    /// 取得した範囲にある1日の体重すべて(古い順)。計画がなければ HealthKit の全履歴。初回設定の開始日の範囲と開始体重の初期値に使う。
    var recordedWeights: [DailyWeight]
}

/// 履歴の1日分。グラフ(7日平均の実線、計画の点線)と記録カレンダーが使う。
struct DailyPoint: Equatable {
    var day: CalendarDay
    /// その日の記録。なければ nil(カレンダーの印に使う)。
    var weight: DailyWeight?
    /// その日に終わる窓の7日平均。出なければ nil。
    var sevenDayAverage: Double?
    /// その日の計画値。計画がない、または今のフェーズの起点より前の日は nil(前のフェーズの計画値を今の式で描かないため)。
    var guideline: Double?
}

/// 計画に関する判定のまとめ。
struct PlanStatus: Equatable {
    /// 保存されている計画(自動遷移を反映したあと)。
    var record: PlanRecord
    var roadmap: Roadmap { record.roadmap }
    var phase: PlanPhase { record.phase }
    /// 最初の区切りに到達した日(保存値)。ステージ1で nil なら「最初の区切り」をめざしている表示になる。
    var firstMilestoneReachedOn: CalendarDay? { record.firstMilestoneReachedOn }
    /// 画面に出すステージ番号。フェーズの番号で、体重から逆算しない。維持モードは nil。
    var stageNumber: Int?
    var guideline: Double
    var progress: ProgressJudgment?
    var actualPace: ActualPace?
    var maintenance: MaintenanceState?
    var maintenanceNotice: MaintenanceNotice?
    var earlyArrivalStage: Int?
    var shouldProposeEarlyArrival: Bool
    var shouldProposePlanReview: Bool
}

struct DailySummaryBuilder: Sendable {
    let health: any HealthStore
    let planStore: PlanStore
    let calendar: Calendar
    let settings: PlanSettings

    /// 計画があれば開始日の6日前から、なければ全履歴を取得する(初回設定で最初の記録の日まで開始日を遡れるように。04-screens/03-decisions.md #12)。
    /// 計画があれば、取得のあとに自動遷移(最初の区切り、到達、卒業)を反映して保存し、それを基準に判定する(05-cards/01-design.md 3.)。
    func build(on day: CalendarDay) async throws -> DailySummary {
        let loaded = try planStore.load()
        let firstDay = loaded.map { $0.roadmap.startDay.adding(days: -(SevenDayAverage.windowDays - 1)) }
        let from = firstDay?.startDate(in: calendar) ?? Date.distantPast
        let to = day.adding(days: 1).startDate(in: calendar)

        let weights = DailyWeightResolver.resolve(try await health.weightSamples(from: from, to: to), calendar: calendar)
        let bodyFats = DailyBodyFatResolver.resolve(try await health.bodyFatSamples(from: from, to: to), calendar: calendar)
        let average = SevenDayAverage(endingOn: day, in: weights)
        let record = try loaded.map { try progressed($0, weights: weights, through: day) }

        var summary = DailySummary(
            day: day,
            todayWeight: weights.first { $0.day == day },
            todayBodyFat: bodyFats.first { $0.day == day },
            sevenDayAverage: average,
            plan: nil,
            history: history(from: max(firstDay ?? day.adding(days: -(HomeSettings.historyDays - 1)), day.adding(days: -(HomeSettings.historyDays - 1))),
                             to: day, weights: weights, phase: record?.phase),
            recordedWeights: weights.filter { $0.day <= day }.sorted { $0.day < $1.day }
        )
        if let record {
            summary.plan = planStatus(record: record, on: day, weights: weights, average: average)
        }
        return summary
    }

    /// 自動遷移を反映する。変わっていれば保存する。
    private func progressed(_ record: PlanRecord, weights: [DailyWeight], through day: CalendarDay) throws -> PlanRecord {
        var updated = record
        if updated.firstMilestoneReachedOn == nil,
           let reached = updated.roadmap.firstMilestoneReachedDay(phase: updated.phase, weights: weights, through: day) {
            updated.recordFirstMilestone(on: reached)
        }
        let progression = PhaseProgression.advance(phase: updated.phase, roadmap: updated.roadmap, weights: weights, through: day, settings: settings)
        if !progression.steps.isEmpty { updated.apply(progression) }
        if updated != record { try planStore.save(updated) }
        return updated
    }

    private func history(from: CalendarDay, to: CalendarDay, weights: [DailyWeight], phase: PlanPhase?) -> [DailyPoint] {
        let byDay = Dictionary(weights.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        return SevenDayAverage.series(from: from, to: to, in: weights).map { point in
            var guideline: Double?
            if let phase, point.day >= phase.origin.day {
                guideline = Guideline.expectedWeight(phase: phase, on: point.day, settings: settings)
            }
            return DailyPoint(day: point.day, weight: byDay[point.day], sevenDayAverage: point.average?.kilograms, guideline: guideline)
        }
    }

    private func planStatus(record: PlanRecord, on day: CalendarDay, weights: [DailyWeight], average: SevenDayAverage?) -> PlanStatus {
        let roadmap = record.roadmap
        let phase = record.phase
        let stageNumber: Int?
        switch phase {
        case .losing(let stage, _), .maintaining(let stage, _): stageNumber = stage
        case .maintenanceMode: stageNumber = nil
        }
        var status = PlanStatus(
            record: record,
            stageNumber: stageNumber,
            guideline: Guideline.expectedWeight(phase: phase, on: day, settings: settings),
            progress: nil, actualPace: nil, maintenance: nil, maintenanceNotice: nil,
            earlyArrivalStage: nil, shouldProposeEarlyArrival: false, shouldProposePlanReview: false
        )
        // 当日の7日平均が要るのは進み具合と早期到達だけ。維持期間の判定(85日目のカードを含む)と一言は
        // 到達日からの履歴で決まるので、当日の平均がなくても評価する
        switch phase {
        case .losing:
            if let average {
                status.progress = ProgressJudgment.judge(phase: phase, sevenDayAverage: average.kilograms, on: day, roadmap: roadmap)
            }
            status.actualPace = ActualPace(endingOn: day, phase: phase, weights: weights, roadmap: roadmap)
            status.shouldProposePlanReview = PlanReviewTrigger.shouldPropose(phase: phase, through: day, weights: weights, roadmap: roadmap)
        case .maintaining(_, let arrival):
            status.maintenance = MaintenanceJudgment.evaluate(arrivalDay: arrival.day, arrivalWeight: arrival.weight, through: day, weights: weights, settings: settings)
            status.maintenanceNotice = MaintenanceNoticeJudgment.notice(phase: phase, through: day, weights: weights, settings: settings)
            if let average {
                status.earlyArrivalStage = roadmap.earlyArrival(phase: phase, sevenDayAverage: average.kilograms)
                status.shouldProposeEarlyArrival = EarlyArrivalProposal.shouldPropose(
                    earlyArrivalStage: status.earlyArrivalStage, declinedOn: record.declinedEarlyArrivalOn, today: day, settings: settings)
            }
        case .maintenanceMode:
            status.maintenanceNotice = MaintenanceNoticeJudgment.notice(phase: phase, through: day, weights: weights, settings: settings)
        }
        return status
    }
}
