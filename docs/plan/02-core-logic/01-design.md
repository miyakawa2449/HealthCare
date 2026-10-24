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
public struct SevenDayAverage: Sendable, Equatable {
    public var kilograms: Double
    public var daysUsed: Int     // 平均に使った日数(1〜7)
    public init?(endingOn day: CalendarDay, in weights: [DailyWeight])
}
```

- `day` を含む直近7日(`day - 6` 〜 `day`)にある `DailyWeight` の単純平均。平均に使った日数も返す。
- 窓の中に1件もなければ `nil`。件数の下限は設けない(03-decisions.md #2。下限は実機で使ってから決める)。
- 丸めない(表示側で丸める)。

## 2b. フェーズ: `PlanPhase`、`StageOrigin`(03-decisions.md #9 の A 案)

```swift
public struct StageOrigin: Codable { var weight: Double /* 0.1kg 丸め済み */; var day: CalendarDay }
public enum PlanPhase: Codable {
    case losing(stage: Int, origin: StageOrigin)       // 減量中。origin はステージ開始時の7日平均と日付
    case maintaining(stage: Int, arrival: StageOrigin) // 維持期間。arrival は到達日の7日平均と日付
    case maintenanceMode(arrival: StageOrigin)         // 最終目標の後
    func rebased(sevenDayAverage:on:) -> PlanPhase?    // 計画見直しの採用(減量中だけ)
}
```

- アプリが保存する「いまどこにいるか」。計画値(目安)、進み具合、実績ペース、計画見直しはすべてこれを基準にする。
- 遷移は `Roadmap` のメソッドで表す: `initialPhase`(ステージ1、起点は計画の開始。ステージがなければ nil)、`phaseOnArrival(stage:sevenDayAverage:on:)`(維持期間へ。最終ステージなら維持モード。番号が 1...ステージ数 の外なら nil)、`phaseOnAdvance(from:sevenDayAverage:on:)`(維持期間から次のステージへ。その日の7日平均と日付が次の起点。範囲外なら nil)。`rescheduled(from:)` は範囲外のフェーズを無視して元のロードマップを返す。
- `Roadmap.rescheduled(from:)` でフェーズから到達予定日を計算し直す。減量中はそのステージを起点から、維持中はそのステージの予定日を実際の到達日にして次を「到達日 + 維持期間(仮定)」から。境界と手前のステージは変えない。

## 3. 目安と進み具合: `Guideline`、`ProgressJudgment`

```swift
public enum Guideline {
    /// フェーズに従った計画値。減量中は起点から月2%で日割り、維持中と維持モードは到達時の体重で一定
    public static func expectedWeight(phase: PlanPhase, on day: CalendarDay, settings: PlanSettings) -> Double
    /// 日割りの式: 開始体重 × (1 − monthlyRate)^(経過日数 ÷ daysPerMonth)
    public static func expectedWeight(startWeight: Double, daysElapsed: Int, settings: PlanSettings) -> Double
}
public enum ProgressJudgment: Sendable, Equatable {
    case settlingIn       // 最初の1か月(ステージ1だけ)
    case onTrack          // 計画どおり
    case aheadOfSchedule  // 予定より早いペース
    case slowerPace       // ゆっくりペース
    /// 減量中でなければ nil
    public static func judge(phase: PlanPhase, sevenDayAverage: Double, on day: CalendarDay, roadmap: Roadmap) -> ProgressJudgment?
    public static func judge(sevenDayAverage: Double, guideline: Double, settings: PlanSettings) -> ProgressJudgment
}
```

- `ratio = Ratio.rounded((sevenDayAverage − guideline) / guideline)`(分母は目安の値)。
- `|ratio| <= progressBand` → `onTrack`、`ratio < −progressBand` → `aheadOfSchedule`、`ratio > progressBand` → `slowerPace`。
- 起点より前の日は起点の体重を返す。
- 最初の1か月(`settlingIn`)は計画の開始日(`roadmap.startDay`)から `initialPeriodDays` 未満、ステージ1だけ。ステージ1で計画見直しを採用して起点を取り直しても再発しない。ステージ2以降は起点の日から判定する。判定 API が `roadmap` を受け取るのは、この開始日と設定値のため。

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
- `targetWeight` は 0.1kg に丸めて保存する(BMI から計算した 67.375 も 67.4 になる)。
- `startWeight <= targetWeight` のときは `stages` が空(計画を作れない)。
- 到達予定日: ステージ k の減量日数 = `ceil(ln(boundary_k / boundary_{k−1}) / ln(1 − monthlyRate) × daysPerMonth)`。ステージ 2 以降は、前のステージの維持期間として `settings.assumedMaintenanceDays` を足す(03-decisions.md #1)。最終ステージの後には足さない。
- 到達判定: `Weight.rounded(sevenDayAverage) <= boundaryWeight`。
- `PlanSettings` に `assumedMaintenanceDays = 60` を追加する。テストもこの定数を参照する(03-decisions.md #1)。
- フェーズの遷移と到達予定日の計算し直しは 2b を参照。

## 6. 実績ペース: `ActualPace`

```swift
public struct ActualPace {
    public var monthlyRate: Double
    public var windowDays: Int
    /// 減量中だけ。データ不足なら nil
    public init?(endingOn day: CalendarDay, phase: PlanPhase, weights: [DailyWeight], roadmap: Roadmap)
    public func isTooFast(settings: PlanSettings) -> Bool
}
```

- `now = SevenDayAverage(day)`、`then = SevenDayAverage(窓の始まりの日)`。どちらかが `nil` なら `nil`。
- 窓の始まりの日は `max(day − actualPaceWindowDays, 下限の日)`。下限の日はステージ1なら「計画の開始日 + `actualPaceWindowStartFloor`(13)」(14日目。初期の水分減少を含めない。03-decisions.md #5)、ステージ2以降はステージの起点の日(#9 の補足)。ステージ1の下限は計画の開始日が基準なので、計画見直しで起点を取り直しても窓は狭まらない。窓の日数 n は、ステージ1では 31日目で 17、42日目で 28。ステージ2以降では経過1日で 1、経過28日で 28。
- ステージ1で計画の開始日から `initialPeriodDays`(30)未満は `nil`(最初の1か月は判定しない)。ステージ2以降に除外はない。
- `monthlyRate = Pace.monthlyRate(ratio: now / then, overDays: n)` = `1 − (now / then)^(daysPerMonth / n)`(03-decisions.md #4)。戻り値は `monthlyRate` と `windowDays` を持つ構造体。
- `isTooFast = Ratio.rounded(monthlyRate) > fastPaceMonthlyLimit`。ちょうど3%は速すぎではない。
- **`Pace`**: 「月」の定義を1か所にまとめる型。`Guideline` の日割りと `ActualPace` の月換算は互いに逆関数になる(`Guideline` で28日後の目安を出し、その比を `Pace.monthlyRate` に通すと `monthlyRate` に戻る)。これをテストで確認する。

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
- 卒業は到達日から `maintenanceMaxDays`(84)以内に限る。84日以内に卒業しなければ `exceededMaximum` になり、その後に28日連続を満たしても自動では卒業しない(次へ進むか維持を続けるかはユーザーが選ぶ)。連続日数は表示用に数え続ける。

## 8. 計画見直しの発動: `PlanReviewTrigger`

```swift
public enum PlanReviewTrigger {
    public static func shouldPropose(phase: PlanPhase, through day: CalendarDay,
                                     weights: [DailyWeight], roadmap: Roadmap) -> Bool
}
```

- 減量中だけ。`day` から遡って `reviewWindowDays`(14)日の各日について、7日平均と計画値(`Guideline.expectedWeight(phase:on:)`)の差の割合を `Ratio.rounded` し、`|ratio| >= reviewDeviation`(2%) なら「ずれている」。分母は計画値。
- 14日すべてがずれていたら `true`。7日平均が `nil` の日、ステージの起点より前の日、ステージ1の最初の1か月(計画の開始日基準)に入る日が窓にあれば `false`。ステージ1で見直しを採用した後は、新しい起点から14日で再び提案できる。上下どちらのずれも対象(03-decisions.md #6)。
- 見直しの採用は `phase.rebased(sevenDayAverage:on:)` で起点を取り直し、`roadmap.rescheduled(from:)` で到達予定日を計算し直す。境界は変えない。

## 9. 最初の1か月(案A)

- `PlanSettings.initialPeriodDays = 30` を追加。経過日数が 30 未満(1〜30日目)は「最初の1か月」。
- `ProgressJudgment` に `.settlingIn` を追加し、`judge(sevenDayAverage:guideline:daysElapsed:settings:)` は経過日数が `initialPeriodDays` 未満ならこれを返す。
- `PlanReviewTrigger` は窓の14日すべてが経過30日以降でなければ `false`(最短で44日目に発動)。
- `ActualPace` は経過30日未満で `nil`、窓の始まりは経過13日(14日目)より前にしない(上記 6)。
