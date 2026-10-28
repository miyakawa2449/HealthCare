import Foundation
import Testing
@testable import WeightCore

struct PlanSetupTests {
    let s = PlanSettings.default

    @Test("最終目標の初期値は BMI × 身長(m)²。丸めない")
    func defaultTarget() {
        #expect(abs(PlanSetup.defaultTargetWeight(heightCentimeters: 175, settings: s) - 67.375) < 1e-9)
        #expect(abs(PlanSetup.defaultTargetWeight(heightCentimeters: 160, settings: s) - 56.32) < 1e-9)
    }

    @Test("Roadmap に入れると 0.1kg に丸まる")
    func roundedByRoadmap() {
        let target = PlanSetup.defaultTargetWeight(heightCentimeters: 175, settings: s)
        let r = Roadmap(startWeight: 123.5, startDay: day(2026, 10, 18), targetWeight: target, settings: s)
        #expect(r.targetWeight == 67.4)
    }

    @Test("設定の BMI に追従する")
    func followsSettings() {
        var custom = s
        custom.defaultTargetBMI = 25
        #expect(abs(PlanSetup.defaultTargetWeight(heightCentimeters: 175, settings: custom) - 76.5625) < 1e-9)
    }

    @Test("身長の初期値は 175cm")
    func defaultHeight() {
        #expect(PlanSetup.defaultHeightCentimeters == 175)
    }

    @Test("検証", arguments: [
        (123.5, 67.4, nil),
        (0.0, 67.4, PlanSetup.ValidationError.startWeightNotPositive),
        (123.5, 0.0, .targetWeightNotPositive),
        (67.4, 67.4, .targetNotBelowStart),
        (67.3, 67.4, .targetNotBelowStart),
        (67.5, 67.4, nil),
    ] as [(Double, Double, PlanSetup.ValidationError?)])
    func validate(start: Double, target: Double, expected: PlanSetup.ValidationError?) {
        #expect(PlanSetup.validate(startWeight: start, targetWeight: target) == expected)
    }

    @Test("無限大と NaN は notFinite(Roadmap の境界計算が終わらなくなるため)")
    func notFinite() {
        #expect(PlanSetup.validate(startWeight: .infinity, targetWeight: 67.4) == .notFinite)
        #expect(PlanSetup.validate(startWeight: 123.5, targetWeight: -.infinity) == .notFinite)
        #expect(PlanSetup.validate(startWeight: .nan, targetWeight: 67.4) == .notFinite)
        #expect(PlanSetup.validate(startWeight: 123.5, targetWeight: .nan) == .notFinite)
    }

    @Test("負の値も正の数でないとして扱う")
    func negative() {
        #expect(PlanSetup.validate(startWeight: -1, targetWeight: 67.4) == .startWeightNotPositive)
        #expect(PlanSetup.validate(startWeight: 123.5, targetWeight: -1) == .targetWeightNotPositive)
    }
}
