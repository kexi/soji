import Foundation

/// 削除候補の絞り込み条件。
///
/// Why SojiKit に置くか: CLI の scan と clean が同じ結果を返すことを保証する
/// ため、両者はこの 1 つの型を通る。ここが分かれると「scan で見えたのに
/// clean で消えない」「clean が scan に無いものを消す」が起きる。
/// GUI のサイドバー絞り込みも同じ語彙を使える。
public struct TargetFilter: Sendable {

    /// 対象にする危険度。空なら全部。
    public var risks: Set<Risk>

    /// 対象にするツール名。空なら全部。
    public var tools: Set<String>

    /// 対象にするルール ID。空なら全部。
    public var ruleIDs: Set<String>

    /// このバイト数未満の候補を除外する。
    public var minimumBytes: Int64

    /// ツール自身のコマンドに委ねる項目を含めるか。
    public var includesAdvisory: Bool

    public init(
        risks: Set<Risk> = [],
        tools: Set<String> = [],
        ruleIDs: Set<String> = [],
        minimumBytes: Int64 = 0,
        includesAdvisory: Bool = false
    ) {
        self.risks = risks
        self.tools = tools
        self.ruleIDs = ruleIDs
        self.minimumBytes = minimumBytes
        self.includesAdvisory = includesAdvisory
    }

    /// 削除にだけ使う、安全側に倒した版。
    ///
    /// advisory はツール自身のコマンドでしか安全に消せないので、削除経路には
    /// 決して混ぜない。呼び出し側が includesAdvisory を立てていても落とす。
    public var forDeletion: TargetFilter {
        var filter = self
        filter.includesAdvisory = false
        return filter
    }

    public func matches(_ target: CleanTarget) -> Bool {
        if !risks.isEmpty && !risks.contains(target.risk) { return false }
        if !tools.isEmpty && !tools.contains(target.toolName) { return false }
        if !ruleIDs.isEmpty && !ruleIDs.contains(target.ruleID) { return false }
        if target.allocatedSize < minimumBytes { return false }
        if !includesAdvisory && target.isAdvisory { return false }
        return true
    }
}

extension Sequence where Element == CleanTarget {
    /// 条件で絞り込み、大きい順に並べる。
    ///
    /// 並び順まで含めてここで決めるのは、消したいものが常に上に来るという
    /// 性質を呼び出し側ごとに書き直させないため。
    public func filtered(by filter: TargetFilter) -> [CleanTarget] {
        self.filter(filter.matches).sorted { $0.allocatedSize > $1.allocatedSize }
    }
}
