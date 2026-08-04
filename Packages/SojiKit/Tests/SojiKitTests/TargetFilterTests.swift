import Foundation
import Testing

@testable import SojiKit

/// 候補の絞り込みが保証すること。
///
/// scan と clean はこの 1 つの型を通る。ここがずれると「scan で見えたのに
/// clean で消えない」あるいは「clean が scan に無いものを消す」が起きる。
@Suite("TargetFilter")
struct TargetFilterTests {

    /// 空の条件がすべてを通すことを保証する (advisory を除く)。
    @Test func emptyFilterPassesEverythingExceptAdvisory() {
        let targets = [
            makeTarget(ruleID: "a.rule", tool: "A", risk: .safe, size: 100),
            makeTarget(ruleID: "b.rule", tool: "B", risk: .needsConfirmation, size: 200),
            makeTarget(ruleID: "c.rule", tool: "C", risk: .safe, size: 300, isAdvisory: true),
        ]

        let passed = targets.filtered(by: TargetFilter())

        #expect(passed.count == 2, "advisory は既定で含めない")
        #expect(!passed.contains { $0.isAdvisory })
    }

    /// 危険度で絞り込めることを保証する。
    @Test func filtersByRisk() {
        let targets = [
            makeTarget(ruleID: "a.rule", tool: "A", risk: .safe, size: 100),
            makeTarget(ruleID: "b.rule", tool: "B", risk: .slowToRebuild, size: 200),
            makeTarget(ruleID: "c.rule", tool: "C", risk: .needsConfirmation, size: 300),
        ]

        let passed = targets.filtered(by: TargetFilter(risks: [.safe, .slowToRebuild]))

        #expect(Set(passed.map(\.ruleID)) == ["a.rule", "b.rule"])
    }

    /// ツール名とルール ID で絞り込めることを保証する。
    @Test func filtersByToolAndRuleID() {
        let targets = [
            makeTarget(ruleID: "homebrew.downloads", tool: "Homebrew", risk: .safe, size: 100),
            makeTarget(ruleID: "npm.cacache", tool: "npm", risk: .safe, size: 200),
        ]

        let byTool = targets.filtered(by: TargetFilter(tools: ["npm"]))
        #expect(byTool.map(\.ruleID) == ["npm.cacache"])

        let byRule = targets.filtered(by: TargetFilter(ruleIDs: ["homebrew.downloads"]))
        #expect(byRule.map(\.ruleID) == ["homebrew.downloads"])
    }

    /// 最小サイズで足切りできることを保証する。
    @Test func filtersBySize() {
        let targets = [
            makeTarget(ruleID: "small.rule", tool: "A", risk: .safe, size: 100),
            makeTarget(ruleID: "big.rule", tool: "B", risk: .safe, size: 10_000),
        ]

        let passed = targets.filtered(by: TargetFilter(minimumBytes: 1000))

        #expect(passed.map(\.ruleID) == ["big.rule"])
    }

    /// 結果が常に大きい順であることを保証する。
    ///
    /// 消したいものが上に来るという性質は、CLI の出力でも GUI の一覧でも同じ。
    @Test func sortsBySizeDescending() {
        let targets = [
            makeTarget(ruleID: "small.rule", tool: "A", risk: .safe, size: 100),
            makeTarget(ruleID: "big.rule", tool: "B", risk: .safe, size: 10_000),
            makeTarget(ruleID: "mid.rule", tool: "C", risk: .safe, size: 5_000),
        ]

        let passed = targets.filtered(by: TargetFilter())

        #expect(passed.map(\.ruleID) == ["big.rule", "mid.rule", "small.rule"])
    }

    /// forDeletion が advisory を必ず落とすことを保証する。
    ///
    /// advisory はツール自身のコマンドでしか安全に消せない。呼び出し側が
    /// includesAdvisory を立てていても、削除経路では必ず外れなければならない。
    @Test func deletionFilterAlwaysDropsAdvisory() {
        let targets = [
            makeTarget(ruleID: "a.rule", tool: "A", risk: .safe, size: 100),
            makeTarget(ruleID: "docker.data", tool: "Docker", risk: .safe, size: 999, isAdvisory: true),
        ]
        // 明示的に advisory を含める条件で始める。
        let permissive = TargetFilter(includesAdvisory: true)
        #expect(targets.filtered(by: permissive).count == 2, "前提: 一覧では含まれる")

        let passed = targets.filtered(by: permissive.forDeletion)

        #expect(passed.map(\.ruleID) == ["a.rule"], "削除経路に advisory が残っている")
    }

    private func makeTarget(
        ruleID: String, tool: String, risk: Risk, size: Int64, isAdvisory: Bool = false
    ) -> CleanTarget {
        CleanTarget(
            ruleID: ruleID,
            toolName: tool,
            displayName: "テスト対象",
            url: URL(fileURLWithPath: "/tmp/soji-fixture/\(ruleID)"),
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
