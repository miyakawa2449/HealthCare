import Foundation

/// 割合(1.0 = 100%)の丸め。判定はすべて丸めてから比較する。
public enum Ratio {
    /// 小数第4位(= 0.01%)に丸める。
    ///
    /// 0.505% のような「ちょうど半分」が二進数の表現誤差(0.50499…%)で下に落ちないよう、
    /// 丸める前にゼロから遠ざかる向きへごく小さな補正を加える。
    ///
    /// 許容誤差: 補正は 0.01% 単位で 1e-9(割合で 1e-13)。この幅だけ境界をわずかに下回る値も
    /// 境界以上として丸める。体重 0.1kg 単位の測定値から生じる割合はこれより桁違いに大きいので、
    /// 実用上は「ちょうど半分を正しく扱う」効果だけが残る。厳密な十進丸めが必要になったら Decimal に切り替える。
    public static func rounded(_ value: Double) -> Double {
        let scaled = value * 10_000
        return (scaled + copysign(1e-9, scaled)).rounded(.toNearestOrAwayFromZero) / 10_000
    }
}

/// 体重(kg)の丸め。表示と、ステージ到達・維持期間の判定に使う。
public enum Weight {
    /// 小数第1位(0.1kg)に丸める。`Ratio.rounded` と同じ理由で半分の補正を入れる(許容誤差は 1e-10kg)。
    public static func rounded(_ kilograms: Double) -> Double {
        let scaled = kilograms * 10
        return (scaled + copysign(1e-9, scaled)).rounded(.toNearestOrAwayFromZero) / 10
    }
}
