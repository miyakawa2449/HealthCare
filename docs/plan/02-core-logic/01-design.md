# 型の設計案

すべて `WeightCore` モジュールの public な値型(`struct` / `enum`)。`Sendable`、`Equatable` を付ける。
`Roadmap` は保存するので `Codable` も付ける。閾値はすべて `PlanSettings` から取り、関数の引数で受け取る。

## 日付の扱い

- **`CalendarDay`**: 年・月・日だけを持つ値型(`Comparable`、`Hashable`、`Codable`)。時刻とタイムゾーンを持たない。
  - `init(date: Date, calendar: Calendar)` で、与えたカレンダーのタイムゾーンで日付に落とす。
  - `adding(days:)`、`days(until:)` は内部で `Calendar(identifier: .gregorian)` + UTC で計算する(暦日の差分なので、どのタイムゾーンでも同じ結果になる)。
- アプリ側は `Calendar` を `Asia/Tokyo` に固定して渡す。WeightCore はタイムゾーンを決め打ちしない。
- テストは `Calendar(identifier: .gregorian)` に `TimeZone(identifier: "Asia/Tokyo")` を設定した固定のカレンダーを使う。

## 丸め

- **`Ratio`**: 割合(1.0 = 100%)の比較用ヘルパー。`static func rounded(_ value: Double) -> Double` で小数第4位(= 0.01%)に丸める。丸め方は `.toNearestOrAwayFromZero`。
- 判定はすべて「丸めてから比較」する。例: `Ratio.rounded(diff / guideline) <= settings.progressBand`。
- 体重の表示・比較用の丸めは **`Weight.rounded(_:)`** で小数第1位(0.1kg)。ステージ到達判定と維持期間の判定はこの丸めた値で行う。

## 1. 1日の体重の決定: `DailyWeightResolver`

```swift
public struct WeightSample: Sendable, Equatable {
    public var kilograms: Double
    public var measuredAt: Date
    public var source: SampleSource   // .healthPlanet / .other
}
public struct DailyWeight: Sendable, Equatable {
    public var day: CalendarDay
    public var kilograms: Double
    public var measuredAt: Date
    public var source: SampleSource
}
public enum DailyWeightResolver {
    public static func resolve(_ samples: [WeightSample], calendar: Calendar) -> [DailyWeight]
}
```

