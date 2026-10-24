import Testing
@testable import WeightCore

struct RoundingTests {
    @Test("割合は 0.01% に丸める", arguments: [
        (0.004999, 0.0050), (0.00505, 0.0051), (0.00504, 0.0050), (-0.00505, -0.0051), (0.02, 0.02),
    ])
    func ratio(input: Double, expected: Double) {
        #expect(Ratio.rounded(input) == expected)
    }

    @Test("体重は 0.1kg に丸める", arguments: [
        (111.15, 111.2), (100.035, 100.0), (72.92, 72.9), (117.325, 117.3), (123.5, 123.5),
    ])
    func weight(input: Double, expected: Double) {
        #expect(Weight.rounded(input) == expected)
    }
}

extension RoundingTests {
    @Test("差を割った結果の「ちょうど半分」も表現誤差で落ちない")
    func halfFromDivision() {
        #expect(Ratio.rounded((100.505 - 100.0) / 100.0) == 0.0051)
        #expect(Ratio.rounded((99.495 - 100.0) / 100.0) == -0.0051)
        #expect(Weight.rounded(123.5 * 0.9) == 111.2)
    }
}
