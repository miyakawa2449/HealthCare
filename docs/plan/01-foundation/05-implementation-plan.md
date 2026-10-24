# フェーズ1 実装計画

作成日: 2026-10-24
状態: **承認済み**(2026-10-24、3件とも推奨どおり)

03-decisions.md と 04-open-questions.md の回答を反映した、実装直前の計画。
01-structure.md と 02-commands.md の内容を前提にし、変わった点だけここに書く。

## 前提の訂正(2026-10-24 に再確認)

| 項目 | 2026-10-19 の記述 | 今回の確認結果 |
| --- | --- | --- |
| テスト用シミュレーター | iPhone 16 Pro, OS=26.5 | **iPhone 16 Pro は iOS 18.1 / 18.6 にしかない。** iOS 26.5 には iPhone 17 Pro / 17 / 17e / Air / 13 がある。最低 iOS が 26.0 なので、`iPhone 17 Pro, OS=26.5` を使う |
| XcodeGen | 未インストール | 変わらず未インストール(`brew install xcodegen` を実行する。決定事項 #10) |
| Xcode / Swift | 27.1 / 6.4 | 変わらず |

## 変更するファイル

01-structure.md のとおり。決定事項で確定した値を埋めると次のようになる。

| ファイル | 内容 | 決定事項 |
| --- | --- | --- |
| `project.yml` | ターゲット `WeightApp`(iOS app)と `WeightAppTests`。Bundle ID `com.miyakawa.weightapp`、最低 iOS 26.0、Swift 6 言語モード、Team ID `VC9862P72J`、Automatic signing、iPhone のみ、縦向きのみ、開発言語 ja。ローカルパッケージ `WeightCore` を参照。スキーム `WeightApp` のテストに `WeightAppTests` と `WeightCore/WeightCoreTests` の両方を含める | #2 #3 #4 #6 |
| `WeightApp/App/WeightApp.swift` | `@main`、WindowGroup に ContentView | |
| `WeightApp/App/ContentView.swift` | `Text("今日の体重")` のみ | |
| `WeightApp/Resources/Info.plist` | `NSHealthShareUsageDescription` = 確定文言(AGENTS.md に記載)。`NSHealthUpdateUsageDescription` は入れない | #9 |
| `WeightApp/WeightApp.entitlements` | `com.apple.developer.healthkit` = true、`com.apple.developer.healthkit.background-delivery` = true | #8 |
| `WeightAppTests/WeightAppTests.swift` | 下記のテスト2件 | #5 |
| `WeightCore/Package.swift` | swift-tools-version 6.0、ターゲット `WeightCore` / `WeightCoreTests`、Swift 6 言語モード | #5 #6 |
| `WeightCore/Sources/WeightCore/PlanSettings.swift` | 閾値を1か所にまとめる設定値の型(下記「確認したいこと」#1) | |
| `WeightCore/Tests/WeightCoreTests/PlanSettingsTests.swift` | 下記のテスト | #5 |
| `README.md` | セットアップ手順、確認コマンド、実機でしか確認できないこと、次フェーズで HealthKit に要求する型(bodyMass、bodyFatPercentage) | |
| `.gitignore` | 作成済み(10/24)。`*.xcworkspace`、`*.xcresult`、`Package.resolved` を追加済みなので変更なし | |

## 追加するテスト(先に書く)

すべて Swift Testing(`import Testing`)。XCTest は使わない。

### WeightCoreTests(`swift test` で動く)

| テスト | 確かめること |
| --- | --- |
| `標準ペースは月2%` | `PlanSettings.default.monthlyRate == 0.02` |
| `安全性判定の閾値は週0.5%と1%` | `weeklySafeLimit == 0.005`、`weeklyCautionLimit == 0.01` |
| `ステージ幅は10%、最初のマイルストーンは5%` | `stageRatio == 0.10`、`firstMilestoneRatio == 0.05` |
| `維持期間は最低4週・最長12週、範囲は±2%` | `maintenanceMinDays == 28`、`maintenanceMaxDays == 84`、`maintenanceBand == 0.02` |
| `進み具合の帯は±0.5%、見直しは2%ずれ14日` | `progressBand == 0.005`、`reviewDeviation == 0.02`、`reviewWindowDays == 14` |
| `実績ペースの窓は28日、速すぎの上限は月3%` | `actualPaceWindowDays == 28`、`fastPaceMonthlyLimit == 0.03` |
| `1か月は30日固定` | `daysPerMonth == 30` |
| `最終目標の初期値は BMI22` | `defaultTargetBMI == 22` |

ロジック(計算や判定)はこのフェーズでは書かない。値の読み出しだけを確かめる。

### WeightAppTests(`xcodebuild test` で動く)

| テスト | 確かめること |
| --- | --- |
| `アプリモジュールが読み込める` | `ContentView()` が生成できる |
| `HealthKit の説明文が確定文言と一致する` | `Bundle.main` の `NSHealthShareUsageDescription` が AGENTS.md の文言と完全一致する |

## 実装の順番

1. `brew install xcodegen`(承認をもらってから実行)
2. `WeightCore/Package.swift` と `PlanSettingsTests.swift` を書き、`swift test` が**コンパイルエラーで失敗**することを確認
3. `PlanSettings.swift` を書き、`swift test` が通ることを確認
4. `project.yml`、`Info.plist`、`entitlements`、`WeightApp.swift`、`ContentView.swift`、`WeightAppTests.swift` を書く
5. `xcodegen generate` → `xcodebuild build` → `xcodebuild test`
6. シミュレーターで起動し「今日の体重」の画面が出ることを確認
7. `git status --short` で生成物が無視されていることを確認
8. README.md を書く
9. Codex へのレビュー依頼をまとめる

コミットは「WeightCore の雛形」「アプリ本体と project.yml」「README」の3つに分ける。ブランチは `feature/phase1-foundation`。

## 確認方法

02-commands.md のコマンドを、シミュレーター名を直して使う。

```sh
brew install xcodegen
cd WeightCore && swift test && cd ..
xcodegen generate
xcodebuild -project WeightApp.xcodeproj -scheme WeightApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
xcodebuild -project WeightApp.xcodeproj -scheme WeightApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
xcrun simctl boot "iPhone 17 Pro" ; xcrun simctl launch booted com.miyakawa.weightapp
git status --short
```

| 確認 | 期待する結果 |
| --- | --- |
| `swift test` | PlanSettingsTests 8件が通る |
| `xcodebuild test` | WeightAppTests 2件 + PlanSettingsTests 8件が通る |
| `simctl launch` | 「今日の体重」の文字だけの画面 |
| `git status --short` | `WeightApp.xcodeproj`、`.DS_Store`、`.build` が出ない |

### 実機でしか確認できないこと(今回は未確認のまま進める)

- `healthkit.background-delivery` entitlement を付けた状態で実機に署名・インストールできること
- HealthKit の権限ダイアログに確定文言が表示されること(シミュレーターにもダイアログは出るが、今回は権限要求のコードを書かないので出ない)

## 確認したいこと

### 1. PlanSettings をこのフェーズで入れてよいか(推奨: 入れる)

- 01-structure.md では「空の public 型を1つ(ロジックなし)」としていた。
- 推奨案: 空の型の代わりに、AGENTS.md の「数値の閾値はハードコードを避け、1か所の設定値にまとめる」を満たす `PlanSettings` を置く。値を持つだけでロジックは持たない。
- 理由: 雛形テストが「パッケージが読める」だけだと TDD として意味が薄い。設定値なら AGENTS.md の表をそのままテストの期待値にでき、フェーズ2のロジックはこの型を引数に取る形で書き始められる。
- 代替案: 01-structure.md のとおり空の型にして、PlanSettings はフェーズ2で入れる。
- 回答: 推奨どおり(2026-10-24)

### 2. ブランチ運用(推奨: feature ブランチ + main へマージ)

- 推奨案: `feature/phase1-foundation` で作業し、Codex のレビュー後に main へマージする(PR を使うか、ローカルで fast-forward するかはお任せ)。
- 代替案: main に直接コミットする(個人開発なので手間を減らす)。
- 回答: 推奨どおり(2026-10-24)

### 3. シミュレーターを iPhone 17 Pro に変えてよいか(推奨: 変える)

- 上の「前提の訂正」のとおり。02-commands.md の記述を直す。
- 回答: 推奨どおり(2026-10-24)

## 新しく足す文言

| 文言 | 使う場所 |
| --- | --- |
| 「体重と体脂肪率を Apple ヘルスケアから読み取り、7日平均とレポートの作成に使います。データは外部のサーバーに送信しません。」 | HealthKit の権限ダイアログ(Info.plist) |

ContentView の「今日の体重」はデザインの見出しの流用なので数えない。
