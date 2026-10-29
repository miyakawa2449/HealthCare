import SwiftUI
import WeightCore

/// `HomeModel` を見て `RoadmapView` に渡す薄い層。
struct RoadmapScreen: View {
    let model: HomeModel

    var body: some View {
        if let summary = model.summary, let plan = summary.plan {
            RoadmapView(rows: RoadmapRows.make(record: plan.record, on: summary.day)) {
                do {
                    try await model.revertToOriginalPlan()
                } catch {
                    await model.refresh()
                }
            }
        } else {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ProgressView()
            }
        }
    }
}

/// ロードマップ画面(05-cards/01-design.md 6.)。最終目標はこの画面にだけ出す。評価ラベルは出さない。
struct RoadmapView: View {
    let rows: RoadmapRows
    var revert: () async -> Void = {}
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("ロードマップ")
                    .font(.largeTitle.bold())
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 6) {
                    Text("計画のペース").font(.headline).foregroundStyle(AppTheme.accent)
                    Text(rows.paceText).font(.subheadline)
                }
                .card()

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.stages) { stage in
                        stageRows(stage)
                    }
                    targetRow
                    if let day = rows.maintenanceMode {
                        subRow(label: "維持モード", detail: "到達 \(DisplayFormat.fullDate(day))", current: true)
                    }
                }
                .card()

                if let revert = rows.revert {
                    revertCard(revert)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background.ignoresSafeArea())
    }

    // MARK: 行

    /// ステージの行。1行目: 「ステージn」と状態(いまここ / 到達 / 到達予定)、2行目: 開始 → 区切りの体重と、今のステージなら到達予定。
    /// 「ステージn」と状態は折り返さない(fixedSize)。
    @ViewBuilder
    private func stageRows(_ stage: RoadmapRows.StageRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("ステージ\(stage.number)")
                    .font(.headline)
                    .foregroundStyle(stage.isCurrent ? AppTheme.accent : .primary)
                    .fixedSize()
                Spacer(minLength: 8)
                Text(statusText(stage.status))
                    .font(.footnote)
                    .foregroundStyle(stage.isCurrent ? AppTheme.accent : AppTheme.secondaryText)
                    .fixedSize()
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(DisplayFormat.kilogramsNumber(stage.startWeight)) → \(DisplayFormat.kilograms(stage.boundaryWeight))")
                    .font(.subheadline)
                Spacer(minLength: 8)
                if case .current(let estimated) = stage.status {
                    Text("到達予定 \(DisplayFormat.approximateDate(estimated))")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize()
                }
            }
            if let milestone = stage.firstMilestone {
                HStack(alignment: .firstTextBaseline) {
                    Text("最初の区切り \(DisplayFormat.kilograms(milestone.weight))")
                    Spacer(minLength: 8)
                    if let reached = milestone.reachedOn {
                        Text("届いた \(DisplayFormat.fullDate(reached))").fixedSize()
                    } else if let estimated = milestone.estimatedArrival {
                        Text("到達予定 \(DisplayFormat.approximateDate(estimated))").fixedSize()
                    }
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.leading, 12)
            }
        }
        .padding(.vertical, 10)
        Divider()
        if let maintenance = stage.maintenance {
            maintenanceRow(maintenance)
            Divider()
        }
    }

    private func maintenanceRow(_ status: RoadmapRows.MaintenanceStatus) -> some View {
        let detail: String
        var current = false
        switch status {
        case .upcoming: detail = "約2か月"
        case .current(let n): detail = "いまここ(到達から \(n)日目)"; current = true
        case .ended(let day): detail = day.map { "終了 \(DisplayFormat.fullDate($0))" } ?? "終了"
        }
        return subRow(label: "維持期間", detail: detail, current: current)
    }

    private func subRow(label: String, detail: String, current: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(current ? AppTheme.accent : AppTheme.secondaryText)
                .fixedSize()
            Spacer(minLength: 8)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(current ? AppTheme.accent : AppTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
        .padding(.leading, 12)
    }

    private var targetRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("最終目標").font(.headline).fixedSize()
            Text(DisplayFormat.kilograms(rows.target.weight)).font(.subheadline)
            Spacer(minLength: 8)
            Text(statusText(rows.target.status))
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize()
        }
        .padding(.vertical, 10)
    }

    private func statusText(_ status: RoadmapRows.StageStatus) -> String {
        switch status {
        case .arrived(let day): "到達 \(DisplayFormat.fullDate(day))"
        case .current: "いまここ"
        case .estimated(let day): "到達予定 \(DisplayFormat.approximateDate(day))"
        }
    }

    private func revertCard(_ revert: RoadmapRows.Revert) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("見直し前の計画に戻します。今のステージの到達予定: \(DisplayFormat.approximateDate(revert.current)) → \(DisplayFormat.approximateDate(revert.original))。")
                .font(.subheadline)
            Button {
                Task { isWorking = true; await self.revert(); isWorking = false }
            } label: {
                Text("元の計画に戻す").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.accent)
            .disabled(isWorking)
        }
        .card()
    }
}

#Preview("ステージ1の減量中") {
    RoadmapScreen(model: PreviewData.homeModel(.onTrack))
}

#Preview("ステージ1の維持期間") {
    RoadmapScreen(model: PreviewData.homeModel(.maintaining))
}

#Preview("ステージ3の減量中") {
    RoadmapScreen(model: PreviewData.homeModel(.stage3))
}

#Preview("維持モード") {
    RoadmapScreen(model: PreviewData.homeModel(.maintenanceMode))
}

#Preview("見直し採用後") {
    RoadmapScreen(model: PreviewData.homeModel(.afterReview))
}
