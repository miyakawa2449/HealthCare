import SwiftUI
import WeightCore

/// 今のステージ。番号は保存したフェーズの番号(体重から逆算しない)。
struct StageCard: View {
    let plan: PlanStatus
    let sevenDayAverage: Double?
    let day: CalendarDay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch plan.phase {
            case .losing(let stage, let origin):
                losing(stage: stage, origin: origin)
            case .maintaining(let stage, let arrival):
                maintaining(stage: stage, arrival: arrival)
            case .maintenanceMode(let arrival):
                maintenanceMode(arrival: arrival)
            }
        }
        .card()
    }

    private func titleRow(_ left: String, _ right: String) -> some View {
        HStack {
            Text(left).font(.headline).foregroundStyle(AppTheme.accent)
            Spacer()
            Text(right).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
        }
    }

    // MARK: 減量中

    @ViewBuilder
    private func losing(stage: Int, origin: StageOrigin) -> some View {
        let roadmap = plan.roadmap
        let aimingFirstMilestone = stage == 1 && plan.firstMilestoneReachedOn == nil
        let stageInfo = roadmap.stages.indices.contains(stage - 1) ? roadmap.stages[stage - 1] : nil
        let target = aimingFirstMilestone ? roadmap.firstMilestoneWeight : stageInfo?.boundaryWeight
        let arrival = aimingFirstMilestone ? roadmap.firstMilestoneEstimatedArrival(from: plan.phase) : stageInfo?.estimatedArrival

        titleRow("ステージ\(stage)", aimingFirstMilestone ? "最初の区切り" : "次の区切り")
        if let target {
            Text("\(DisplayFormat.kilograms(target)) をめざしています")
                .font(.title3.weight(.semibold))
            ProgressBar(fraction: Self.fraction(origin: origin.weight, target: target, current: sevenDayAverage))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(DisplayFormat.kilograms(origin.weight)) からスタート")
                if let arrival {
                    // 何の予定かを言葉で示す(最初の区切り / 次の区切り)。1行に収まるよう別の行にする
                    Text("\(aimingFirstMilestone ? "最初の区切り" : "次の区切り")の到達予定 \(DisplayFormat.approximateDate(arrival))")
                }
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryText)
        }
        if let text = progressText {
            Text(text).font(.subheadline).padding(.top, 4)
        }
    }

    /// (起点 − 7日平均) ÷ (起点 − めざす体重) を 0〜1 に収める。7日平均がなければ 0。起点がめざす体重以下なら 1。
    static func fraction(origin: Double, target: Double, current: Double?) -> Double {
        guard let current else { return 0 }
        let span = origin - target
        guard span > 0 else { return 1 }
        return min(max((origin - current) / span, 0), 1)
    }

    private var progressText: String? {
        switch plan.progress {
        case .settlingIn: "最初の1か月は、体の水分が落ち着く時期です"
        case .onTrack: "計画どおりに進んでいます"
        case .aheadOfSchedule: "予定より少し早いペースです"
        case .slowerPace: "ゆっくりしたペースで進んでいます"
        case nil: nil
        }
    }

    // MARK: 維持期間

    @ViewBuilder
    private func maintaining(stage: Int, arrival: StageOrigin) -> some View {
        titleRow("ステージ\(stage)", "維持期間")
        Text("\(DisplayFormat.kilograms(arrival.weight)) を保つ期間です")
            .font(.title3.weight(.semibold))
        Text("到達から \(arrival.day.days(until: day) + 1)日目")
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryText)
        Text("減らした体重に、体と生活を慣らす時期です")
            .font(.subheadline)
            .padding(.top, 4)
    }

    // MARK: 維持モード

    @ViewBuilder
    private func maintenanceMode(arrival: StageOrigin) -> some View {
        titleRow("維持", "維持モード")
        Text("\(DisplayFormat.kilograms(arrival.weight)) を保っていく時期です")
            .font(.title3.weight(.semibold))
        Text("到達 \(DisplayFormat.fullDate(arrival.day))")
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryText)
    }
}

/// 進み具合のバー。色はアクセントだけ。
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.track)
                Capsule().fill(AppTheme.accent).frame(width: max(geo.size.width * fraction, 10))
            }
        }
        .frame(height: 8)
        // 割合の数値は読み上げない(毎日の画面に出す数値は体重だけ)。進み具合はカードの文言で伝える
        .accessibilityHidden(true)
    }
}
