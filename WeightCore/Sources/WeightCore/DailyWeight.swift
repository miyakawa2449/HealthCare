import Foundation

/// 測定値の出どころ。HKSource の Bundle ID からの変換はアプリ側で行う。
public enum SampleSource: Sendable, Equatable, Codable {
    case healthPlanet
    case other
}

/// HealthKit から取り出した1件の測定値。
public struct WeightSample: Sendable, Equatable {
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

/// 1日の体重を決める。HealthPlanet 由来を優先し、その中で最初の測定値を採用する。
public enum DailyWeightResolver {
    public static func resolve(_ samples: [WeightSample], calendar: Calendar) -> [DailyWeight] {
        let byDay = Dictionary(grouping: samples) { CalendarDay(date: $0.measuredAt, calendar: calendar) }
        return byDay.keys.sorted().compactMap { day in
            guard let chosen = pick(from: byDay[day]!) else { return nil }
            return DailyWeight(day: day, kilograms: chosen.kilograms, measuredAt: chosen.measuredAt, source: chosen.source)
        }
    }

    private static func pick(from samples: [WeightSample]) -> WeightSample? {
        let preferred = samples.filter { $0.source == .healthPlanet }
        let candidates = preferred.isEmpty ? samples : preferred
        return candidates.min { $0.measuredAt < $1.measuredAt }
    }
}
