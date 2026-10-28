import SwiftUI
import WeightCore

/// 初回設定。開始体重(初期値は直近7日平均か最新値)、身長(最終目標の初期値のためだけ)、最終目標(BMI 22)。
struct SetupView: View {
    let model: HomeModel
    @State private var form: SetupFormState
    @State private var isSaving = false
    @State private var saveFailureText: String?
    private let suggestion: HomeModel.StartWeightSuggestion

    init(model: HomeModel) {
        self.model = model
        let suggestion = model.startWeightSuggestion
        self.suggestion = suggestion
        let suggested: Double? = switch suggestion {
        case .sevenDayAverage(let kg), .latest(let kg): kg
        case .none: nil
        }
        _form = State(initialValue: SetupFormState(suggestedStartWeight: suggested))
    }

    private var startNote: String {
        switch suggestion {
        case .sevenDayAverage: "直近7日間の平均を入れてあります。違っていれば直してください。"
        case .latest: "直近の記録を入れてあります。違っていれば直してください。"
        case .none: "ヘルスケアに体重の記録がないので、いまの体重を入れてください。"
        }
    }

    private var problemText: String? {
        switch form.problem {
        case nil: nil
        case .notNumber: "数字で入れてください"
        case .targetNotBelowStart: "最終目標は開始体重より小さい値にしてください"
        case .notPositive: "0 より大きい値にしてください"
        }
    }

    private var summaryText: String {
        let today = DisplayFormat.dayWithWeekday(CalendarDay(date: Date(), calendar: AppCalendar.tokyo))
        if let milestone = form.firstMilestoneWeight {
            return "開始日は今日(\(today))。最初の区切りは \(DisplayFormat.kilograms(milestone)) です。"
        }
        return "開始日は今日(\(today))。"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("はじめる")
                    .font(.largeTitle.bold())
                    .padding(.top, 24)

                field(title: "開始体重", text: $form.startText, unit: "kg", note: startNote, keyboard: .decimalPad)
                field(title: "身長", text: Binding(get: { form.heightText }, set: { form.heightChanged($0) }),
                      unit: "cm", note: "最終目標の初期値を決めるためだけに使います。", keyboard: .numberPad)
                field(title: "最終目標", text: Binding(get: { form.targetText }, set: { form.targetChanged($0) }),
                      unit: "kg", note: "BMI 22 の体重を入れてあります。", keyboard: .decimalPad)

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        Task { await start() }
                    } label: {
                        Text("この計画で始める")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(!form.canStart || isSaving)

                    if let problemText {
                        Text(problemText).font(.footnote).foregroundStyle(AppTheme.secondaryText)
                    } else {
                        Text(summaryText).font(.footnote).foregroundStyle(AppTheme.secondaryText)
                    }
                    if let saveFailureText {
                        Text(saveFailureText)
                            .font(.footnote).foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
        }
        .background(AppTheme.background.ignoresSafeArea())
    }

    private func field(title: String, text: Binding<String>, unit: String, note: String, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("", text: text)
                    .keyboardType(keyboard)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
                Text(unit).font(.title3).foregroundStyle(AppTheme.secondaryText)
            }
            Text(note).font(.footnote).foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func start() async {
        guard let start = form.startWeight, let target = form.targetWeight else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.startPlan(startWeight: start, targetWeight: target)
            saveFailureText = nil
        } catch HomeModel.StartPlanError.savedButRefreshFailed, HomeModel.StartPlanError.alreadyStarted {
            // 計画は保存済み。上書きはせず、次に開いたときの取り直しに任せる
            saveFailureText = "計画は保存しました。ヘルスケアから体重を読み取れなかったので、もう一度開いてみてください。"
        } catch {
            saveFailureText = "計画を保存できませんでした。もう一度お試しください。"
        }
    }
}

#Preview("7日平均の初期値あり") {
    SetupView(model: PreviewData.setupModel(.sevenDayAverage))
}

#Preview("最新値の初期値") {
    SetupView(model: PreviewData.setupModel(.latest))
}

#Preview("記録なし(空欄)") {
    SetupView(model: PreviewData.setupModel(.none))
}

#Preview("検証エラー(最終目標が開始体重以上)") {
    SetupView(model: PreviewData.setupModel(.invalid))
}
