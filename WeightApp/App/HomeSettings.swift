/// 表示に関する設定値。閾値と同じく1か所にまとめる(判定の閾値は WeightCore の PlanSettings)。
enum HomeSettings {
    /// グラフと記録カレンダーが使う履歴の日数(当日を含む)。
    static let historyDays = 28
}
