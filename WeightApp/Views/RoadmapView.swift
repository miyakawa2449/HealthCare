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

    /// 項目(左)とその日付(右)の組。横に収まらなければ縦に積む(文字サイズが大きいときに左右どちらも折り返さないため)。
    /// 縦に積んだときも項目と日付が隣り合うので、どの予定かが分かる。
    private func pair<L: View, R: View>(@ViewBuilder left: () -> L, @ViewBuilder right: () -> R) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                left()
                Spacer(minLength: 0)
                right()
            }
            VStack(alignment: .leading, spacing: 2) {
                left()
                right()
            }
        }
    }

    /// ステージ同士の区切り(維持期間の下、最終ステージの下)。他の線より太くして見分けやすくする。
    private var stageSeparator: some View {
        Rectangle().fill(AppTheme.accent.opacity(0.35)).frame(height: 2)
    }

    /// ステージのブロック。「ステージn」と状態、開始 → 区切りの体重(今のステージなら到達予定つき)、ステージ1なら最初の区切り。
    @ViewBuilder
    private func stageRows(_ stage: RoadmapRows.StageRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            pair {
                Text("ステージ\(stage.number)")
                    .font(.headline)
                    .foregroundStyle(stage.isCurrent ? AppTheme.accent : .primary)
            } right: {
                Text(statusText(stage.status))
                    .font(.footnote)
                    .foregroundStyle(stage.isCurrent ? AppTheme.accent : AppTheme.secondaryText)
            }
            pair {
                Text("\(DisplayFormat.kilogramsNumber(stage.startWeight)) → \(DisplayFormat.kilograms(stage.boundaryWeight))")
                    .font(.subheadline)
            } right: {
                if case .current(let estimated) = stage.status {
                    Text("到達予定 \(DisplayFormat.approximateDate(estimated))")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            if let milestone = stage.firstMilestone {
                pair {
                    Text("最初の区切り \(DisplayFormat.kilograms(milestone.weight))")
                } right: {
                    if let reached = milestone.reachedOn {
                        Text("届いた \(DisplayFormat.fullDate(reached))")
                    } else if let estimated = milestone.estimatedArrival {
                        Text("到達予定 \(DisplayFormat.approximateDate(estimated))")
                    }
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.leading, 12)
            }
        }
        .padding(.vertical, 10)
        if let maintenance = stage.maintenance {
            Divider()
            maintenanceRow(maintenance)
        }
        stageSeparator
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
        pair {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(current ? AppTheme.accent : AppTheme.secondaryText)
        } right: {
            Text(detail)
                .font(.footnote)
                .foregroundStyle(current ? AppTheme.accent : AppTheme.secondaryText)
        }
        .padding(.vertical, 8)
        .padding(.leading, 12)
    }

    /// 最終目標。見出しと到達予定を1行目に、体重を2行目に(体重が折り返さないように)。
    private var targetRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            pair {
                Text("最終目標").font(.headline)
            } right: {
                Text(statusText(rows.target.status))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Text(DisplayFormat.kilograms(rows.target.weight)).font(.subheadline)
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
