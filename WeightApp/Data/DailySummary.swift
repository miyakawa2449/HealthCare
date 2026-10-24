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
}

/// 計画に関する判定のまとめ。
struct PlanStatus: Equatable {
    var phase: PlanPhase
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

    /// 計画がなければ当日を含む直近30日、あれば開始日の6日前から取得する(03-decisions.md #8)。
    static let daysWithoutPlan = 30

    func build(on day: CalendarDay) async throws -> DailySummary {
        let record = try planStore.load()
        let firstDay = record.map { $0.roadmap.startDay.adding(days: -(SevenDayAverage.windowDays - 1)) }
            ?? day.adding(days: -(Self.daysWithoutPlan - 1))
        let from = firstDay.startDate(in: calendar)
        let to = day.adding(days: 1).startDate(in: calendar)

        let weights = DailyWeightResolver.resolve(try await health.weightSamples(from: from, to: to), calendar: calendar)
        let bodyFats = DailyBodyFatResolver.resolve(try await health.bodyFatSamples(from: from, to: to), calendar: calendar)
        let average = SevenDayAverage(endingOn: day, in: weights)

        var summary = DailySummary(
            day: day,
            todayWeight: weights.first { $0.day == day },
            todayBodyFat: bodyFats.first { $0.day == day },
            sevenDayAverage: average,
            plan: nil
        )
        if let record {
            summary.plan = planStatus(record: record, on: day, weights: weights, average: average)
        }
        return summary
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
            phase: phase,
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
