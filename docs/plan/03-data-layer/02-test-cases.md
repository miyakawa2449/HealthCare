# テストケースの一覧

## A1. ActualPace の最低窓(ステージ2、起点 2027-05-22、110.9)

| ケース | 入力 | 期待 |
| --- | --- | --- |
| 経過1日 | n = 1 | nil |
| 経過13日 | n = 13 | nil |
| 経過14日 | n = 14 | windowDays 14、30/14 乗 |
| ステージ1は影響なし | 経過30日(n = 17) | windowDays 17(フェーズ2のテストのまま通る) |
| ステージ2で見直しを採用した直後 | 再起点から13日 / 14日 | nil / windowDays 14 |

## A2. MaintenanceNotice(到達 2026-11-01、111.2、範囲 109.0〜113.4)

| ケース | 入力 | 期待 |
| --- | --- | --- |
| 上に14日 | 7日平均が 11-10〜11-23 に 113.5 以上 | aboveBand(14) |
| 13日では出ない | 13日 | nil |
| 下に14日 | 108.9 以下が14日 | belowBand(14) |
| 範囲内の日でリセット | 10日外れ → 1日範囲内 → 13日外れ | nil |
| 7日平均が出ない日でリセット | 10日外れ → データなしの日 → 13日外れ | nil |
| 上下が入れ替わったら数え直し | 上に10日 → 下に10日 | nil(下は10日) |
| 維持モードでも出る | maintenanceMode | aboveBand |
| 減量中は出ない | losing | nil |
| 85日目のカードと同時 | exceededMaximum と aboveBand が両方成立 | 両方返る(優先は表示側) |

## A3. 早期到達(6ステージ、維持中ステージ1、次の境界 100.0)

| ケース | 入力 | 期待 |
| --- | --- | --- |
| 次の境界ちょうど | 7日平均 100.04 → 丸め 100.0 | earlyArrival = 2 |
| 境界の上 | 100.05 → 100.1 | nil |
| 採用 | phaseOnEarlyArrival(維持中1、100.0 @ 2027-04-10) | maintaining(2, 100.0 @ 04-10) |
| 次が最終 | 維持中5、7日平均 67.4 | earlyArrival = 6、採用で maintenanceMode |
| 維持モード | maintenanceMode | nil |
| 減量中 | losing | nil |
| 予定日の更新 | 採用後 rescheduled | ステージ2の予定日 = 04-10、ステージ3 = 04-10 + 60 + 157 |

## A4. DailySampleResolver / 体脂肪率

| ケース | 入力 | 期待 |
| --- | --- | --- |
| 体重の既存テスト | DailyWeightResolver | すべてそのまま通る |
| 体脂肪率: HealthPlanet 優先 | 07:00 0.350(other)、08:00 0.352(healthPlanet) | 0.352 |
| 体脂肪率: 同日は最初 | 08:00 0.352、20:00 0.345 | 0.352 |
| 体脂肪率: 日付境界(JST) | 23:30 と翌 00:30 | 2日 |
| 体重と体脂肪率で日が揃わない | 体重だけの日、体脂肪率だけの日 | それぞれ独立に返る |

## A5. InitialWeightSuggestion

| ケース | 入力 | 期待 |
| --- | --- | --- |
| 7日揃い | 7件 | 平均 |
| 3日分 | 窓に3件 | 3件の平均 |
| 窓に0件、過去にあり | 10日前に 1 件 | その値(最新) |
| データなし | [] | nil |

## B2. HealthSampleMapper

| ケース | 入力 | 期待 |
| --- | --- | --- |
| HealthPlanet の Bundle ID | 集合に含まれる ID | .healthPlanet |
| それ以外 | "com.apple.Health" | .other |
| 未設定 | 空集合 | すべて .other |
| 体重の単位 | 123.5 kg の HKQuantity | 123.5 |
| 体脂肪率の単位 | 35.2% の HKQuantity(percent) | 0.352 |

## B3. PlanStore(一時ディレクトリ)

| ケース | 入力 | 期待 |
| --- | --- | --- |
| 往復 | save → load | 等しい(roadmap、phase、originalRoadmap、declinedEarlyArrivalOn) |
| 未保存 | load | nil |
| 上書き | save 2回 | 後の値 |
| 壊れたファイル | 不正な JSON | エラーを投げる(黙って nil にしない) |

## B4. DailySummaryBuilder(MockHealthStore)

| ケース | 入力 | 期待 |
| --- | --- | --- |
| 計画なし | PlanStore が空 | nil |
| 減量中ステージ1、経過45日 | モックに 50 日分 | sevenDayAverage、guideline、progress、actualPace(windowDays 28)、maintenance nil |
| 維持期間 | phase = maintaining | progress nil、maintenance = inProgress(n)、earlyArrivalStage |
| 当日の体重なし | 今日のサンプルなし | todayWeight nil、sevenDayAverage は過去6日から |
| ステージ番号 | phase の番号 | stage(containing:) と食い違っても phase の番号 |
| 取得期間 | 開始日 − 6 日から今日 | モックが受け取った from/to |

## B6. AppCalendar

| ケース | 期待 |
| --- | --- |
| タイムゾーン | Asia/Tokyo |
| 10-18 08:00 JST(10-17 23:00 UTC) | CalendarDay 10-18 |

## アプリ側の既存テスト

- WeightAppTests の2件はそのまま通す。
