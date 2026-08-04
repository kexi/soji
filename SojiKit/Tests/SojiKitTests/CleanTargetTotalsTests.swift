import Foundation
import Testing

@testable import SojiKit

/// 合計の集計が保証すること。
///
/// ここが狂うとユーザーに「消せる量」の嘘を見せる。
@Suite("CleanTargetTotals")
struct CleanTargetTotalsTests {

    /// 同じ場所を指す複数のルールを二重に数えないことを保証する。
    ///
    /// 実測で pnpm のストアが advisory と通常の 2 ルールに指され、素朴に足すと
    /// 合計が 71 GB から 108 GB に水増しされた。
    @Test func doesNotCountTheSamePathTwice() {
        let url = URL(fileURLWithPath: "/tmp/soji-fixture/store")
        let targets = [
            makeTarget(ruleID: "tool.advisory", url: url, size: 1000, isAdvisory: true),
            makeTarget(ruleID: "tool.whole", url: url, size: 1000),
        ]

        #expect(targets.reclaimableBytes == 1000, "同じ場所が二重に数えられている")
    }

    /// advisory な候補を「削除できる量」に含めないことを保証する。
    ///
    /// advisory は soji が消さないものなので、解放量として見せると嘘になる。
    @Test func excludesAdvisoryTargetsFromReclaimable() {
        let targets = [
            makeTarget(ruleID: "a.rule", url: URL(fileURLWithPath: "/tmp/a"), size: 500),
            makeTarget(
                ruleID: "b.rule", url: URL(fileURLWithPath: "/tmp/b"), size: 900, isAdvisory: true),
        ]

        #expect(targets.reclaimableBytes == 500)
        #expect(targets.advisoryBytes == 900)
    }

    /// 別々の場所は素直に合算されることを保証する。
    @Test func sumsDistinctPaths() {
        let targets = (0..<4).map { index in
            makeTarget(
                ruleID: "rule.\(index)",
                url: URL(fileURLWithPath: "/tmp/dir\(index)"),
                size: 100)
        }

        #expect(targets.reclaimableBytes == 400)
    }

    /// 空のときに 0 を返すことを保証する。
    @Test func returnsZeroForEmptyCollection() {
        let targets: [CleanTarget] = []

        #expect(targets.reclaimableBytes == 0)
        #expect(targets.advisoryBytes == 0)
    }

    private func makeTarget(
        ruleID: String, url: URL, size: Int64, isAdvisory: Bool = false
    ) -> CleanTarget {
        CleanTarget(
            ruleID: ruleID,
            toolName: "Test",
            displayName: "テスト対象",
            url: url,
            risk: .safe,
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
