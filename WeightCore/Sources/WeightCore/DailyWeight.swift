import Foundation

/// 測定値の出どころ。HKSource の Bundle ID からの変換はアプリ側で行う。
public enum SampleSource: Sendable, Equatable, Codable {
    case healthPlanet
    case other
}

/// HealthKit から取り出した1件の測定値に共通するもの。1日の値の決定(`DailySampleResolver`)はこれだけを見る。
public protocol MeasurementSample: Sendable {
    var measuredAt: Date { get }
    var source: SampleSource { get }
}

/// HealthKit から取り出した1件の体重。
public struct WeightSample: MeasurementSample, Equatable {
    public var kilograms: Double
    public var measuredAt: Date
    public var source: SampleSource

    public init(kilograms: Double, measuredAt: Date, source: SampleSource) {
        self.kilograms = kilograms
        self.measuredAt = measuredAt
        self.source = source
    }
}

/// その日の体重として採用した1件。
public struct DailyWeight: Sendable, Equatable {
    public var day: CalendarDay
    public var kilograms: Double
    public var measuredAt: Date
    public var source: SampleSource

    public init(day: CalendarDay, kilograms: Double, measuredAt: Date, source: SampleSource) {
        self.day = day
        self.kilograms = kilograms
        self.measuredAt = measuredAt
        self.source = source
    }
}

/// 1日の値を決める共通の規則。HealthPlanet 由来を優先し、その中で最初の測定値を採用する。
/// 体重と体脂肪率で同じ規則を使う。
public enum DailySampleResolver {
    /// `calendar` のタイムゾーンで日付に分け、日付の昇順で (日付, 採用したサンプル) を返す。
    public static func resolve<S: MeasurementSample>(_ samples: [S], calendar: Calendar) -> [(day: CalendarDay, sample: S)] {
        let byDay = Dictionary(grouping: samples) { CalendarDay(date: $0.measuredAt, calendar: calendar) }
        return byDay.keys.sorted().compactMap { day in
            guard let chosen = pick(from: byDay[day]!) else { return nil }
            return (day, chosen)
        }
    }

    private static func pick<S: MeasurementSample>(from samples: [S]) -> S? {
        let preferred = samples.filter { $0.source == .healthPlanet }
        let candidates = preferred.isEmpty ? samples : preferred
        return candidates.min { $0.measuredAt < $1.measuredAt }
    }
}

/// 1日の体重を決める(`DailySampleResolver` の体重版)。
public enum DailyWeightResolver {
    public static func resolve(_ samples: [WeightSample], calendar: Calendar) -> [DailyWeight] {
        DailySampleResolver.resolve(samples, calendar: calendar).map { day, s in
            DailyWeight(day: day, kilograms: s.kilograms, measuredAt: s.measuredAt, source: s.source)
        }
    }
}

/// HealthKit から取り出した1件の体脂肪率(0.0〜1.0 の割合)。
public struct BodyFatSample: MeasurementSample, Equatable {
    public var fraction: Double
    public var measuredAt: Date
    public var source: SampleSource

    public init(fraction: Double, measuredAt: Date, source: SampleSource) {
        self.fraction = fraction
        self.measuredAt = measuredAt
        self.source = source
    }
}

/// その日の体脂肪率として採用した1件。
public struct DailyBodyFat: Sendable, Equatable {
    public var day: CalendarDay
    public var fraction: Double
    public var measuredAt: Date
    public var source: SampleSource

    public init(day: CalendarDay, fraction: Double, measuredAt: Date, source: SampleSource) {
        self.day = day
        self.fraction = fraction
        self.measuredAt = measuredAt
        self.source = source
    }
}

/// 1日の体脂肪率を決める(`DailySampleResolver` の体脂肪率版)。
public enum DailyBodyFatResolver {
    public static func resolve(_ samples: [BodyFatSample], calendar: Calendar) -> [DailyBodyFat] {
        DailySampleResolver.resolve(samples, calendar: calendar).map { day, s in
            DailyBodyFat(day: day, fraction: s.fraction, measuredAt: s.measuredAt, source: s.source)
        }
    }
}

/// 初回設定で示す開始体重の初期値。
public enum InitialWeightSuggestion {
    /// 直近7日平均(窓に1件でもあれば平均)。窓に0件なら最新の1件。データがなければ nil。
    public static func suggest(on day: CalendarDay, weights: [DailyWeight]) -> Double? {
        if let avg = SevenDayAverage(endingOn: day, in: weights) { return avg.kilograms }
        return weights.filter { $0.day <= day }.max { $0.day < $1.day }?.kilograms
    }
}
