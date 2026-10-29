/// 計画と判定に使う閾値を1か所にまとめた設定値。
///
/// 値の根拠は AGENTS.md の「ドメインルール」。計算や判定のロジックはここに置かず、
/// ロジック側がこの型を引数として受け取る。割合はすべて 1.0 = 100% で表す。
public struct PlanSettings: Sendable, Equatable, Codable {
    /// 標準ペース(1か月あたりの減量割合)。その時点の7日平均に対する割合。
    public var monthlyRate: Double
    /// 1か月の日数。暦月ではなく固定値で日割りする。
    public var daysPerMonth: Int

    /// 安全性判定(週あたり)。この値以下は「無理がない」。
    public var weeklySafeLimit: Double
    /// 安全性判定(週あたり)。safe を超えこの値以下は「頑張りすぎ注意」、超えたら「危険」。
    public var weeklyCautionLimit: Double

    /// 実績ペースを測る窓の日数(7日平均の変化率をこの期間で見る)。
    public var actualPaceWindowDays: Int
    /// 実績ペースについて伝える上限(1か月あたり)。これを超えたらペースを落とすよう伝える。
    public var fastPaceMonthlyLimit: Double

    /// ステージ幅。各ステージ開始時の体重に対する減量割合。
    public var stageRatio: Double
    /// ステージ1の中に置く最初のマイルストーン(開始体重に対する割合)。
    public var firstMilestoneRatio: Double

    /// 維持期間の最低日数。卒業条件の「28日連続」と同じ長さ。
    public var maintenanceMinDays: Int
    /// 維持期間の最長日数。超えたら提案カードを出し、ユーザーが選ぶ。
    public var maintenanceMaxDays: Int
    /// 維持期間中に収まるべき範囲(ステージ到達時の体重に対する±割合)。
    public var maintenanceBand: Double

    /// 進み具合の判定で「計画どおり」とする範囲(目安の値に対する±割合)。
    public var progressBand: Double
    /// 計画見直しを提案するずれ(計画値に対する割合)。
    public var reviewDeviation: Double
    /// 計画見直しを提案するまでに、ずれが続く日数。
    public var reviewWindowDays: Int

    /// 最終目標の初期値を決める BMI。
    public var defaultTargetBMI: Double

    /// 到達予定日の計算で、各ステージの後に置くと仮定する維持期間の日数。
    public var assumedMaintenanceDays: Int
    /// 最初の1か月(この経過日数未満)は進み具合・実績ペース・計画見直しの判定をしない。
    public var initialPeriodDays: Int
    /// 実績ペースの窓の始まりを、この経過日数より前にしない(初期の水分減少を含めないため)。14日目 = 経過13日。
    public var actualPaceWindowStartFloor: Int
    /// 実績ペースの窓の最低日数。これ未満なら判定しない(1日の揺れが 30/n 乗で拡大されるため)。
    public var actualPaceMinimumWindowDays: Int
    /// 維持中に、7日平均が範囲外に連続してこの日数続いたら一言を出す。
    public var maintenanceNoticeDays: Int
    /// 提案を断った日(早期到達、計画見直し、元の計画に戻した日)や「維持を続ける」を選んだ日から、この日数後に再提案する。
    /// この型は plan.json に保存されるので、項目を足すと既存のファイルが読めなくなる。用途が同じ日数は1つにまとめる。
    public var earlyArrivalRetryDays: Int

    public init(
        monthlyRate: Double,
        daysPerMonth: Int,
        weeklySafeLimit: Double,
        weeklyCautionLimit: Double,
        actualPaceWindowDays: Int,
        fastPaceMonthlyLimit: Double,
        stageRatio: Double,
        firstMilestoneRatio: Double,
        maintenanceMinDays: Int,
        maintenanceMaxDays: Int,
        maintenanceBand: Double,
        progressBand: Double,
        reviewDeviation: Double,
        reviewWindowDays: Int,
        defaultTargetBMI: Double,
        assumedMaintenanceDays: Int,
        initialPeriodDays: Int,
        actualPaceWindowStartFloor: Int,
        actualPaceMinimumWindowDays: Int,
        maintenanceNoticeDays: Int,
        earlyArrivalRetryDays: Int
    ) {
        self.monthlyRate = monthlyRate
        self.daysPerMonth = daysPerMonth
        self.weeklySafeLimit = weeklySafeLimit
        self.weeklyCautionLimit = weeklyCautionLimit
        self.actualPaceWindowDays = actualPaceWindowDays
        self.fastPaceMonthlyLimit = fastPaceMonthlyLimit
        self.stageRatio = stageRatio
        self.firstMilestoneRatio = firstMilestoneRatio
        self.maintenanceMinDays = maintenanceMinDays
        self.maintenanceMaxDays = maintenanceMaxDays
        self.maintenanceBand = maintenanceBand
        self.progressBand = progressBand
        self.reviewDeviation = reviewDeviation
        self.reviewWindowDays = reviewWindowDays
        self.defaultTargetBMI = defaultTargetBMI
        self.assumedMaintenanceDays = assumedMaintenanceDays
        self.initialPeriodDays = initialPeriodDays
        self.actualPaceWindowStartFloor = actualPaceWindowStartFloor
        self.actualPaceMinimumWindowDays = actualPaceMinimumWindowDays
        self.maintenanceNoticeDays = maintenanceNoticeDays
        self.earlyArrivalRetryDays = earlyArrivalRetryDays
    }

    /// AGENTS.md のドメインルールどおりの既定値。
    public static let `default` = PlanSettings(
        monthlyRate: 0.02,
        daysPerMonth: 30,
        weeklySafeLimit: 0.005,
        weeklyCautionLimit: 0.01,
        actualPaceWindowDays: 28,
        fastPaceMonthlyLimit: 0.03,
        stageRatio: 0.10,
        firstMilestoneRatio: 0.05,
        maintenanceMinDays: 28,
        maintenanceMaxDays: 84,
        maintenanceBand: 0.02,
        progressBand: 0.005,
        reviewDeviation: 0.02,
        reviewWindowDays: 14,
        defaultTargetBMI: 22,
        assumedMaintenanceDays: 60,
        initialPeriodDays: 30,
        actualPaceWindowStartFloor: 13,
        actualPaceMinimumWindowDays: 14,
        maintenanceNoticeDays: 14,
        earlyArrivalRetryDays: 14
    )
}
