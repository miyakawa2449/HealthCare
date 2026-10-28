import Foundation
import Testing
import WeightCore
@testable import WeightApp

struct SetupFormStateTests {
    @Test("初期値: 開始体重は提案、身長 175、最終目標は BMI 22")
    func initial() {
        let s = SetupFormState(suggestedStartWeight: 123.5)
        #expect(s.startText == "123.5")
        #expect(s.heightText == "175")
        #expect(s.targetText == "67.4")
        #expect(s.canStart)
        #expect(s.firstMilestoneWeight == 117.3)
    }

    @Test("提案がなければ開始体重は空欄で、ボタンは無効")
    func noSuggestion() {
        let s = SetupFormState(suggestedStartWeight: nil)
        #expect(s.startText == "")
        #expect(s.problem == .notNumber)
        #expect(!s.canStart)
    }

    @Test("身長を変えると最終目標の初期値を計算し直す")
    func heightChange() {
        var s = SetupFormState(suggestedStartWeight: 123.5)
        s.heightChanged("170")
        #expect(s.targetText == "63.6")
    }

    @Test("最終目標を手で直したあとは身長を変えても上書きしない")
    func targetEdited() {
        var s = SetupFormState(suggestedStartWeight: 123.5)
        s.targetChanged("70.0")
        s.heightChanged("170")
        #expect(s.targetText == "70.0")
    }

    @Test("数字でなければ notNumber")
    func notNumber() {
        var s = SetupFormState(suggestedStartWeight: 123.5)
        s.startText = "abc"
        #expect(s.problem == .notNumber)
    }

    @Test("最終目標が開始体重以上なら targetNotBelowStart")
    func targetNotBelow() {
        var s = SetupFormState(suggestedStartWeight: 67.0)
        #expect(s.problem == .targetNotBelowStart)
        s.targetChanged("66.9")
        #expect(s.canStart)
    }

    @Test("0 以下は notPositive")
    func notPositive() {
        var s = SetupFormState(suggestedStartWeight: 123.5)
        s.targetChanged("0")
        #expect(s.problem == .notPositive)
    }
}
