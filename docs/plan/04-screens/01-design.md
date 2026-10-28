# 画面と型の設計案

元: `docs/design/concept_design.pdf` 1枚目(ホーム)、`docs/concept.md`「画面と表示ルール」、AGENTS.md「コンセプト上の制約」。
デザインにある数値(123.5、117.3 など)は見た目の例示で、テストの期待値には使わない。

## 0. 画面の振り分け(`RootView`)

`WeightApp` が持つ `HomeModel` の状態で分ける。上から順に判定する。

| 状態 | 画面 | 判定 |
| --- | --- | --- |
| ヘルスケアが使えない / 保存先が取れない | `UnavailableView`(文言だけ) | `isUnavailable` |
| 最初の取得がまだ終わっていない | 空の背景に `ProgressView`(文字なし) | `!hasRefreshed` |
| 最初の取得に失敗して値がない | `UnavailableView`(読み取れなかった旨の文言) | `summary == nil && lastRefreshFailed` |
| 計画がない | `SetupView` | `summary.plan == nil` |
| 計画がある | タブ(`HomeView` / ロードマップ / レポート) | それ以外 |

- `PlanStore.load()` が投げたとき(スキーマ違い、壊れた JSON)は `lastRefreshFailed` になり、初回設定には進まない(上書きして計画を消さない)。
- `hasRefreshed` は最初の `refresh()` が終わったら true。失敗でも true。
- タブは3つ。ロードマップとレポートは1行の文言だけの画面(03-decisions.md #5)。

## 1. 初回設定(`SetupView`)

計画がないときに出る。1画面で完結させる(ステップ分けはしない)。

```
はじめる                                  ← 見出し

開始体重
  [ 123.5 ] kg
  直近7日間の平均を入れてあります。違っていれば直してください。   ← 初期値の出どころで変わる(04-wording.md)

身長
  [ 175 ] cm
  最終目標の初期値を決めるためだけに使います。

最終目標
  [ 67.4 ] kg
  BMI 22 の体重を入れてあります。

この計画で始める                          ← ボタン
  開始日は今日(10月28日)。最初の区切りは 117.3 kg です。   ← 要約。最終目標はここに入力があるので表示してよい
```

- 開始体重の初期値: `InitialWeightSuggestion.suggest(on: today, weights: summary.history の体重)`。
  直近7日に1日でもあれば7日平均、なければ取得範囲(直近30日)の最新値、それもなければ空欄(文言は「ヘルスケアに体重の記録がないので、いまの体重を入れてください」)。
- 身長の初期値は `PlanSetup.defaultHeightCentimeters = 175`(設定値)。身長を変えると最終目標の初期値を計算し直す。ただし最終目標を手で直したあとは上書きしない。
- 最終目標の初期値: `PlanSetup.defaultTargetWeight(heightCentimeters:settings:)` = BMI × (身長m)²。`Roadmap.init` が 0.1kg に丸める(175cm → 67.4)。
- 身長は保存しない(最終目標の初期値を決めるためだけ。BMI は画面に出さない方針なので、保存しても使い道がない)。
- 検証: `PlanSetup.validate(startWeight:targetWeight:)`。開始体重と最終目標が正の数で、開始体重 > 最終目標。違えばボタンを無効にして理由を1行で出す(04-wording.md)。範囲の上限・下限は設けない(個人用)。
- 「この計画で始める」で `HomeModel.startPlan(startWeight:targetWeight:)`:
  `Roadmap(startWeight:startDay: 今日(Asia/Tokyo), targetWeight:settings: .default)` → `PlanRecord(roadmap:phase: roadmap.initialPhase, originalRoadmap: nil, declinedEarlyArrivalOn: nil)` → `PlanStore.save` → `refresh()`。
  保存に失敗したら初回設定にとどまり、文言を1行出す。
- 開始体重は入力値をそのまま `Roadmap.startWeight` にする(丸めは `Roadmap` 内の境界計算に任せる)。入力は小数第1位まで。

## 2. ホーム画面(`HomeView`)

縦スクロール。背景は薄い色、カードは白(ダークモードは 03-decisions.md #8)。

### 2.1 見出し

```
10月18日(日)            ← summary.day を「M月d日(E)」。曜日は日本語1文字
今日の体重
```

取り直しに失敗して前回の値を出しているときは、見出しの下に小さく「最新の値を読み取れませんでした。前回の値を表示しています。」

### 2.2 7日平均カード(`WeightCard`)

```
直近7日間の平均
123.5 kg                        ← 大。Weight.rounded を "%.1f"
今日の測定 123.5 kg ・ 17:47     ← 小。当日の値がなければ「今日はまだ測っていません」
[グラフ]                        ← 7日平均の実線と計画の点線。軸の目盛りや数値は出さない
── 7日平均  --- 計画             ← 凡例
点線の近くにいれば順調です。日々の上下は気にしなくて大丈夫。
```

- 7日平均が出ない(直近7日に記録がない)ときは、数値の代わりに「直近7日間に記録がありません」、その下に「HealthPlanet で同期すると、ここに表示されます」。グラフは履歴があれば出す。
- グラフ(`WeightChart`、Swift Charts): 直近 `HomeSettings.chartDays`(28日。03-decisions.md #2)の `history` を使う。
  - 実線: 各日の7日平均(`DailyPoint.sevenDayAverage`)。nil の日は線を切る。
  - 点線: 各日の計画値(`DailyPoint.guideline`)。**今のフェーズの起点より前の日は nil にして描かない**(前のフェーズの計画値を今のフェーズの式で描くと嘘になるため)。維持期間・維持モードでは到達時体重の水平な点線。
  - 軸のラベル、目盛り、グリッドは出さない(ホームに目安の数値を出さない方針。concept.md「メイン画面では数字の目安を出さず、点線で重ねるだけ」)。y の範囲は実線と点線の最小・最大に少し余白を足す。
  - 点が1つしかない(計画初日)ときは点だけを打つ。

### 2.3 ステージカード(`StageCard`)

フェーズで中身を変える。ステージ番号は `plan.stageNumber`(保存したフェーズの番号。体重から逆算しない)。

**減量中(`.losing`)**

```
ステージ1                     最初の区切り      ← 右上の小さな見出し
117.3 kg をめざしています
[━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━]           ← 進み具合のバー
123.5 kg からスタート         到達予定 2027年1月上旬
最初の1か月は、体の水分が落ち着く時期です        ← 進み具合の一言(2.3.1)
```

| 項目 | ステージ1で最初の区切りの前 | それ以外の減量中 |
| --- | --- | --- |
| 右上 | 最初の区切り | 次の区切り |
| めざす体重 | `roadmap.firstMilestoneWeight` | `stages[k-1].boundaryWeight` |
| スタート | ステージの起点の体重 `phase.origin.weight`(丸め) | 同じ |
| 到達予定 | `roadmap.firstMilestoneEstimatedArrival(from: phase)` | `stages[k-1].estimatedArrival` |
| バー | (起点 − 7日平均) ÷ (起点 − めざす体重) を 0〜1 に収める。7日平均がなければ 0 | 同じ |

- 「最初の区切りの前」= `stageNumber == 1` かつ `record.firstMilestoneReachedOn == nil`(03-decisions.md #3)。
- 到達予定の表示は `DisplayFormat.approximateDate`: 1〜10日「上旬」、11〜20日「中旬」、21日〜「下旬」。年は常に付ける。
- 最終ステージでも「次の区切り」と `boundaryWeight`(= 最終目標)を出す。ホームに最終目標の値が出るのは最終ステージに入ってからだけで、そのときは「次の区切り」と同じ扱い(03-decisions.md #4)。

**維持期間(`.maintaining`)**

```
ステージ1                     維持期間
111.2 kg を保つ期間です            ← 到達時体重(丸め)
到達から 12日目                    ← arrival.day から数えて当日が何日目か(到達日 = 1日目)
減らした体重に、体と生活を慣らす時期です
```

- 範囲内の連続日数(28日のカウント)は出さない。外れると数え直しになり、失敗に見えるため。
- バーは出さない(期限を連想させるため)。

**維持モード(`.maintenanceMode`)**

```
維持                          維持モード
67.4 kg を保っています
到達 2029年2月3日
```

- ステージ番号は nil なので左上は「維持」。

#### 2.3.1 進み具合の一言(減量中だけ)

`plan.progress` から1行。評価ラベルではなく、状態を穏やかに伝える言葉(04-wording.md)。

| `ProgressJudgment` | 文言 |
| --- | --- |
| `.settlingIn` | 最初の1か月は、体の水分が落ち着く時期です |
| `.onTrack` | 計画どおりに進んでいます |
| `.aheadOfSchedule` | 予定より少し早いペースです |
| `.slowerPace` | ゆっくりしたペースで進んでいます |
| nil(7日平均がない) | 出さない |

実績ペース(月3%超)の一言はカードのフェーズ5で扱う。このフェーズでは `actualPace` を画面に使わない。

### 2.4 今週の記録カード(`WeekRecordCard`)

```
今週の記録
 月   火   水   木   金   土   日
(12) (13) (14) (15) (16) (17) [18]
記録した日に印がつきます。途切れても、また今日から。
```

- 週は月曜始まり、`summary.day` を含む週(Asia/Tokyo)。
- 印: `history` にその日の体重があれば塗りつぶし。今日は枠を強調。今日より後の日は薄く出す。
- 連続日数や「何日記録した」の数は出さない(レポートのフェーズ6で「記録できた日」として出す)。

### 2.5 出さないもの(確認用)

体脂肪率、除脂肪量、BMI、最終目標(最終ステージを除く)、目安の数値、評価ラベル、赤色、連続記録の数、実績ペースの数値。

## 3. 型と責務

### A. WeightCore

```swift
public enum PlanSetup {
    public static let defaultHeightCentimeters = 175.0
    /// BMI × 身長(m)²。丸めない(Roadmap が丸める)
    public static func defaultTargetWeight(heightCentimeters: Double, settings: PlanSettings) -> Double
    public enum ValidationError: Error, Equatable { case startWeightNotPositive, targetWeightNotPositive, targetNotBelowStart }
    public static func validate(startWeight: Double, targetWeight: Double) -> ValidationError?
}

extension Roadmap {
    /// 7日平均(丸め)が最初の区切り以下
    public func hasReachedFirstMilestone(sevenDayAverage: Double) -> Bool
    /// ステージ1の減量中だけ。起点から月2%で最初の区切りに届く予定日。起点が区切り以下なら起点の日。それ以外のフェーズは nil
    public func firstMilestoneEstimatedArrival(from phase: PlanPhase) -> CalendarDay?
}

extension SevenDayAverage {
    /// from〜to の各日の7日平均(その日に終わる窓)。出ない日は nil
    public static func series(from: CalendarDay, to: CalendarDay, in weights: [DailyWeight]) -> [(day: CalendarDay, average: SevenDayAverage?)]
}
```

### B. アプリ本体

```swift
// Data/DailySummary.swift
struct DailyPoint: Equatable {
    var day: CalendarDay
    var weight: DailyWeight?          // その日の記録(カレンダーの印)
    var sevenDayAverage: Double?      // グラフの実線
    var guideline: Double?            // グラフの点線。計画がない、または今のフェーズの起点より前は nil
}
struct DailySummary {
    …既存…
    /// day を含む直近 HomeSettings.historyDays 日(古い順)
    var history: [DailyPoint]
}

// App/HomeSettings.swift(表示に関する設定値。閾値と同じく1か所に)
enum HomeSettings {
    static let historyDays = 28       // グラフと記録カレンダーが使う履歴の日数
}

// Data/PlanStore.swift
struct PlanRecord {
    …既存…
    /// 最初の区切り(5%)に到達した日。到達後は戻らない。schemaVersion は 1 のまま(項目の追加だけで、古い JSON は nil として読める)
    var firstMilestoneReachedOn: CalendarDay?
}

// App/HomeModel.swift
final class HomeModel {
    …既存…
    private(set) var hasRefreshed = false
    /// 初回設定の初期値。summary の履歴から InitialWeightSuggestion
    var suggestedStartWeight: Double? { get }
    var suggestionKind: SuggestionKind  // .sevenDayAverage / .latest / .none(文言の出し分け)
    func startPlan(startWeight: Double, targetWeight: Double) async throws
    // refresh() の最後: 減量中ステージ1で firstMilestoneReachedOn == nil、7日平均(丸め)が区切り以下なら保存して summary を作り直す
}

// App/DisplayFormat.swift
enum DisplayFormat {
    static func kilograms(_ value: Double) -> String            // "123.5 kg"
    static func dayWithWeekday(_ day: CalendarDay) -> String     // "10月18日(日)"
    static func fullDate(_ day: CalendarDay) -> String           // "2029年2月3日"
    static func time(_ date: Date) -> String                     // "17:47"(Asia/Tokyo)
    static func approximateDate(_ day: CalendarDay) -> String    // "2027年1月上旬"
    static func weekdaySymbol(_ day: CalendarDay) -> String      // "月"
}

// App/AppTheme.swift
enum AppTheme { static let accent: Color; static let background: Color; static let card: Color; static let secondaryText: Color; static let track: Color }
```

- `DailySummaryBuilder` は取得範囲を変えない(計画があれば開始日の6日前から、なければ直近30日)。`history` は取得した範囲のうち直近 `historyDays` 日だけを切り出す。
  計画の開始直後は取得範囲が短いので、`history` は「取得範囲の始まり」と「day − 27」の遅い方から始める。
- 画面は `HomeModel` を見る `HomeScreen`(薄い)と、`DailySummary` と `PlanRecord` の一部を受け取る `HomeView`(純粋)に分ける。`#Preview` は AGENTS.md のとおり `MockHealthStore` と一時ディレクトリの `PlanStore` から `HomeModel` を作って渡す(`PreviewData` に状態ごとの作り方をまとめる)。

## 4. 色と見た目

- アクセント: 深い緑(デザインの `#2E6B5E` 付近)。文字と線に使う。
- 背景: ごく薄い灰緑。カード: 白、角丸 16、影なし。
- 赤・橙・黄の警告色は `AppTheme` に定義しない。
- 大きな数値は `.rounded` デザインの太字。

## 5. フェーズ5への引き継ぎ

- フェーズの遷移(到達、卒業)と各カードは、`HomeView` の7日平均カードとステージカードの間に差し込む。`HomeView` はそのための `cards: [Card]` の置き場だけ用意しておく(空)。
- `actualPace`、`maintenance`、`maintenanceNotice`、`shouldPropose*` は `DailySummary` にあるが、このフェーズでは画面に使わない。