- `measuredAt` を `calendar` で `CalendarDay` に落として日ごとに分ける。
- 各日で、HealthPlanet 由来のサンプルがあればその中で `measuredAt` が最も早いもの。なければ他ソースの中で最も早いもの(03-decisions.md #3)。
- 結果は日付の昇順。
- HKSource の Bundle ID を `SampleSource` に変換するのはアプリ側(フェーズ3)。WeightCore は enum だけを見る。

## 2. 7日平均: `SevenDayAverage`

```swift
public enum SevenDayAverage {
    public static func value(endingOn day: CalendarDay, in weights: [DailyWeight]) -> Double?
}
```

- `day` を含む直近7日(`day - 6` 〜 `day`)にある `DailyWeight` の単純平均。
- 窓の中に1件もなければ `nil`。件数の下限は設けない(03-decisions.md #2)。
- 丸めない(表示側で丸める)。

## 3. 目安と進み具合: `Guideline`、`ProgressJudgment`

```swift
public enum Guideline {
    /// 開始体重 × (1 − monthlyRate)^(経過日数 ÷ daysPerMonth)
    public static func expectedWeight(startWeight: Double, daysElapsed: Int, settings: PlanSettings) -> Double
}
public enum ProgressJudgment: Sendable, Equatable {
    case onTrack          // 計画どおり
    case aheadOfSchedule  // 予定より早いペース
    case slowerPace       // ゆっくりペース
    public static func judge(sevenDayAverage: Double, guideline: Double, settings: PlanSettings) -> ProgressJudgment
}
```

- `ratio = Ratio.rounded((sevenDayAverage − guideline) / guideline)`(分母は目安の値)。
- `|ratio| <= progressBand` → `onTrack`、`ratio < −progressBand` → `aheadOfSchedule`、`ratio > progressBand` → `slowerPace`。
- 経過日数が負の場合は `expectedWeight` は `startWeight` を返す(開始日より前は目安なし扱い)。

## 4. 安全性の判定: `SafetyJudgment`

```swift
public enum SafetyJudgment: Sendable, Equatable {
    case comfortable   // 無理がない
    case caution       // 頑張りすぎ注意
    case danger        // 危険
    public static func judge(weeklyRate: Double, settings: PlanSettings) -> SafetyJudgment
    /// 現在の体重から目標まで days 日で減らすのに必要な週あたりの割合(期日指定モードの材料)
    public static func requiredWeeklyRate(from current: Double, to target: Double, days: Int) -> Double
}
```

- `r = Ratio.rounded(weeklyRate)`。`r <= weeklySafeLimit` → `comfortable`、`r <= weeklyCautionLimit` → `caution`、それ以外 → `danger`。
- `requiredWeeklyRate = 1 − (target / current)^(7 / days)`。期日指定モードそのものは対象外だが、純粋な式なのでここで用意しておく。

## 5. ロードマップ: `Roadmap`

```swift
public struct Stage: Sendable, Equatable, Codable {
    public var number: Int                 // 1 始まり
    public var startWeight: Double         // 丸め済み
    public var boundaryWeight: Double      // 丸め済み。このステージの到達体重
    public var estimatedArrival: CalendarDay
}
public struct Roadmap: Sendable, Equatable, Codable {
    public var startWeight: Double
    public var startDay: CalendarDay
    public var targetWeight: Double
    public var firstMilestoneWeight: Double     // 開始体重 × (1 − 0.05) を丸めたもの
    public var stages: [Stage]
    public var settings: PlanSettings
    public init(startWeight:, startDay:, targetWeight:, settings:)
    public func stage(containing sevenDayAverage: Double) -> Stage?   // 今いるステージ
}
```

- 境界: `startWeight × (1 − stageRatio)^k` を丸めずに連鎖させ、各境界だけを `Weight.rounded` で丸める。`targetWeight` を下回る境界が出たらそこで `targetWeight` に置き換えて打ち切る。境界がちょうど `targetWeight` に一致したらそれが最終ステージ。
- `startWeight <= targetWeight` のときは `stages` が空(計画を作れない)。
- 到達予定日: ステージ k の減量日数 = `ceil(ln(boundary_k / boundary_{k−1}) / ln(1 − monthlyRate) × daysPerMonth)`。ステージ 2 以降は、前のステージの維持期間として `settings.assumedMaintenanceDays` を足す(03-decisions.md #1)。最終ステージの後には足さない。
- 到達判定: `Weight.rounded(sevenDayAverage) <= boundaryWeight`。
- `PlanSettings` に `assumedMaintenanceDays` を追加する。

## 6. 実績ペース: `ActualPace`

```swift
public enum ActualPace {
    /// 直近28日間の7日平均の変化率を月あたりに換算した値。データ不足なら nil
    public static func monthlyRate(endingOn day: CalendarDay, in weights: [DailyWeight], settings: PlanSettings) -> Double?
    public static func isTooFast(monthlyRate: Double, settings: PlanSettings) -> Bool
}
```

- `now = SevenDayAverage(day)`、`then = SevenDayAverage(day − actualPaceWindowDays)`。どちらかが `nil` なら `nil`。
- `monthlyRate = 1 − (now / then)^(daysPerMonth / actualPaceWindowDays)`(03-decisions.md #4)。
- `isTooFast = Ratio.rounded(monthlyRate) > fastPaceMonthlyLimit`。ちょうど3%は速すぎではない。

## 7. 維持期間: `MaintenanceJudgment`

```swift
public enum MaintenanceState: Sendable, Equatable {
    case inProgress(consecutiveDaysInBand: Int)
    case graduated(on: CalendarDay)
    case exceededMaximum(consecutiveDaysInBand: Int)   // 12週超。カードで提案
}
public enum MaintenanceJudgment {
    public static func evaluate(arrivalDay: CalendarDay, arrivalWeight: Double,
                                through day: CalendarDay, weights: [DailyWeight],
                                settings: PlanSettings) -> MaintenanceState
}
```

- `arrivalDay` から `day` まで1日ずつ、その日の7日平均を `Weight.rounded` で丸め、`|avg − arrivalWeight| / arrivalWeight` を `Ratio.rounded` して `<= maintenanceBand` なら範囲内。
- 範囲内の日が連続で `maintenanceMinDays`(28)に達した最初の日に `graduated`。範囲外の日、または7日平均が `nil` の日(03-decisions.md #7)で連続カウントを 0 に戻す。
- 卒業しないまま `arrivalDay` からの経過日数が `maintenanceMaxDays`(84)を超えたら `exceededMaximum`。卒業条件の判定を先に行う(84日目までに卒業していればそちら)。

## 8. 計画見直しの発動: `PlanReviewTrigger`

```swift
public enum PlanReviewTrigger {
    public static func shouldPropose(roadmap: Roadmap, through day: CalendarDay,
                                     weights: [DailyWeight]) -> Bool
}
```

- `day` から遡って `reviewWindowDays`(14)日の各日について、7日平均と目安(`Guideline.expectedWeight`)の差の割合を `Ratio.rounded` し、`|ratio| >= reviewDeviation`(2%) なら「ずれている」。分母は目安(計画値)。
- 14日すべてがずれていたら `true`。7日平均が `nil` の日があれば `false`(判断できない)。上下どちらのずれも対象(03-decisions.md #6)。
- 見直しを「採用したあとの再起点」は `Roadmap` を新しい `startWeight` / `startDay` で作り直し、`stages` の境界だけ元の値を引き継ぐ初期化子 `Roadmap(rebasing: old, startWeight:, startDay:)` で表す。

## 9. 最初の1か月

03-decisions.md #5 の回答後に設計を確定する。いずれの案でも `PlanSettings.initialPeriodDays = 30` を追加する。
