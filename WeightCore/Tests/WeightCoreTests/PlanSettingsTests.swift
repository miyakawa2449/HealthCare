import Testing
@testable import WeightCore

// AGENTS.md「ドメインルール」の数値を、設定値として1か所にまとめたことを確かめる。
// 計算や判定のロジックはフェーズ2で書く。
struct PlanSettingsTests {
    let settings = PlanSettings.default

    @Test("標準ペースは月2%")
    func standardPace() {
        #expect(settings.monthlyRate == 0.02)
    }

    @Test("安全性判定の閾値は週0.5%と1%")
    func safetyThresholds() {
        #expect(settings.weeklySafeLimit == 0.005)
        #expect(settings.weeklyCautionLimit == 0.01)
    }

    @Test("ステージ幅は10%、最初のマイルストーンは5%")
    func stageRatios() {
        #expect(settings.stageRatio == 0.10)
        #expect(settings.firstMilestoneRatio == 0.05)
    }

    @Test("維持期間は最低4週・最長12週、範囲は±2%")
    func maintenance() {
        #expect(settings.maintenanceMinDays == 28)
        #expect(settings.maintenanceMaxDays == 84)
        #expect(settings.maintenanceBand == 0.02)
    }

    @Test("進み具合の帯は±0.5%、見直しは2%ずれが14日")
    func progressAndReview() {
        #expect(settings.progressBand == 0.005)
        #expect(settings.reviewDeviation == 0.02)
        #expect(settings.reviewWindowDays == 14)
    }

    @Test("実績ペースの窓は28日、速すぎの上限は月3%")
    func actualPace() {
        #expect(settings.actualPaceWindowDays == 28)
        #expect(settings.fastPaceMonthlyLimit == 0.03)
    }

    @Test("1か月は30日固定")
    func daysPerMonth() {
        #expect(settings.daysPerMonth == 30)
    }

    @Test("最終目標の初期値はBMI22")
    func defaultTargetBMI() {
        #expect(settings.defaultTargetBMI == 22)
    }
}
