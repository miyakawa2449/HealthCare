/// 起動後に出す画面の種類。`HomeModel` の状態から決める(上から順に判定)。
enum RootRoute: Equatable {
    /// ヘルスケアが使えない、または保存先が取れない。
    case unavailable
    /// 最初の取得がまだ終わっていない。
    case loading
    /// 最初の取得に失敗して値がない。
    case failed
    /// 計画がない(初回設定)。
    case setup
    /// 計画がある。
    case home

    @MainActor
    static func route(for model: HomeModel) -> RootRoute {
        if model.isUnavailable { return .unavailable }
        if !model.hasRefreshed { return .loading }
        guard let summary = model.summary else { return model.lastRefreshFailed ? .failed : .loading }
        return summary.plan == nil ? .setup : .home
    }
}
