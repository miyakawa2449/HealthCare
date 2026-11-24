/// フェーズの履歴。過去のレポートの目安とステージを、当時のフェーズで出すために使う。
public struct PhaseTimeline: Sendable, Equatable, Codable {
    /// `from` の日からこのフェーズに従う。
    public struct Entry: Sendable, Equatable, Codable {
        public var from: CalendarDay
        public var phase: PlanPhase

        public init(from: CalendarDay, phase: PlanPhase) {
            self.from = from
            self.phase = phase
        }
    }

    /// 期間の中でフェーズが変わったこと(レポートの「この期間の出来事」)。
    public struct Change: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            /// ステージの区切りに届いて維持期間に入った(早期到達を含む)。
            case arrived(stage: Int, weight: Double)
            /// 最終目標に届いて維持モードに入った。
            case reachedTarget(weight: Double)
            /// 維持期間を終えて次のステージへ進んだ。
            case advanced(toStage: Int)
            /// 計画の見直しを採用して起点を取り直した。
            case planRebased(stage: Int)
            /// 元の計画に戻した。
            case planReverted(stage: Int)
        }

        public var day: CalendarDay
        public var kind: Kind

        public init(day: CalendarDay, kind: Kind) {
            self.day = day
            self.kind = kind
        }
    }

    /// 古い順。
    public private(set) var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries.sorted { $0.from < $1.from }
    }

    /// 履歴のない記録の補完: 計画の開始(ステージ1の減量中)と、今のフェーズが違えばその起点の日からの今のフェーズ。
    public static func reconstructed(roadmap: Roadmap, current: PlanPhase) -> PhaseTimeline {
        let initial = PlanPhase.losing(stage: 1, origin: StageOrigin(weight: roadmap.startWeight, day: roadmap.startDay))
        var timeline = PhaseTimeline(entries: [Entry(from: roadmap.startDay, phase: initial)])
        timeline.append(current, from: max(current.origin.day, roadmap.startDay))
        return timeline
    }

    /// `day` に従っていたフェーズ。最初の項目より前は nil。
    public func phase(on day: CalendarDay) -> PlanPhase? {
        entries.last { $0.from <= day }?.phase
    }

    /// `day` からのフェーズを足す。同じ日の項目は置き換え、直前と同じフェーズなら足さない。日付順を保つ。
    public mutating func append(_ phase: PlanPhase, from day: CalendarDay) {
        entries.removeAll { $0.from == day }
        if let previous = entries.last(where: { $0.from < day }), previous.phase == phase { return }
        entries.append(Entry(from: day, phase: phase))
        entries.sort { $0.from < $1.from }
    }

    /// `from`〜`through` の間に始まった項目を、前の項目との違いで分類する(最初の項目は計画の開始なので含めない)。
    public func changes(from first: CalendarDay, through last: CalendarDay) -> [Change] {
        entries.indices.dropFirst().compactMap { i in
            let entry = entries[i]
            guard entry.from >= first, entry.from <= last else { return nil }
            let previous = entries[i - 1].phase
            switch entry.phase {
            case .maintaining(let stage, let arrival):
                return Change(day: entry.from, kind: .arrived(stage: stage, weight: arrival.weight))
            case .maintenanceMode(let arrival):
                return Change(day: entry.from, kind: .reachedTarget(weight: arrival.weight))
            case .losing(let stage, _):
                if previous.losingStage == nil { return Change(day: entry.from, kind: .advanced(toStage: stage)) }
                // 前に従っていたフェーズに戻ったなら「元の計画に戻した」
                let returned = entries[..<(i - 1)].contains { $0.phase == entry.phase }
                return Change(day: entry.from, kind: returned ? .planReverted(stage: stage) : .planRebased(stage: stage))
            }
        }
    }
}
