import Foundation
import Testing

@testable import SojiKit

/// スキャナが保証すること。
@Suite("TargetScanner")
struct TargetScannerTests {

    /// 実在する場所だけが候補として流れることを保証する。
    @Test func emitsTargetsForExistingLocationsOnly() async throws {
        let temp = try TemporaryDirectory()
        try temp.makeFile("Library/Caches/present/data.bin", bytes: 100_000)

        let scanner = makeScanner(
            home: temp.url,
            rules: [
                makeRule(id: "test.present", locations: [.init("Library/Caches/present")]),
                makeRule(id: "test.absent", locations: [.init("Library/Caches/absent")]),
            ]
        )

        let targets = await collectTargets(from: scanner)

        #expect(targets.count == 1)
        #expect(targets.first?.ruleID == "test.present")
        #expect(targets.first?.allocatedSize ?? 0 >= 100_000)
    }

    /// 空のディレクトリを候補にしないことを保証する。
    ///
    /// 0 バイトの行が並ぶと、消すべきものが埋もれる。
    @Test func skipsEmptyDirectories() async throws {
        let temp = try TemporaryDirectory()
        try temp.makeDirectory("Library/Caches/empty")

        let scanner = makeScanner(
            home: temp.url,
            rules: [makeRule(id: "test.empty", locations: [.init("Library/Caches/empty")])]
        )

        let targets = await collectTargets(from: scanner)

        #expect(targets.isEmpty)
    }

    /// ルールのメタデータが候補に引き継がれることを保証する。
    ///
    /// rationale と consequence はユーザーが削除を判断する唯一の材料なので、
    /// スキャンの過程で失われてはいけない。
    @Test func carriesRuleMetadataIntoTargets() async throws {
        let temp = try TemporaryDirectory()
        try temp.makeFile("Library/Caches/docker/disk.raw", bytes: 100_000)

        let rule = CleanRule(
            id: "test.advisory",
            toolName: "Docker",
            displayName: "イメージ",
            locations: [.init("Library/Caches/docker")],
            risk: .needsConfirmation,
            rationale: "理由",
            consequence: "結果",
            isAdvisory: true,
            advisoryCommand: "docker system prune"
        )
        let scanner = makeScanner(home: temp.url, rules: [rule])

        let targets = await collectTargets(from: scanner)
        let target = try #require(targets.first)

        #expect(target.toolName == "Docker")
        #expect(target.risk == .needsConfirmation)
        #expect(target.rationale == "理由")
        #expect(target.consequence == "結果")
        #expect(target.isAdvisory)
        #expect(target.advisoryCommand == "docker system prune")
    }

    /// expandsChildren が子ごとの候補になることを保証する。
    @Test func expandsChildrenIntoSeparateTargets() async throws {
        let temp = try TemporaryDirectory()
        try temp.makeFile("DerivedData/ProjectA/build.o", bytes: 100_000)
        try temp.makeFile("DerivedData/ProjectB/build.o", bytes: 200_000)

        let scanner = makeScanner(
            home: temp.url,
            rules: [
                makeRule(id: "test.derived", locations: [.init("DerivedData", expandsChildren: true)])
            ]
        )

        let targets = await collectTargets(from: scanner)

        #expect(targets.count == 2)
        #expect(Set(targets.map(\.displayName)) == ["ProjectA", "ProjectB"])
        // 1 ルールから複数候補が出ても ID が衝突しないこと。
        #expect(Set(targets.map(\.id)).count == 2)
    }

    /// 進捗イベントが総数まで単調に増えることを保証する。
    ///
    /// 進捗が飛んだり戻ったりすると、UI のプログレスバーが不自然に動く。
    @Test func reportsMonotonicProgressUpToTotal() async throws {
        let temp = try TemporaryDirectory()
        for index in 0..<5 {
            try temp.makeFile("Library/Caches/c\(index)/data.bin", bytes: 10_000)
        }

        let rules = (0..<5).map { index in
            makeRule(id: "test.c\(index)", locations: [.init("Library/Caches/c\(index)")])
        }
        let scanner = makeScanner(home: temp.url, rules: rules)

        var progressValues: [Int] = []
        var total = 0
        for await event in scanner.scan() {
            if case .progress(let completed, let reportedTotal) = event {
                progressValues.append(completed)
                total = reportedTotal
            }
        }

        #expect(total == 5)
        #expect(progressValues == Array(1...5), "進捗が単調増加していない")
    }

