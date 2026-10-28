import SwiftUI
import WeightCore

/// `HomeModel` を見て `HomeView` に渡す薄い層。
struct HomeScreen: View {
    let model: HomeModel

    var body: some View {
        if let summary = model.summary {
            HomeView(summary: summary, showsRefreshFailure: model.lastRefreshFailed)
        } else {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ProgressView()
            }
        }
    }
}

/// ホーム画面(デザイン1枚目)。出す数値は体重だけ。評価ラベル、体組成、最終目標(最終ステージを除く)は出さない。
struct HomeView: View {
    let summary: DailySummary
    /// 取り直しに失敗して前回の値を出している。
    var showsRefreshFailure = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                WeightCard(summary: summary)
                // フェーズ5のカード(計画見直し、85日目、早期到達、維持中の一言)はここに差し込む
                if let plan = summary.plan {
                    StageCard(plan: plan, sevenDayAverage: summary.sevenDayAverage?.kilograms, day: summary.day)
                }
                WeekRecordCard(day: summary.day, history: summary.history)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(DisplayFormat.dayWithWeekday(summary.day))
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            Text("今日の体重")
                .font(.largeTitle.bold())
            if showsRefreshFailure {
                Text("最新の値を読み取れませんでした。前回の値を表示しています。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.top, 16)
    }
}

/// カードの共通の見た目。
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

#Preview("記録なし(7日平均が出ない)") {
    HomeScreen(model: PreviewData.homeModel(.noRecords))
}

#Preview("減量中・最初の1か月") {
    HomeScreen(model: PreviewData.homeModel(.settlingIn))
}

#Preview("減量中・計画どおり") {
    HomeScreen(model: PreviewData.homeModel(.onTrack))
}

#Preview("減量中・最初の区切り到達後") {
    HomeScreen(model: PreviewData.homeModel(.afterFirstMilestone))
}

#Preview("減量中・最終ステージ") {
    HomeScreen(model: PreviewData.homeModel(.finalStage))
}

#Preview("維持期間") {
    HomeScreen(model: PreviewData.homeModel(.maintaining))
}

#Preview("維持モード") {
    HomeScreen(model: PreviewData.homeModel(.maintenanceMode))
}

#Preview("読み取り失敗(前回の値)") {
    HomeScreen(model: PreviewData.homeModel(.refreshFailed))
}
