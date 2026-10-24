import SwiftUI
import WeightCore

/// 起動確認の延長。7日平均(大)と当日の体重(小)の数値だけを出す。評価・色・ステージは出さない(フェーズ4)。
struct ContentView: View {
    @State private var model = HomeModel.live()

    var body: some View {
        VStack(spacing: 16) {
            if let summary = model.summary, let average = summary.sevenDayAverage {
                Text("直近7日間の平均")
                    .font(.subheadline)
                Text(Self.kilograms(average.kilograms))
                    .font(.system(size: 48, weight: .medium, design: .rounded))
                if let today = summary.todayWeight {
                    Text("今日の測定 \(Self.kilograms(today.kilograms))")
                        .font(.footnote)
                }
            } else {
                Text("今日の体重")
            }
        }
        .task { await model.refresh() }
    }

    static func kilograms(_ value: Double) -> String {
        String(format: "%.1f kg", Weight.rounded(value))
    }
}

#Preview {
    ContentView()
}
