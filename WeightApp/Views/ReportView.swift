import SwiftUI
import WeightCore

/// レポートタブ。最新のレポートを出し、前後のレポートへ移れる。開いたレポートを既読にする。
struct ReportScreen: View {
    let model: HomeModel
    @State private var selectedID: String?

    var body: some View {
        if let summary = model.summary {
            let reports = summary.reports
            if let current = reports.first(where: { $0.id == selectedID }) ?? reports.last {
                let index = reports.firstIndex(of: current) ?? reports.count - 1
                ReportView(
                    report: current,
                    planReviewCard: current.isLatest ? model.cards.first { if case .planReview = $0 { true } else { false } } : nil,
                    previous: index > 0 ? { selectedID = reports[index - 1].id } : nil,
                    next: index < reports.count - 1 ? { selectedID = reports[index + 1].id } : nil
                ) { action in
                    do { try await model.perform(action) } catch { await model.refresh() }
                }
                .onAppear { model.markReportOpened(current.id) }
                .onChange(of: current.id) { _, id in model.markReportOpened(id) }
            } else {
                NoReportView(next: summary.nextReport)
            }
        } else {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ProgressView()
            }
        }
    }
}

/// 公開済みのレポートがまだないとき。
struct NoReportView: View {
    let next: ReportPeriod?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            if let next {
                Text("最初のレポートは \(DisplayFormat.dayWithWeekday(next.releaseDay)) に届きます。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(32)
            }
        }
    }
}

/// レポート1件(デザイン2・3枚目)。体組成の数値は月末だけ(`CompositionSection` が月半ばでは数値を持たない)。
/// 色はアクセントと灰色だけで、「上がった」も同じ色にする。
struct ReportView: View {
    let report: ReportContent
    /// 最新のレポートで、ホームに計画見直しのカードが出ているときだけ渡す。
    var planReviewCard: HomeCard?
    var previous: (() -> Void)?
    var next: (() -> Void)?
    var perform: (CardAction) async -> Void = { _ in }

    private var period: ReportPeriod { report.period }

    var body: some View {
        ScrollView {
            content
        }
        .background(AppTheme.background.ignoresSafeArea())
    }

