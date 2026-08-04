import Foundation
import Testing

@testable import SojiKit

/// サンバーストの階層構築が保証すること。
///
/// リングの面積がサイズ比を表すので、ここで合計が狂うと「見えている割合」と
/// 「一覧の数字」が食い違い、可視化そのものが信用を失う。
@Suite("SunburstTree")
struct SunburstTreeTests {

    /// 根の合計が候補の合計と一致することを保証する。
    @Test func rootTotalMatchesTheSumOfTargets() {
        let targets = [
            makeTarget(id: "a", tool: "A", rule: "a.rule", size: 1000),
            makeTarget(id: "b", tool: "B", rule: "b.rule", size: 2000),
            makeTarget(id: "c", tool: "B", rule: "b.rule", size: 3000),
        ]

        let tree = SunburstNode.build(from: targets)

        #expect(tree.bytes == 6000)
    }

    /// 各階層で、子の合計が親と一致することを保証する。
    ///
    /// ここがずれると、内側の輪と外側の輪の幅が食い違って見える。
    @Test func childrenSumToTheirParentAtEveryLevel() {
        let targets = (0..<6).map { index in
            makeTarget(
                id: "t\(index)",
                tool: index < 3 ? "A" : "B",
                rule: "rule\(index % 2)",
                size: Int64((index + 1) * 1000))
        }

        let tree = SunburstNode.build(from: targets, collapseBelow: 0)

        assertChildrenSum(tree)
    }

    /// ツールごとにまとまることを保証する。
    @Test func groupsByTool() {
        let targets = [
            makeTarget(id: "a", tool: "Homebrew", rule: "brew.x", size: 1000),
            makeTarget(id: "b", tool: "npm", rule: "npm.x", size: 2000),
            makeTarget(id: "c", tool: "npm", rule: "npm.y", size: 3000),
        ]

        let tree = SunburstNode.build(from: targets, collapseBelow: 0)

        #expect(tree.children.count == 2)
        // 大きい順に並ぶ。
        #expect(tree.children.first?.name == "npm")
        #expect(tree.children.first?.bytes == 5000)
    }

    /// 小さい節を畳んでも合計が変わらないことを保証する。
    ///
    /// 実キャッシュは小さい項目の裾が長く、そのまま描くと人間に見えない幅の
    /// 扇形が数百枚並ぶ。畳むのは表示の都合であって、量を捨ててよいという
    /// 意味ではない。
    @Test func collapsingSmallNodesPreservesTheTotal() {
        var targets = [makeTarget(id: "big", tool: "Big", rule: "big.rule", size: 1_000_000)]
        for index in 0..<20 {
            targets.append(
                makeTarget(id: "s\(index)", tool: "Small\(index)", rule: "s.rule", size: 100))
        }

        let tree = SunburstNode.build(from: targets, collapseBelow: 0.01)

        #expect(tree.bytes == 1_000_000 + 20 * 100, "畳んだ分が失われている")
        #expect(tree.children.count < 21, "畳まれていない")

        let childSum = tree.children.reduce(Int64(0)) { $0 + $1.bytes }
        #expect(childSum == tree.bytes)
    }

    /// 畳まれた節が元の候補すべてを指すことを保証する。
    ///
    /// クリックしたときに元の項目へ辿れないと、可視化から操作に繋がらない。
    @Test func collapsedNodeKeepsEveryTargetID() {
        var targets = [makeTarget(id: "big", tool: "Big", rule: "big.rule", size: 1_000_000)]
        for index in 0..<5 {
            targets.append(
                makeTarget(id: "s\(index)", tool: "Small\(index)", rule: "s.rule", size: 100))
        }

        let tree = SunburstNode.build(from: targets, collapseBelow: 0.01)
        let other = tree.children.first { $0.name.hasPrefix("その他") }

        #expect(other?.targetIDs.count == 5)
    }

    /// 枝の危険度が配下で最も高いものになることを保証する。
    ///
    /// 「安全」と表示された輪の中に要確認が隠れていると、色が嘘をつく。
    @Test func branchRiskIsTheHighestAmongDescendants() {
        let targets = [
            makeTarget(id: "a", tool: "Mixed", rule: "m.safe", size: 1000, risk: .safe),
            makeTarget(
                id: "b", tool: "Mixed", rule: "m.risky", size: 1000, risk: .needsConfirmation),
        ]

        let tree = SunburstNode.build(from: targets, collapseBelow: 0)
        let tool = tree.children.first

        #expect(tool?.risk == .needsConfirmation)
    }

    /// advisory を含む枝がそれを伝えることを保証する。
    @Test func branchReportsAdvisoryDescendants() {
        let targets = [
            makeTarget(id: "a", tool: "Docker", rule: "d.rule", size: 1000, isAdvisory: true)
        ]

        let tree = SunburstNode.build(from: targets, collapseBelow: 0)

        #expect(tree.containsAdvisory)
        #expect(tree.children.first?.containsAdvisory == true)
    }

    /// 候補が無いときに空の根を返すことを保証する。
    @Test func returnsEmptyRootForNoTargets() {
        let tree = SunburstNode.build(from: [])

        #expect(tree.bytes == 0)
        #expect(tree.children.isEmpty)
    }

    private func assertChildrenSum(_ node: SunburstNode, depth: Int = 0) {
        guard !node.children.isEmpty else { return }
        let sum = node.children.reduce(Int64(0)) { $0 + $1.bytes }
        #expect(sum == node.bytes, "深さ \(depth) の '\(node.name)' で子の合計が親と違う")
        for child in node.children {
            assertChildrenSum(child, depth: depth + 1)
        }
    }

    private func makeTarget(
        id: String, tool: String, rule: String, size: Int64,
        risk: Risk = .safe, isAdvisory: Bool = false
    ) -> CleanTarget {
        CleanTarget(
            ruleID: rule,
            toolName: tool,
            displayName: id,
            url: URL(fileURLWithPath: "/tmp/soji-fixture/\(id)"),
            risk: risk,
            allocatedSize: size,
            fileCount: 1,
            skippedCount: 0,
            rationale: "テスト用",
            consequence: "テスト用",
            isAdvisory: isAdvisory,
            advisoryCommand: isAdvisory ? "tool prune" : nil
        )
    }
}
