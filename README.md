# WeightApp(仮称)

個人用の体重管理 iOS アプリ。「見せすぎないことで継続させる」を目的にする。
仕様は `docs/concept.md`、開発ルールは `AGENTS.md` と `CLAUDE.md`、フェーズごとの計画は `docs/plan/` にある。

## 構成

| ディレクトリ | 内容 |
| --- | --- |
| `WeightCore/` | Swift Package。UI と HealthKit に依存しない純粋なロジック。`swift test` だけでテストできる |
| `WeightApp/` | SwiftUI のアプリ本体。HealthKit 連携と永続化はここに置く |
| `WeightAppTests/` | アプリ本体のユニットテスト(ホストは WeightApp) |
| `project.yml` | XcodeGen の定義。`WeightApp.xcodeproj` はここから生成する(コミットしない) |
| `docs/` | コンセプトシート、画面デザイン、計画 |

## 必要なもの

- Xcode 27.1 以上(Swift 6.4)
- iOS 26.5 のシミュレーターランタイム(iPhone 17 Pro を使う)
- XcodeGen(`brew install xcodegen`)

## ビルドとテスト

```sh
# WeightCore 単体
cd WeightCore && swift test && cd ..

# アプリ(プロジェクトを生成してからビルド・テスト)
xcodegen generate
xcodebuild -project WeightApp.xcodeproj -scheme WeightApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
xcodebuild -project WeightApp.xcodeproj -scheme WeightApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

`xcodebuild test` は WeightAppTests と WeightCore のテストの両方を実行する。
テストは Swift Testing(`import Testing`)で書く。XCTest は使わない。

## HealthKit

- 読み取る型は体重(`bodyMass`)と体脂肪率(`bodyFatPercentage`)の2つ。除脂肪量は計算で出す。権限の要求コードは次フェーズで書く。
- 説明文(`NSHealthShareUsageDescription`)は `WeightApp/Resources/Info.plist` に手書きで管理する。
- entitlements には `healthkit` と `healthkit.background-delivery` を設定済み。

### 実機でしか確認できないこと

- バックグラウンド受信(`background-delivery`)の動作。シミュレーターでは確認できない。
- HealthPlanet が HealthKit に書き込むときの Bundle ID。確認してから設定値に入れる。
- 署名と entitlements を付けた状態での実機へのインストール。

## 進め方

計画 → 承認 → テストを先に書く → 実装 → `swift test` と `xcodebuild test` → Codex のレビュー、の順で進める。
詳しくは `CLAUDE.md` と `AGENTS.md` を参照。
