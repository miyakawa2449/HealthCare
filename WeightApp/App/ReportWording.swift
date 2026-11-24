import Foundation
import WeightCore

/// レポートの文言(06-reports/04-wording.md)。責めない言葉づかい。評価ラベルを使わない。
enum ReportWording {
    /// "11月前半のレポート" / "11月のレポート"。
    static func title(_ period: ReportPeriod) -> String {
        switch period.kind {
        case .midMonth: "\(period.month)月前半のレポート"
        case .monthEnd: "\(period.month)月のレポート"
        }
    }

    /// "11月1日〜15日"。
    static func range(_ period: ReportPeriod) -> String {
        "\(period.month)月\(period.firstDay.day)日〜\(period.lastDay.day)日"
    }

    /// ホームの「次のレポート」に出す種類。
    static func kindName(_ kind: ReportPeriod.Kind) -> String {
        switch kind {
        case .midMonth: "月半ばのレポート"
        case .monthEnd: "月末のレポート"
        }
    }

    /// 記録できた日の一言。
    static func continuity(_ c: RecordContinuity, period: ReportPeriod) -> String {
        if c.allRecorded { return "この期間、毎日記録できました。" }
        if c.recordedDays * 2 >= c.totalDays, c.totalDays > 0 {
            if period.isClippedByPlanStart { return "この期間、よく続けられました。" }
            return period.kind == .midMonth ? "この2週間、よく続けられました。" : "この1か月、よく続けられました。"
        }
        return "記録できた日の分だけ、体重の流れが見えてきます。途切れても、また今日から。"
    }

    /// "−3.4 kg" / "+0.8 kg" / "±0.0 kg"。
    static func signedKilograms(_ value: Double) -> String {
        let v = Weight.rounded(value)
        if v < 0 { return String(format: "−%.1f kg", -v) }
        if v > 0 { return String(format: "+%.1f kg", v) }
        return "±0.0 kg"
    }

    /// 体重の流れの下に出す、進み具合の一言。
    static func progress(_ progress: ProgressJudgment?, guideline: Double, settings: PlanSettings) -> String {
        switch progress {
        case .onTrack:
            "計画どおりです。目安との差は ±\(DisplayFormat.kilograms(guideline * settings.progressBand)) 以内です。"
        case .aheadOfSchedule: "予定より早いペースです。"
        case .slowerPace: "ゆっくりペースです。日々の上下より、流れを見ていきましょう。"
        case .settlingIn: "最初の1か月は、体の水分が落ち着く時期です。目安との比べ方は、この時期を過ぎてから始めます。"
        case nil: noAverage
        }
    }

    static let noAverage = "記録が少なく、この期間の平均を出せませんでした。"

    static func maintenance(_ position: MaintenancePosition?) -> String {
        switch position {
        case .within: "維持の範囲に収まっています。"
        case .above: "維持の範囲から少し上にいます。いつもの生活のリズムで大丈夫です。"
        case .below: "維持の範囲から少し下にいます。減らしすぎていないか、食事の量を見直してみてください。"
        case nil: noAverage
        }
    }

    /// 期間内の出来事(フェーズ5のカードの見出しと同じ言葉)。
    static func change(_ change: PhaseTimeline.Change) -> String {
        let text = switch change.kind {
        case .arrived(let stage, let weight): "ステージ\(stage)の区切り \(DisplayFormat.kilograms(weight)) に届きました"
        case .reachedTarget(let weight): "最後の区切り \(DisplayFormat.kilograms(weight)) に届きました"
        case .advanced(let toStage): "維持期間を終えて、ステージ\(toStage)に進みました"
        case .planRebased: "最近のペースに合わせて、計画を見直しました"
        case .planReverted: "元の計画に戻しました"
        }
        return "\(change.day.month)月\(change.day.day)日 \(text)"
    }

    static func direction(_ d: CompositionDirection) -> String {
        switch d {
        case .down: "下がった"
        case .flat: "横ばい"
        case .up: "上がった"
        }
    }

    static func directionSymbol(_ d: CompositionDirection) -> String {
        switch d {
        case .down: "arrow.down"
        case .flat: "arrow.right"
        case .up: "arrow.up"
        }
    }

    /// 月半ばのステージの一言(見出し, 本文)。
    static func stageSummary(_ standing: PlanStanding?) -> (String, String)? {
        switch standing {
        case .losing(let stage, _, let progress)?:
            let text: String = switch progress {
            case .onTrack: "計画どおりに進んでいます"
            case .aheadOfSchedule: "予定より早いペースで進んでいます"
            case .slowerPace: "ゆっくりペースで進んでいます"
            case .settlingIn: "体が落ち着く時期です"
            case nil: "記録が入ると、進み具合をお伝えします"
            }
            return ("ステージ\(stage)", text)
        case .maintaining(let stage?, _, _, _, _)?:
            return ("ステージ\(stage)の維持期間", "体重を保つ時期です")
        case .maintaining(nil, _, _, _, _)?:
            return ("維持モード", "この体重を保つ時期です")
        case nil:
            return nil
        }
    }

    /// 月末のペースの一言(見出し, 本文)。
    static func pace(_ note: PaceNote) -> (String, String) {
        switch note {
        case .tooFast: ("最近のペースは、目安よりかなり速めです", "目標はそのままに、少しゆるめても大丈夫です。")
        case .aheadWithinLimit: ("予定より少し早いペースです", "目標ペースはそのままに、前倒しとして見守ります。")
        }
    }
}
