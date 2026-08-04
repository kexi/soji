import Foundation

/// サンバースト表示のための階層。
///
/// 内側から ツール → ルール → 個別の候補 の 3 段。それ以上深くしても
/// リング 1 本あたりの角度が細くなるだけで読めない。
///
/// Why SojiKit に置くか: 角度の割り当てと畳み込みは純粋な計算で、View に
/// 置くとテストできない。「表示されている割合が実際のサイズ比と一致する」
/// ことは、掃除アプリの信頼に直結する。
public struct SunburstNode: Sendable, Identifiable, Hashable {

    public let id: String
    public let name: String

    /// 自分とすべての子孫の合計 (バイト)。
    public let bytes: Int64

    /// この節が代表する候補。葉なら 1 件、枝なら配下すべて。
    public let targetIDs: [CleanTarget.ID]

    /// 色分けに使う危険度。枝では配下で最も高いものを採る。
    public let risk: Risk

    /// 配下に soji が消さない項目が含まれるか。
    public let containsAdvisory: Bool

    public let children: [SunburstNode]

    public var isLeaf: Bool { children.isEmpty }

    init(
        id: String,
        name: String,
        bytes: Int64,
        targetIDs: [CleanTarget.ID],
        risk: Risk,
        containsAdvisory: Bool,
        children: [SunburstNode] = []
    ) {
        self.id = id
        self.name = name
        self.bytes = bytes
        self.targetIDs = targetIDs
        self.risk = risk
        self.containsAdvisory = containsAdvisory
        self.children = children
    }
}

extension SunburstNode {

    /// 候補の一覧から階層を組み立てる。
    ///
    /// - Parameter collapseBelow: 全体に対するこの割合未満の節は「その他」に
    ///   畳む。実キャッシュは小さい項目の裾が非常に長く、そのまま描くと
    ///   人間に見えない幅の扇形が数百枚並ぶだけになる。
    public static func build(
        from targets: [CleanTarget],
        collapseBelow ratio: Double = 0.01
    ) -> SunburstNode {
        let total = targets.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let threshold = Int64(Double(total) * ratio)

        let tools = Dictionary(grouping: targets, by: \.toolName)
            .map { name, toolTargets in
                makeToolNode(name: name, targets: toolTargets, threshold: threshold)
            }
            .sorted { $0.bytes > $1.bytes }

        return SunburstNode(
            id: "root",
            name: "すべて",
            bytes: total,
            targetIDs: targets.map(\.id),
            risk: tools.map(\.risk).max() ?? .safe,
            containsAdvisory: targets.contains(\.isAdvisory),
            children: collapse(tools, threshold: threshold, idPrefix: "root")
        )
    }

    private static func makeToolNode(
        name: String, targets: [CleanTarget], threshold: Int64
    ) -> SunburstNode {
        let rules = Dictionary(grouping: targets, by: \.ruleID)
            .map { ruleID, ruleTargets in
                makeRuleNode(ruleID: ruleID, targets: ruleTargets, threshold: threshold)
            }
            .sorted { $0.bytes > $1.bytes }

        return SunburstNode(
            id: "tool:\(name)",
            name: name,
            bytes: targets.reduce(0) { $0 + $1.allocatedSize },
            targetIDs: targets.map(\.id),
            risk: targets.map(\.risk).max() ?? .safe,
            containsAdvisory: targets.contains(\.isAdvisory),
            // ルールが 1 つしかないなら中間の輪は情報を増やさないので省く。
            children: rules.count > 1 ? collapse(rules, threshold: threshold, idPrefix: name) : []
        )
    }

    private static func makeRuleNode(
        ruleID: String, targets: [CleanTarget], threshold: Int64
    ) -> SunburstNode {
        let leaves =
            targets
            .map { target in
                SunburstNode(
                    id: "target:\(target.id)",
                    name: target.displayName,
                    bytes: target.allocatedSize,
                    targetIDs: [target.id],
                    risk: target.risk,
                    containsAdvisory: target.isAdvisory
                )
            }
            .sorted { $0.bytes > $1.bytes }

        return SunburstNode(
            id: "rule:\(ruleID)",
            name: targets.first?.displayName ?? ruleID,
            bytes: targets.reduce(0) { $0 + $1.allocatedSize },
            targetIDs: targets.map(\.id),
            risk: targets.map(\.risk).max() ?? .safe,
            containsAdvisory: targets.contains(\.isAdvisory),
            children: leaves.count > 1 ? collapse(leaves, threshold: threshold, idPrefix: ruleID) : []
        )
    }

    /// 閾値未満の節をまとめて「その他」にする。
    ///
    /// 畳んでも合計は保たれる。ここでサイズを落とすと、リングの面積と
    /// 一覧の数字が食い違って信用を失う。
    private static func collapse(
        _ nodes: [SunburstNode], threshold: Int64, idPrefix: String
    ) -> [SunburstNode] {
        let kept = nodes.filter { $0.bytes >= threshold }
        let dropped = nodes.filter { $0.bytes < threshold }
        guard dropped.count > 1 else { return nodes }

        let other = SunburstNode(
            id: "other:\(idPrefix)",
            name: "その他 \(dropped.count) 件",
            bytes: dropped.reduce(0) { $0 + $1.bytes },
            targetIDs: dropped.flatMap(\.targetIDs),
            risk: dropped.map(\.risk).max() ?? .safe,
            containsAdvisory: dropped.contains(\.containsAdvisory)
        )
        return kept + [other]
    }
}

extension Sequence {
    /// 述語を満たす要素があるか。`contains(where:)` の keyPath 版。
    fileprivate func contains(_ keyPath: KeyPath<Element, Bool>) -> Bool {
        contains { $0[keyPath: keyPath] }
    }
}