    /// 囲む Task のキャンセルでスキャンが止まることを保証する。
    @Test func stopsWhenSurroundingTaskIsCancelled() async throws {
        let temp = try TemporaryDirectory()
        for index in 0..<40 {
            for file in 0..<50 {
                try temp.makeFile("Library/Caches/c\(index)/f\(file).bin", bytes: 512)
            }
        }
        let rules = (0..<40).map { index in
            makeRule(id: "test.c\(index)", locations: [.init("Library/Caches/c\(index)")])
        }
        let scanner = makeScanner(home: temp.url, rules: rules)

        let task = Task { () -> Int in
            var count = 0
            for await event in scanner.scan() {
                if case .found = event {
                    count += 1
                    if count == 2 { break }  // 途中で購読をやめる
                }
            }
            return count
        }

        let observed = await task.value
        #expect(observed == 2, "購読を止めた後もイベントが流れ続けている")
    }

    /// 閾値未満の子が 1 行にまとめられることを保証する。
    ///
    /// 実機で CoreSimulator/Devices が 88 件に展開され、その大半が 18MB 以下の
    /// 未起動デバイスだった。一覧がノイズで埋まると、本当に消したい上位
    /// (数十 GB) が見えなくなる。
    @Test func collapsesSmallChildrenIntoOneRow() async throws {
        let temp = try TemporaryDirectory()
        // 大きい子 1 件 + 小さい子 5 件。
        try temp.makeFile("Devices/big/data.bin", bytes: 5_000_000)
        for index in 0..<5 {
            try temp.makeFile("Devices/small\(index)/data.bin", bytes: 10_000)
        }

        let rule = CleanRule(
            id: "test.devices",
            toolName: "Test",
            displayName: "デバイス",
            locations: [.init("Devices", expandsChildren: true, childThreshold: 1_000_000)],
            risk: .safe,
            rationale: "テスト用",
            consequence: "テスト用"
        )
        let scanner = makeScanner(home: temp.url, rules: [rule])

        let targets = await collectTargets(from: scanner)

        #expect(targets.count == 2, "大きい子 1 件 + まとめた行 1 件になる")

        let collapsedRow = try #require(targets.first { $0.collapsedCount > 1 })
        #expect(collapsedRow.collapsedCount == 5, "小さい子が全部まとまっている")
        #expect(collapsedRow.displayName.contains("5 件"))
        #expect(collapsedRow.allocatedSize >= 50_000, "まとめた行の合計サイズ")

        let bigRow = try #require(targets.first { $0.collapsedCount == 1 })
        #expect(bigRow.displayName == "big", "閾値以上の子は個別のまま")
    }

    /// まとめた行が、含まれる全ての場所を削除対象として持つことを保証する。
    ///
    /// 表示は 1 行でも、削除時には元の N 件すべてを消す必要がある。
    @Test func collapsedRowRetainsAllDeletionURLs() async throws {
        let temp = try TemporaryDirectory()
        for index in 0..<3 {
            try temp.makeFile("Devices/small\(index)/data.bin", bytes: 10_000)
        }

        let rule = CleanRule(
            id: "test.devices",
            toolName: "Test",
            displayName: "デバイス",
            locations: [.init("Devices", expandsChildren: true, childThreshold: 1_000_000)],
            risk: .safe,
            rationale: "テスト用",
            consequence: "テスト用"
        )
        let targets = await collectTargets(from: makeScanner(home: temp.url, rules: [rule]))
        let row = try #require(targets.first)

        #expect(row.deletionURLs.count == 3)
        #expect(Set(row.deletionURLs.map(\.lastPathComponent)) == ["small0", "small1", "small2"])
    }

    /// 閾値が 0 (既定) なら集約せず、すべて個別の行になることを保証する。
    @Test func doesNotCollapseWhenThresholdIsZero() async throws {
        let temp = try TemporaryDirectory()
        for index in 0..<3 {
            try temp.makeFile("Devices/small\(index)/data.bin", bytes: 10_000)
        }

        let rule = CleanRule(
            id: "test.devices",
            toolName: "Test",
            displayName: "デバイス",
            locations: [.init("Devices", expandsChildren: true)],
            risk: .safe,
            rationale: "テスト用",
            consequence: "テスト用"
        )
        let targets = await collectTargets(from: makeScanner(home: temp.url, rules: [rule]))

        #expect(targets.count == 3)
        #expect(targets.allSatisfy { $0.collapsedCount == 1 })
    }

    // MARK: - helpers

    private func makeScanner(home: URL, rules: [CleanRule]) -> TargetScanner {
        TargetScanner(rules: rules, resolver: PathResolver(home: home, environment: [:]))
    }

    private func makeRule(id: String, locations: [CleanRule.Location]) -> CleanRule {
        CleanRule(
            id: id,
            toolName: "Test",
            displayName: "テスト対象",
            locations: locations,
            risk: .safe,
            rationale: "テスト用",
            consequence: "テスト用"
        )
    }

    private func collectTargets(from scanner: TargetScanner) async -> [CleanTarget] {
        var targets: [CleanTarget] = []
        for await event in scanner.scan() {
            if case .found(let target) = event { targets.append(target) }
        }
        return targets
    }
}
