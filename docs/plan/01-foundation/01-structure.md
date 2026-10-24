# 作成するファイルとディレクトリ構成

```
HealthCare/
├── .gitignore
├── README.md
├── project.yml
├── WeightApp/
│   ├── App/WeightApp.swift            @main。WindowGroup に ContentView を置くだけ
│   ├── App/ContentView.swift          Text("今日の体重") のみ(起動確認用。デザインの見出しを流用)
│   ├── Resources/Info.plist           NSHealthShareUsageDescription など(手書きで管理、コミットする)
│   └── WeightApp.entitlements         HealthKit、HealthKit Background Delivery
├── WeightAppTests/
│   └── WeightAppTests.swift           アプリモジュールが読み込めることを確かめる1件
└── WeightCore/
    ├── Package.swift                  swift-tools-version 6.0。WeightCore / WeightCoreTests
    ├── Sources/WeightCore/WeightCore.swift          空の public 型を1つ(ロジックなし)
    └── Tests/WeightCoreTests/WeightCoreTests.swift  雛形テスト1件
```

既存の `AGENTS.md`、`CLAUDE.md`、`docs/`、`kickoff-prompts.md` はそのまま。

## project.yml の要点

- ターゲットは `WeightApp`(iOS application)と `WeightAppTests`(unit-test、ホストは WeightApp)の2つ。
- `WeightCore` はローカル Swift Package として参照し、アプリに依存させる。
- スキーム `WeightApp` のテストに `WeightAppTests` と `WeightCore/WeightCoreTests` の両方を含める。`xcodebuild test` 一発で両方が走る。
- 主な設定
  - Swift 6 言語モード(strict concurrency)
  - iPhone のみ、縦向きのみ
  - 開発言語 `ja`
  - Automatic signing、Team ID は決定事項 #4 のとおり
  - `INFOPLIST_FILE` と `CODE_SIGN_ENTITLEMENTS` は上記の手書きファイルを指す
- `.xcodeproj` は `WeightApp.xcodeproj` としてリポジトリ直下に生成される(コミットしない)。

## entitlements と Info.plist に入れるもの

| ファイル | キー | 値・備考 |
| --- | --- | --- |
| WeightApp.entitlements | `com.apple.developer.healthkit` | `true` |
| WeightApp.entitlements | `com.apple.developer.healthkit.background-delivery` | `true`。iOS 15 以降、バックグラウンド受信に必須。今は使わないが権限設定の一部として入れる(決定事項 #8)。実機でしか確認できない |
| Info.plist | `NSHealthShareUsageDescription` | 読み取りの説明文(決定事項 #9) |
| Info.plist | `NSHealthUpdateUsageDescription` | 書き込みはしないので入れない |

読み取り対象の型(体重 `bodyMass`、体脂肪率 `bodyFatPercentage`)はコード側で要求するものなので、今回はコードを書かない。README に「次フェーズで要求する型」として記す。

## .gitignore の内容

```
*.xcodeproj
xcuserdata/
.build/
.swiftpm/
DerivedData/
.DS_Store
```

## 今回は作らないもの

- UIテストターゲット
- ウィジェットターゲット(後のフェーズ)
- Makefile、CI 設定
