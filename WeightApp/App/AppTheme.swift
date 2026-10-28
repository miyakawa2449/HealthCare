import SwiftUI

/// 色と見た目の定義。赤・橙・黄の警告色は定義しない(判定は色ではなく言葉で伝える)。
/// 背景と文字はシステム色に任せ、アクセントの緑だけ固定にする(03-decisions.md #8)。
enum AppTheme {
    /// アクセント。見出し、線、バー、記録の印に使う。
    static let accent = Color(red: 0x2E / 255, green: 0x6B / 255, blue: 0x5E / 255)
    /// 画面の背景。
    static let background = Color(.systemGroupedBackground)
    /// カードの背景。
    static let card = Color(.secondarySystemGroupedBackground)
    /// 補足の文字。
    static let secondaryText = Color(.secondaryLabel)
    /// バーやグラフの下地(アクセントを薄くした色)。
    static let track = accent.opacity(0.18)
    /// カードの角丸。
    static let cornerRadius: CGFloat = 16
}