    /// スクロールの中身(画像への書き出しでも使う)。
    var content: some View {
            VStack(alignment: .leading, spacing: 16) {
                header
                switch period.kind {
                case .midMonth:
                    continuityCard
                    weightFlowCard
                    compositionCard
                    midStageCard
                case .monthEnd:
                    monthEndSummaryCard
                    compositionCard
                    monthEndStageCard
                    paceCard
                }
                if let planReviewCard {
                    HomeCardView(card: planReviewCard, perform: perform)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
    }

    // MARK: 見出し

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ReportWording.range(period))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                if previous != nil || next != nil {
                    Button { previous?() } label: { Image(systemName: "chevron.left") }
                        .disabled(previous == nil)
                        .accessibilityLabel("前のレポート")
                    Button { next?() } label: { Image(systemName: "chevron.right") }
                        .disabled(next == nil)
                        .accessibilityLabel("次のレポート")
                        .padding(.leading, 12)
                }
            }
            .tint(AppTheme.accent)
            Text(ReportWording.title(period))
                .font(.largeTitle.bold())
        }
        .padding(.top, 16)
    }

    // MARK: 記録できた日

    private var continuityCount: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("記録できた日").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(report.continuity.recordedDays)").font(.system(size: 40, weight: .bold, design: .rounded))
                Text("日 / \(report.continuity.totalDays)日").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var continuityMarks: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 15), spacing: 4) {
            ForEach(report.continuity.marks, id: \.day) { mark in
                RoundedRectangle(cornerRadius: 3)
                    .fill(mark.recorded ? AppTheme.accent : AppTheme.track)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
    }

    private var continuityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            continuityCount
            continuityMarks
            Text(ReportWording.continuity(report.continuity, period: period)).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: 体重(月半ば)

    private var weightFlowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("体重の流れ(7日平均)").font(.headline)
            if let end = report.weight.endAverage {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let base = report.weight.baseline {
                        Text(DisplayFormat.kilogramsNumber(base.weight)).font(.title).foregroundStyle(AppTheme.secondaryText)
                        Image(systemName: "arrow.right").foregroundStyle(AppTheme.secondaryText)
                    }
                    Text(DisplayFormat.kilogramsNumber(end)).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("kg").foregroundStyle(AppTheme.secondaryText)
                }
            }
            planBox(guidelineLabel: "\(period.lastDay.day)日の目安", showsActual: true)
            planText
            changesList
        }
        .card()
    }

    // MARK: 記録と体重(月末)

    private var monthEndSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) {
                    continuityCount
                    Spacer()
                    monthEndWeight
                }
                VStack(alignment: .leading, spacing: 12) {
                    continuityCount
                    monthEndWeight
                }
            }
            continuityMarks
            Text(ReportWording.continuity(report.continuity, period: period)).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            planBox(guidelineLabel: "月末の目安", showsActual: false)
            planText
            changesList
        }
        .card()
    }

    private var monthEndWeight: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("体重(7日平均)").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            if let end = report.weight.endAverage {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(DisplayFormat.kilogramsNumber(end)).font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("kg").foregroundStyle(AppTheme.secondaryText)
                }
                if let base = report.weight.baseline, let change = report.weight.change {
                    Text("\(baselineName(base)) \(DisplayFormat.kilograms(base.weight)) から \(ReportWording.signedKilograms(change))")
                        .font(.footnote).foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                Text("—").font(.title)
            }
        }
    }

    private func baselineName(_ base: WeightFlow.Baseline) -> String {
        switch base {
        case .previousMonthEnd(let day, _): "\(day.month)月末"
        case .planStart: "開始時"
        }
    }

    // MARK: 目安と進み具合(共通)

    /// 目安と実際、または維持の範囲。最初の1か月と7日平均が出ないときは出さない。
    @ViewBuilder
    private func planBox(guidelineLabel: String, showsActual: Bool) -> some View {
        switch report.standing {
        case .losing(_, let guideline, let progress)? where progress != nil && progress != .settlingIn:
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                labeled(guidelineLabel, "\(DisplayFormat.kilograms(guideline)) 前後")
                if showsActual, let end = report.weight.endAverage {
                    labeled("実際", DisplayFormat.kilograms(end))
                }
            }
            .infoBox()
        case .maintaining(_, _, let lower, let upper, _)?:
            labeled("維持の範囲", "\(DisplayFormat.kilogramsNumber(lower))〜\(DisplayFormat.kilograms(upper))")
                .infoBox()
        default:
            EmptyView()
        }
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text(value).font(.headline)
        }
    }

    @ViewBuilder
    private var planText: some View {
        switch report.standing {
        case .losing(_, let guideline, let progress)?:
            if report.weight.endAverage == nil {
                Text(ReportWording.noAverage).font(.subheadline)
            } else {
                Text(ReportWording.progress(progress, guideline: guideline, settings: .default)).font(.subheadline)
            }
        case .maintaining(_, _, _, _, let position)?:
            Text(ReportWording.maintenance(position)).font(.subheadline)
        case nil:
            if report.weight.endAverage == nil { Text(ReportWording.noAverage).font(.subheadline) }
        }
    }

    @ViewBuilder
    private var changesList: some View {
        if !report.changes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(report.changes.enumerated()), id: \.offset) { _, change in
                    Text(ReportWording.change(change))
                }
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryText)
        }
    }

    // MARK: 体組成

    @ViewBuilder
    private var compositionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch report.composition {
            case .unavailable:
                Text(period.kind == .midMonth ? "体組成の変化" : "体組成").font(.headline)
                Text("体脂肪率の記録が少なく、比べられませんでした。").font(.subheadline)
            case .directions(let fat, let lean):
                Text("体組成の変化").font(.headline)
                directionRow("体脂肪率", fat)
                if let lean {
                    Divider()
                    directionRow("除脂肪量", lean)
                }
                Text("数値は\(DisplayFormat.dayWithWeekday(monthEndDay))の月末レポートでお届けします。")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryText)
            case .values(let v):
                compositionValues(v)
            }
        }
        .card()
    }

    private var monthEndDay: CalendarDay {
        CalendarDay(year: period.year, month: period.month, day: ReportPeriod.lastDayOfMonth(year: period.year, month: period.month))
    }

    private func directionRow(_ label: String, _ direction: CompositionDirection) -> some View {
        HStack {
            Text(label)
            Spacer()
            Label(ReportWording.direction(direction), systemImage: ReportWording.directionSymbol(direction))
                .font(.headline)
                .foregroundStyle(direction == .flat ? AppTheme.secondaryText : AppTheme.accent)
        }
    }

    @ViewBuilder
    private func compositionValues(_ v: CompositionValues) -> some View {
        HStack {
            Text("体組成").font(.headline)
            Spacer()
            Text("月に一度だけの数値です").font(.footnote).foregroundStyle(AppTheme.secondaryText)
        }
        Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                Text("").frame(maxWidth: .infinity, alignment: .leading).gridColumnAlignment(.leading)
                Text(baselineColumn(v.baselineLabel)).font(.footnote).foregroundStyle(AppTheme.secondaryText)
                Text("\(period.month)月").font(.footnote.bold())
            }
            GridRow {
                Text("体脂肪率").gridColumnAlignment(.leading)
                Text(String(format: "%.1f %%", v.bodyFatPercent.baseline)).foregroundStyle(AppTheme.secondaryText)
                Text(String(format: "%.1f %%", v.bodyFatPercent.current)).font(.title3.bold())
            }
            if let lean = v.leanMass {
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text("除脂肪量").gridColumnAlignment(.leading)
                    Text(DisplayFormat.kilograms(lean.baseline)).foregroundStyle(AppTheme.secondaryText)
                    Text(DisplayFormat.kilograms(lean.current)).font(.title3.bold())
                }
            }
        }
        let notes = [v.showsLeanMassNote ? "体重が減ると、除脂肪量も少し減るのは自然なことです。" : nil,
                     v.showsFatShareNote ? "減った体重の半分以上は脂肪でした。" : nil].compactMap { $0 }
        if !notes.isEmpty {
            Text(notes.joined()).font(.footnote).foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func baselineColumn(_ label: CompositionValues.BaselineLabel) -> String {
        switch label {
        case .month(let m): "\(m)月"
        case .planStart: "開始時"
        }
    }

    // MARK: ステージ

    @ViewBuilder
    private var midStageCard: some View {
        if let (title, text) = ReportWording.stageSummary(report.standing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline).foregroundStyle(AppTheme.accent)
                Text(text).font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(AppTheme.track, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }

    @ViewBuilder
    private var monthEndStageCard: some View {
        if let stage = report.stage {
            VStack(alignment: .leading, spacing: 10) {
                switch stage.phase {
                case .losing(let number, let origin):
                    HStack {
                        Text("ステージ\(number)").font(.headline).foregroundStyle(AppTheme.accent)
                        Spacer()
                        if let target = stage.target {
                            Text("\(stage.aimingFirstMilestone ? "最初の区切り" : "次の区切り") \(DisplayFormat.kilograms(target))")
                                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    if let target = stage.target {
                        ProgressBar(fraction: StageCard.fraction(origin: origin.weight, target: target, current: report.weight.endAverage))
                    }
                    HStack {
                        Text(DisplayFormat.kilograms(origin.weight))
                        Spacer()
                        if let arrival = stage.estimatedArrival {
                            Text("到達予定 \(DisplayFormat.approximateDate(arrival))")
                        }
                    }
                    .font(.footnote).foregroundStyle(AppTheme.secondaryText)
                case .maintaining(let number, let arrival):
                    Text("ステージ\(number)の維持期間").font(.headline).foregroundStyle(AppTheme.accent)
                    Text("\(DisplayFormat.kilograms(arrival.weight)) を保つ期間です").font(.subheadline)
                case .maintenanceMode(let arrival):
                    Text("維持モード").font(.headline).foregroundStyle(AppTheme.accent)
                    Text("\(DisplayFormat.kilograms(arrival.weight)) を保っていく時期です").font(.subheadline)
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private var paceCard: some View {
        if let note = report.paceNote {
            let (title, text) = ReportWording.pace(note)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(AppTheme.track, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }
}

private extension View {
    /// カードの中の灰色の囲み(目安と実際)。
    func infoBox() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// ホームの一番下の「次のレポート」(デザイン1枚目)。届いていて未読なら「届きました」。
struct NextReportCard: View {
    let unread: ReportContent?
    let next: ReportPeriod?
    var open: () -> Void = {}

    var body: some View {
        Button(action: open) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let unread {
                        Text("レポートが届きました").font(.subheadline).foregroundStyle(AppTheme.accent)
                        Text(ReportWording.title(unread.period)).font(.headline)
                    } else if let next {
                        Text("次のレポート").font(.subheadline).foregroundStyle(AppTheme.accent)
                        Text("\(DisplayFormat.dayWithWeekday(next.releaseDay)) \(ReportWording.kindName(next.kind))").font(.headline)
                    }
                }
                .foregroundStyle(Color(.label))
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(AppTheme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(AppTheme.track, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
        .buttonStyle(.plain)
    }
}

#Preview("月半ば・計画どおり") {
    ReportView(report: PreviewData.report(.midOnTrack), previous: {}, next: nil)
}

#Preview("月半ば・予定より早い") {
    ReportView(report: PreviewData.report(.midAhead))
}

#Preview("月半ば・ゆっくり") {
    ReportView(report: PreviewData.report(.midSlower))
}

#Preview("月半ば・最初の1か月") {
    ReportView(report: PreviewData.report(.midSettlingIn))
}

#Preview("月半ば・体組成が比べられない") {
    ReportView(report: PreviewData.report(.midNoBodyFat))
}

#Preview("月半ば・記録が少ない") {
    ReportView(report: PreviewData.report(.midFewRecords))
}

#Preview("月半ば・見直しの提案あり") {
    ReportView(report: PreviewData.report(.midSlower),
               planReviewCard: .planReview(stage: 1, before: CalendarDay(year: 2027, month: 1, day: 5), after: CalendarDay(year: 2027, month: 2, day: 15)))
}

#Preview("月末・減量中(脂肪の一言)") {
    ReportView(report: PreviewData.report(.endLosing))
}

#Preview("月末・最初の月(開始時と比べる)") {
    ReportView(report: PreviewData.report(.endFirstMonth))
}

#Preview("月末・速すぎるペース") {
    ReportView(report: PreviewData.report(.endTooFast))
}

#Preview("月末・前倒しの一言") {
    ReportView(report: PreviewData.report(.endAhead))
}

#Preview("月末・維持期間(期間内に到達)") {
    ReportView(report: PreviewData.report(.endArrivedInPeriod))
}

#Preview("月末・維持モード") {
    ReportView(report: PreviewData.report(.endMaintenanceMode))
}

#Preview("レポートタブ・公開済みなし") {
    NoReportView(next: ReportPeriod.next(planStart: CalendarDay(year: 2026, month: 11, day: 20), after: CalendarDay(year: 2026, month: 11, day: 24), settings: .default))
}

#Preview("レポートタブ(前後の移動)") {
    ReportScreen(model: PreviewData.homeModel(.onTrack))
}

#Preview("ホーム・次のレポート") {
    NextReportCard(unread: nil, next: ReportPeriod.next(planStart: CalendarDay(year: 2026, month: 10, day: 24), after: CalendarDay(year: 2026, month: 11, day: 24), settings: .default))
        .padding()
}

#Preview("ホーム・届きました") {
    NextReportCard(unread: PreviewData.report(.midOnTrack), next: nil)
        .padding()
}
