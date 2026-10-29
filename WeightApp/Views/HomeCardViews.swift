import SwiftUI
import WeightCore

/// ホームのカード(05-cards/04-wording.md)。色はアクセントだけ。評価ラベルは出さない。
struct HomeCardView: View {
    let card: HomeCard
    let perform: (CardAction) async -> Void

    var body: some View {
        switch card {
        case .event(let event):
            EventCard(event: event) { await perform(.dismiss(event.id)) }
        case .maintenanceMaximum(let canAdvance):
            ProposalCard(
                title: "維持期間が12週間を超えました",
                text: canAdvance ? "どちらを選んでも、ここまで保てたことが成果です。" : "今日の記録が入ってから選べます。",
                primary: .init(title: "次のステージへ進む", enabled: canAdvance) { await perform(.advanceAfterMaximum) },
                secondary: .init(title: "維持を続ける") { await perform(.continueMaintenance) })
        case .earlyArrival(_, let boundary):
            ProposalCard(
                title: "維持期間のあいだに、次の区切り \(DisplayFormat.kilograms(boundary)) まで減りました",
                text: "次のステージの到達として扱うと、ここから新しい維持期間が始まります。",
                primary: .init(title: "次のステージの到達として扱う") { await perform(.adoptEarlyArrival) },
                secondary: .init(title: "維持を続ける") { await perform(.declineEarlyArrival) })
        case .planReview(_, let before, let after):
            ProposalCard(
                title: "最近のペースに合わせて、計画を見直せます",
                text: "今のステージの到達予定: \(DisplayFormat.approximateDate(before)) → \(DisplayFormat.approximateDate(after))。区切りの体重は変わりません。",
                primary: .init(title: "この計画で進める") { await perform(.adoptPlanReview) },
                secondary: .init(title: "元の計画のままにする") { await perform(.declinePlanReview) })
        case .tooFast:
            NoticeCard(text: "最近のペースは、目安よりかなり速めです。目標はそのままに、少しゆるめても大丈夫です。")
        case .maintenanceNotice(let notice):
            switch notice {
            case .aboveBand:
                NoticeCard(text: "維持の範囲から少し上に離れています。日々の上下は気にせず、いつもの生活のリズムに戻していきましょう。")
            case .belowBand:
                NoticeCard(text: "維持の範囲から少し下に離れています。減らしすぎていないか、食事の量を見直してみてください。")
            }
        }
    }
}

/// 出来事(閉じるまで残る)。
struct EventCard: View {
    let event: PlanEvent
    let onDismiss: () async -> Void
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .font(.subheadline)
            Text(DisplayFormat.fullDate(event.day))
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
            Button("閉じる") {
                Task { isWorking = true; await onDismiss(); isWorking = false }
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.accent)
            .disabled(isWorking)
            .padding(.top, 4)
        }
        .card()
    }

    private var title: String {
        switch event.kind {
        case .firstMilestoneReached(let weight, _): "最初の区切り \(DisplayFormat.kilograms(weight)) に届きました"
        case .stageArrived(let stage, let weight): "ステージ\(stage)の区切り \(DisplayFormat.kilograms(weight)) に届きました"
        case .graduated(let toStage, _, _): "維持期間を終えて、ステージ\(toStage)に進みました"
        case .targetReached(let weight): "最終目標 \(DisplayFormat.kilograms(weight)) に届きました"
        }
    }

    private var text: String {
        switch event.kind {
        case .firstMilestoneReached(_, let next): "ここまで続いたことが成果です。次は \(DisplayFormat.kilograms(next)) をめざします。"
        case .stageArrived: "ここから維持期間に入ります。減らした体重に、体と生活を慣らす時期です。"
        case .graduated(_, let kept, let next): "\(DisplayFormat.kilograms(kept)) を保てました。ここから \(DisplayFormat.kilograms(next)) をめざします。"
        case .targetReached: "ここからは維持モードです。この体重に体と生活を慣らしていきます。"
        }
    }
}

/// 提案(ボタン2つ)。主ボタンはアクセント塗り、副ボタンは枠だけ。
struct ProposalCard: View {
    struct Choice {
        var title: String
        var enabled = true
        var action: () async -> Void
    }

    let title: String
    let text: String
    let primary: Choice
    let secondary: Choice
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .font(.subheadline)
            VStack(spacing: 8) {
                Button {
                    run(primary.action)
                } label: {
                    Text(primary.title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!primary.enabled || isWorking)

                Button {
                    run(secondary.action)
                } label: {
                    Text(secondary.title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(!secondary.enabled || isWorking)
            }
            .tint(AppTheme.accent)
            .padding(.top, 4)
        }
        .card()
    }

    private func run(_ action: @escaping () async -> Void) {
        Task { isWorking = true; await action(); isWorking = false }
    }
}

/// 一言(ボタンなし)。
struct NoticeCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .card()
    }
}

// MARK: - Preview

private let previewDay = CalendarDay(year: 2027, month: 3, day: 23)

#Preview("出来事: 最初の区切り") {
    EventCard(event: PlanEvent(kind: .firstMilestoneReached(weight: 117.3, nextBoundary: 111.2), day: previewDay)) {}
        .padding().background(AppTheme.background)
}

#Preview("出来事: ステージ到達") {
    EventCard(event: PlanEvent(kind: .stageArrived(stage: 1, weight: 111.2), day: previewDay)) {}
        .padding().background(AppTheme.background)
}

#Preview("出来事: 卒業") {
    EventCard(event: PlanEvent(kind: .graduated(toStage: 2, keptWeight: 111.2, nextBoundary: 100.0), day: previewDay)) {}
        .padding().background(AppTheme.background)
}

#Preview("出来事: 最終目標") {
    EventCard(event: PlanEvent(kind: .targetReached(weight: 67.4), day: previewDay)) {}
        .padding().background(AppTheme.background)
}

#Preview("提案: 85日目(選べる)") {
    HomeCardView(card: .maintenanceMaximum(canAdvance: true)) { _ in }
        .padding().background(AppTheme.background)
}

#Preview("提案: 85日目(今日の記録なし)") {
    HomeCardView(card: .maintenanceMaximum(canAdvance: false)) { _ in }
        .padding().background(AppTheme.background)
}

#Preview("提案: 早期到達") {
    HomeCardView(card: .earlyArrival(nextStage: 2, boundary: 100.0)) { _ in }
        .padding().background(AppTheme.background)
}

#Preview("提案: 計画見直し") {
    HomeCardView(card: .planReview(stage: 1, before: CalendarDay(year: 2027, month: 3, day: 23), after: CalendarDay(year: 2027, month: 5, day: 8))) { _ in }
        .padding().background(AppTheme.background)
}

#Preview("一言: 速すぎるペース") {
    HomeCardView(card: .tooFast) { _ in }
        .padding().background(AppTheme.background)
}

#Preview("一言: 維持の範囲から上") {
    HomeCardView(card: .maintenanceNotice(.aboveBand(consecutiveDays: 14))) { _ in }
        .padding().background(AppTheme.background)
}

#Preview("一言: 維持の範囲から下") {
    HomeCardView(card: .maintenanceNotice(.belowBand(consecutiveDays: 14))) { _ in }
        .padding().background(AppTheme.background)
}
