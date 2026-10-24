# 型と責務の設計案

## A. WeightCore の追補

### A1. 実績ペースの最低窓

- `PlanSettings.actualPaceMinimumWindowDays = 14` を追加。
- `ActualPace.init?` で、窓の日数 `days < actualPaceMinimumWindowDays` なら `nil`。
- ステージ1は影響なし(窓の下限が計画の開始日 + 13、判定が開始日 + 30 からなので窓は常に 17 日以上)。ステージ2以降と、ステージ2以降で見直しを採用した直後は、起点から 14 日たつまで `nil`。

### A2. 維持中の一言: `MaintenanceNotice`

```swift
public enum MaintenanceNotice: Sendable, Equatable {
    case aboveBand(consecutiveDays: Int)   // 上に外れて続いている
    case belowBand(consecutiveDays: Int)   // 下に外れて続いている
}
public enum MaintenanceNoticeJudgment {
    /// 維持期間・維持モードで、7日平均(丸め)が到達時体重の ±maintenanceBand の外に
    /// maintenanceNoticeDays(14)日連続で続いていれば返す。減量中は nil。
    public static func notice(phase: PlanPhase, through day: CalendarDay, weights: [DailyWeight], settings: PlanSettings) -> MaintenanceNotice?
}
```

- 到達日から `day` まで1日ずつ見て、範囲外(上/下)の連続日数を数える。範囲内の日と7日平均が出ない日で 0 に戻す。上と下が入れ替わったら数え直す。
- 連続日数が `maintenanceNoticeDays` 以上なら返す。
- 85日目の提案カードとの優先は、判定ではなく表示側で決める(`MaintenanceState.exceededMaximum` が出ていればカードを優先)。判定はそれぞれ独立に返す。
- `PlanSettings.maintenanceNoticeDays = 14` を追加。

### A3. 維持中の早期到達

```swift
extension Roadmap {
    /// 維持期間中に、7日平均(丸め)が次のステージの境界以下なら次のステージ番号。それ以外は nil。
    public func earlyArrival(phase: PlanPhase, sevenDayAverage: Double) -> Int?
    /// 早期到達を採用した日のフェーズ。次が最終ステージなら維持モード、それ以外は次のステージの維持期間。
    public func phaseOnEarlyArrival(from phase: PlanPhase, sevenDayAverage: Double, on day: CalendarDay) -> PlanPhase?
}
```

- `earlyArrival` は `.maintaining(stage: k)` で `k < stages.count` かつ `Weight.rounded(avg) <= stages[k].boundaryWeight` のとき `k + 1`。維持モードでは nil(次の境界がない)。
- `phaseOnEarlyArrival` は `phaseOnArrival(stage: k + 1, ...)` と同じ遷移。予定日の更新はアプリ側が `rescheduled(from:)` を呼ぶ。
- 「維持を続ける」を選んだ場合はフェーズを変えない。断った日を保存し(B3)、その日から14日後にまだ次の境界以下なら再提案する。`EarlyArrivalProposal.shouldPropose(earlyArrival:declinedOn:today:settings:)` を WeightCore に置き、`PlanSettings.earlyArrivalRetryDays = 14` を追加する。85日目の提案カードと重なったらカードを優先する(表示側)。

### A4. 体脂肪率の1日の値: `DailySampleResolver`

- `WeightSample` / `DailyWeight` の仕組みを汎用化する。

```swift
public protocol MeasurementSample: Sendable { var measuredAt: Date { get }; var source: SampleSource { get } }
public struct BodyFatSample: MeasurementSample { var fraction: Double /* 0.0〜1.0 */; var measuredAt: Date; var source: SampleSource }
public struct DailyBodyFat: Sendable, Equatable { var day: CalendarDay; var fraction: Double; var measuredAt: Date; var source: SampleSource }
public enum DailySampleResolver {
    public static func resolve<S: MeasurementSample>(_ samples: [S], calendar: Calendar) -> [(day: CalendarDay, sample: S)]
}
```

- `DailyWeightResolver.resolve` はこの汎用版を呼ぶ薄い関数として残す(既存テストはそのまま通す)。`DailyBodyFatResolver.resolve` を同様に足す。
- 体脂肪率は HealthKit では 0.0〜1.0 の割合。WeightCore でもそのまま割合で持つ(表示で % にする)。
- 除脂肪量 = 体重 × (1 − 体脂肪率) はレポートのフェーズで計算する(今回は値を揃えるところまで)。

### A5. 初回設定の初期値: `InitialWeightSuggestion`

```swift
public enum InitialWeightSuggestion {
    /// 直近7日平均。窓に1件もなければ最新の1件。データがなければ nil
    public static func suggest(on day: CalendarDay, weights: [DailyWeight]) -> Double?
}
```

- 03-decisions.md(フェーズ2)#2 の「7日分ない場合は最新値」は、窓に 1 件でもあれば平均(SevenDayAverage の規則)、窓に 0 件なら最新の 1 件、と解釈する。

## B. アプリ本体のデータ層(`WeightApp/Data/`)

### B6. カレンダー: `AppCalendar`

- `static let tokyo: Calendar`(gregorian、Asia/Tokyo)。WeightCore に渡すカレンダーはこれだけ。`Calendar.current` は使わない。

### B2. 変換: `HealthSampleMapper`、`DataSourceSettings`

