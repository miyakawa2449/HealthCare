import SwiftUI

/// 起動後の画面の振り分け(01-design.md 0.)。
struct RootView: View {
    let model: HomeModel

    var body: some View {
        switch RootRoute.route(for: model) {
        case .unavailable:
            UnavailableView(kind: model.unavailableReason == .planStore ? .planStore : .healthKit)
        case .loading:
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ProgressView()
            }
        case .failed:
            UnavailableView(kind: .firstReadFailed)
        case .setup:
            SetupView(model: model)
        case .home:
            MainTabView(model: model)
        }
    }
}

/// ホーム / ロードマップ / レポートのタブ。ロードマップとレポートの中身は後のフェーズ(03-decisions.md #5)。
struct MainTabView: View {
    let model: HomeModel

    var body: some View {
        TabView {
            Tab("ホーム", systemImage: "house") {
                HomeScreen(model: model)
            }
            Tab("ロードマップ", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                PlaceholderView(text: "ロードマップは次の段階で作ります。")
            }
            Tab("レポート", systemImage: "doc.text") {
                PlaceholderView(text: "レポートは次の段階で作ります。")
            }
        }
        .tint(AppTheme.accent)
    }
}

/// まだ作っていない画面の仮置き。
struct PlaceholderView: View {
    let text: String

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            Text(text)
                .foregroundStyle(AppTheme.secondaryText)
                .padding()
        }
    }
}

/// 使えない・失敗したときの画面。文言だけで、色で警告しない。
struct UnavailableView: View {
    enum Kind {
        case healthKit, planStore, firstReadFailed

        var text: String {
            switch self {
            case .healthKit: "この端末ではヘルスケアが使えないため、体重を読み取れません。"
            case .planStore: "計画の保存先を用意できませんでした。App Group の設定を確認してください。"
            case .firstReadFailed: "ヘルスケアから体重を読み取れませんでした。もう一度開いてみてください。"
            }
        }
    }

    let kind: Kind

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            Text(kind.text)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.secondaryText)
                .padding(32)
        }
    }
}

#Preview("ヘルスケアが使えない") {
    UnavailableView(kind: .healthKit)
}

#Preview("保存先が取れない") {
    UnavailableView(kind: .planStore)
}

#Preview("最初の読み取りに失敗") {
    UnavailableView(kind: .firstReadFailed)
}

#Preview("タブ(ロードマップの仮の画面)") {
    PlaceholderView(text: "ロードマップは次の段階で作ります。")
}

#Preview("起動の振り分け: 読み込み中") {
    RootView(model: PreviewData.loadingModel())
}
