# 作業日報 2026-10-24 フェーズ3: データ層(HealthKit 連携と永続化)+ WeightCore の追補

担当: Claude Code(実装)、Codex(レビュー)、人間(判断・承認)
ブランチ: `feature/phase3-data-layer`(push 済み。main へのマージは承認待ち)
前の作業: [2026-10-24-phase2-core-logic.md](2026-10-24-phase2-core-logic.md)

## 今日やったこと(時系列)

| 作業 | コミット |
| --- | --- |
| フェーズ2の追加回答(提案3件採用、実績ペースの最低窓、ステージ1だけの除外を了承)を AGENTS.md / concept.md に反映し、フェーズ3の計画を提出 | 0a4d717 |
| 03-decisions.md の8件に回答をもらい記録 | 70e2abf |
| A. WeightCore の追補(最低窓、維持中の一言、早期到達、体脂肪率、初回設定の初期値)を TDD で実装(122件) | 075f6b6 |
| B. アプリのデータ層(カレンダー、変換、HealthStore + モック、PlanStore、DailySummaryBuilder、HomeModel、ContentView) | 70c7edd, ff2bf01, dffb63e |
| Codex レビュー 1回目 → 指摘5件を修正 | 881600e |
| Codex レビュー 2回目 → 指摘1件(schemaVersion の先行判定)を修正 | 611b607 |
| Codex レビュー 3回目 → 問題なし、マージ可 | |

## 決めたこと(フェーズ3の 03-decisions.md)

- 体脂肪率も今回読む。1日の値の決定は `DailySampleResolver` に汎用化。
- 保存先は App Group のコンテナ。JSON に schemaVersion を入れる(将来の AI 分析などの項目追加に備える)。
- バックグラウンド受信は入れず、フォアグラウンド復帰時の再取得だけ(ヘルスケアへの反映は HealthPlanet を開いたときなので足りる)。受信はウィジェットのフェーズ。
- ContentView には 7日平均と当日の数値だけ。HealthPlanet の Bundle ID はデバッグビルドでコンソールに出力して確認。
- 早期到達の提案を断ったら14日後に再提案。85日目のカードと重なったらカードを優先。
- 取得期間は計画があれば開始日の6日前から、なければ当日を含む30日。

## 作ったもの

```
WeightCore
  ActualPace                 窓が14日未満なら nil
  MaintenanceNotice.swift    MaintenanceNoticeJudgment(範囲外14日の一言)、EarlyArrivalProposal(断った日から14日)
  Roadmap                    earlyArrival / phaseOnEarlyArrival
  DailyWeight.swift          MeasurementSample、DailySampleResolver、BodyFatSample、DailyBodyFat、DailyBodyFatResolver、InitialWeightSuggestion
  PlanSettings               actualPaceMinimumWindowDays / maintenanceNoticeDays / earlyArrivalRetryDays
WeightApp/Data
  AppCalendar                Asia/Tokyo 固定。CalendarDay → その日の0時
  HealthSampleMapper         HKQuantitySample → WeightSample / BodyFatSample。Bundle ID → SampleSource
  HealthStore                プロトコル、MockHealthStore(actor、エラー注入)、HealthKitStore
  PlanStore                  PlanRecord(schemaVersion)、App Group、スキーマ判定を本体より先に
  DailySummary               DailySummary / PlanStatus / DailySummaryBuilder
WeightApp/App
  HomeModel                  起動時と復帰時に refresh。失敗時は前回の値を残す
  ContentView / WeightApp    7日平均(大)と今日の測定(小)。モデルは App が1つ持つ
WeightApp.entitlements       App Group を追加
```

## 確認結果

| 確認 | 結果 |
| --- | --- |
| `swift test` | 122件通過(17スイート) |
| `xcodebuild test`(iPhone 17 Pro, iOS 26.5) | アプリ25件 + WeightCore 122件通過 |
| シミュレーター起動 | HealthKit の権限ダイアログが出て、読み取りは体脂肪率と体重の2つだけ、確定した説明文が表示される |
| Codex レビュー | 1回目 高1・中3・低1 → 修正。2回目 中1 → 修正。3回目 問題なし、マージ可 |
| 実機(iPhone 12 Pro) | 権限を許可後、7日平均と今日の測定が表示された(17:01)。App Group を含む署名も通った |

## 計画からの逸脱(意図的、設計書に追記済み)

- `DailySummaryBuilder.build` は計画がなくても 7日平均と当日を返す(計画の判定だけ nil)。初回設定の UI がまだないため、実機で読み取りを確認するにはこれが要る。
- App Group が取れないときの退避先は作らない(1回目の実装では Application Support に退避していたが、Codex の指摘で「後で見えなくなる」ため廃止)。

## Codex の指摘と対応

1. **(高)当日の7日平均がないと維持期間の判定が走らない。** 85日目のカードが出なくなる。平均が要るのは進み具合と早期到達だけなので、それ以外は常に評価するよう修正。
2. **(中)復帰時に View を作り直していて前回の値が残らない。** モデルを App が1つ持ち、refresh だけ呼ぶ構成に変更。失敗の状態も持つ。
3. **(中)退避先は承認済み仕様にない。** 廃止し、利用不可として扱う。
4. **(中)schemaVersion を読み込み時に検証していない。** 検証を追加。2回目で「本体より先に読む」よう再修正。
5. **(低)直近30日が31日になっていた。** day − 29 に修正。

## つまずいたことと学び

1. **「当日の平均がない」ケースの見落とし。** 判定を1つの guard でまとめて早期 return すると、履歴で決まる判定(維持期間の85日)まで止まる。判定ごとに「何が要るか」を分けて条件にする。
2. **SwiftUI の `.id()` でモデルごと作り直していた。** 復帰時の再取得を `.id(token)` で実装すると状態が消える。モデルは親(App)が持ち、子は参照だけにする。
3. **「黙って退避する」は仕様外の判断。** 動くようにしたつもりでも、承認済みの設計から外れる。失敗は失敗として見せる(フェイルクローズ)方が、後の移行で困らない。
4. **スキーマのバージョンは本体より先に読む。** 全体をデコードしてから検証すると、項目が変わった将来の JSON では DecodingError が先に出てバージョンのエラーにならない。
5. **維持中の一言のテストは日数の暗算で4件間違えた。** 7日平均が範囲外になるのは「外れた値が何日入ったか」で決まり、値によって(114.0 は6日、108.0 は4日)違う。期待値は Python で判定を再現して出した。
6. **アプリ側のテストは「赤の確認」を省いた。** ビルドに1分かかるので、テストと実装をまとめて書いて1回で回した。WeightCore は赤を確認してから実装している。

## 実機で起きたこと

- 初回の実機ビルドで「No Account for Team "VC9862P72J"」「No profiles for 'com.miyakawa.weightapp'」が出た。Mac に署名証明書はあったが、Xcode の Accounts にその Team の Apple ID が入っていなかったのが原因。アカウントを追加して Team を選び直したら解消した(コードの変更なし)。

## 残っていること

- main へのマージ(承認待ち)。
- HealthPlanet の Bundle ID をコンソールの `[HealthKit] ... sources:` の出力から控え、`DataSourceSettings.healthPlanetBundleIDs` に入れる。
- 7日平均の日数下限は実機で使ってから決める。

## 次にやること

フェーズ4(画面): 初回設定(開始体重の確認・修正、最終目標、ロードマップ作成)、ホーム(デザインどおり)、カード(最初の1か月、計画見直し、85日目、早期到達、維持中の一言)、文言の確定。
