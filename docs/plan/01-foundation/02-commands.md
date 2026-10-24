# 実行して確認するコマンド

```sh
# 事前準備(1回だけ)
brew install xcodegen

# WeightCore 単体
cd WeightCore && swift test

# アプリ
xcodegen generate
xcodebuild -project WeightApp.xcodeproj -scheme WeightApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
xcodebuild -project WeightApp.xcodeproj -scheme WeightApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test

# 起動確認(ビルド後、シミュレーターにインストールして起動し、画面が出ることを見る)
xcrun simctl boot "iPhone 17 Pro" ; xcrun simctl launch booted com.miyakawa.weightapp

# 生成物が無視されていること
git status --short
```

## 補足

- iPhone 16 Pro のシミュレーターは iOS 18 系にしかないため、iOS 26.5 にある iPhone 17 Pro を使う(05-implementation-plan.md 参照)。
- iOS 27.1 のシミュレーターランタイムは未ダウンロードなので、テストは 26.5 で回す。27.1 で回したい場合は `xcodebuild -downloadPlatform iOS` が必要(数GB)。
- バックグラウンドでの HealthKit 受信はシミュレーターで確認できない。このフェーズでは受信処理を書かないので、確認対象は「entitlements を付けてビルドが通ること」まで。

## 確認する結果

| コマンド | 期待する結果 |
| --- | --- |
| `swift test` | WeightCoreTests の雛形テストが通る |
| `xcodegen generate` | `WeightApp.xcodeproj` が生成される |
| `xcodebuild build` | エラーなしで終わる |
| `xcodebuild test` | WeightAppTests と WeightCoreTests が両方通る |
| `simctl launch` | 「今日の体重」の文字だけの画面が出る |
| `git status --short` | `WeightApp.xcodeproj` と `.DS_Store` が出てこない |