```swift
struct DataSourceSettings { static var healthPlanetBundleIDs: Set<String> = [] /* 実機で確認後に入れる */ }
enum HealthSampleMapper {
    static func source(bundleIdentifier: String) -> SampleSource   // 集合に含まれれば .healthPlanet、それ以外 .other
    static func weight(_ sample: HKQuantitySample) -> WeightSample  // kg
    static func bodyFat(_ sample: HKQuantitySample) -> BodyFatSample // 割合
}
```

- Bundle ID が未設定(空集合)の間はすべて `.other` になり、「その日の最初の測定値」だけで決まる。

### B1. HealthKit: `HealthStore`、`HealthKitStore`、`MockHealthStore`

```swift
protocol HealthStore: Sendable {
    func requestReadAuthorization() async throws
    func weightSamples(from: Date, to: Date) async throws -> [WeightSample]
    func bodyFatSamples(from: Date, to: Date) async throws -> [BodyFatSample]
}
```

- `HealthKitStore` は `HKHealthStore` を包み、`HKSampleQuery` で取得して `HealthSampleMapper` で変換する。取得はソートと日付範囲のみで、1日の値の決定は WeightCore に任せる。
- `MockHealthStore` はサンプルの配列を持ち、テストとシミュレーターで使う。
- 読み取る型は `bodyMass` と `bodyFatPercentage` の2つだけ(決定事項 #7)。
- 取得する期間: 計画の開始日の 6 日前から今日まで(7日平均の窓のため)。計画がなければ直近 30 日。

### B3. 永続化: `PlanStore`、`PlanRecord`

```swift
struct PlanRecord: Codable, Equatable {
    var roadmap: Roadmap
    var phase: PlanPhase
    var originalRoadmap: Roadmap?        // 計画見直しを採用したときの「元の計画に戻す」用。採用前は nil
    var declinedEarlyArrivalOn: CalendarDay?  // 早期到達の提案を断った日。その日から14日後に、まだ次の境界以下なら再提案(03-decisions.md #7)
    var schemaVersion: Int               // 1
}
final class PlanStore {
    init(directory: URL)                 // 03-decisions.md #3
    func load() throws -> PlanRecord?
    func save(_ record: PlanRecord) throws
}
```

- JSON(`JSONEncoder` / `JSONDecoder`、ISO8601 ではなく `CalendarDay` の年月日をそのまま)。原子的に書き込む(`.atomic`)。
- `schemaVersion` を持たせ、将来の移行に備える。今回は 1 のみ。読み込み時に検証し、違えば `PlanStoreError.unsupportedSchemaVersion` を投げる(黙って読まない)。
- App Group のコンテナが取れないときは退避先を作らない(別の場所に保存すると、後で App Group が使えるようになったときに見えなくなるため)。`PlanStore.defaultDirectory()` は nil を返し、`HomeModel` が「利用不可」として持つ。

### B4. 集約: `DailySummaryBuilder`、`DailySummary`

```swift
struct DailySummary: Equatable {
    var day: CalendarDay
    var todayWeight: DailyWeight?
    var sevenDayAverage: SevenDayAverage?
    var phase: PlanPhase
    var stageNumber: Int?                   // PlanPhase の番号(体重から逆算しない)
    var guideline: Double                   // 計画値
    var progress: ProgressJudgment?
    var actualPace: ActualPace?
    var maintenance: MaintenanceState?      // 維持期間・維持モードのとき
    var maintenanceNotice: MaintenanceNotice?
    var earlyArrivalStage: Int?
    var shouldProposePlanReview: Bool
}
struct DailySummaryBuilder {
    init(store: HealthStore, planStore: PlanStore, calendar: Calendar, settings: PlanSettings)
    func build(on day: CalendarDay) async throws -> DailySummary   // 計画がなければ plan が nil
}
```

- 実装時の変更: 初回設定の UI がまだないため、計画がなくても 7日平均と当日の体重・体脂肪率は返し、計画の判定だけ `plan: PlanStatus?` を nil にする(`DailySummary` を `todayWeight` / `todayBodyFat` / `sevenDayAverage` / `plan` の形に分けた)。実機で HealthKit の読み取りを確認するため。
- 当日の7日平均が要るのは進み具合と早期到達だけ。維持期間の判定(85日目のカードを含む)、一言、実績ペース、計画見直しは、当日の平均がなくても評価する。
- WeightCore の関数を順に呼ぶだけで、判断を足さない。表示の優先順位(85日目のカード > 一言)は画面のフェーズで決めるので、ここでは両方を返す。
- `stageNumber` は `.losing` / `.maintaining` の番号。維持モードは nil。`stage(containing:)` は使わない。
- 計画がないときの取得期間は「当日を含む30日」(day − 29 の 0 時から)。

### B5. 更新の検知: `HomeModel`

- `HomeModel`(`@MainActor @Observable`)を `WeightApp` が1つだけ持ち、起動時とフォアグラウンド復帰時(`scenePhase == .active`)に `refresh()` を呼ぶ。モデルは作り直さない。
- 取り直しに失敗したら前回の値を残し、`lastRefreshFailed` を立てる(成功で戻す)。HealthKit が使えない、または保存先が取れないときは `isUnavailable`。見せ方と文言はフェーズ4で決める。ヘルスケアへの反映は HealthPlanet を開いたときなので、これで足りる(03-decisions.md #4)。
- `HKObserverQuery` と `enableBackgroundDelivery` はウィジェットのフェーズで入れる。

### ContentView(最小)

- 7日平均(大)と当日の体重(小)を数値で出すだけ。計画がなければ「今日の体重」の文字のまま。評価や色は出さない。
- デザインの再現はフェーズ4。
