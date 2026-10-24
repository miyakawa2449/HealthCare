import Foundation
import Testing
@testable import WeightApp

struct WeightAppTests {
    @Test("アプリモジュールが読み込める")
    @MainActor
    func appModuleLoads() {
        _ = ContentView()
    }

    @Test("HealthKit の説明文が確定文言と一致する")
    func healthKitUsageDescription() {
        // ホストアプリで動くテストなので、Bundle.main は WeightApp 本体を指す。
        let text = Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") as? String
        #expect(text == "体重と体脂肪率を Apple ヘルスケアから読み取り、7日平均とレポートの作成に使います。データは外部のサーバーに送信しません。")
    }
}
