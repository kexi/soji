import Foundation
import Testing

@testable import SojiKit

/// 削除器が保証すること。
///
/// このスイートは実際にファイルを消す。対象は必ず一時ディレクトリ内に限り、
/// ユーザーのファイルには絶対に触れない。
@Suite("Deleter")
struct DeleterTests {

    /// 指定した場所が中身ごと消えることを保証する。
    @Test func removesTargetDirectoryAndItsContents() async throws {
        let temp = try TemporaryDirectory()
        let cache = try temp.makeDirectory("cache")
        try temp.makeFile("cache/a.bin", bytes: 1000)
        try temp.makeFile("cache/nested/b.bin", bytes: 1000)

        let report = await Deleter().delete([makeTarget(url: cache, size: 2000)])

        #expect(!FileManager.default.fileExists(atPath: cache.path))
        #expect(report.failures.isEmpty)
        #expect(report.estimatedBytes == 2000)
    }

    /// 存在しないパスの削除が成功として扱われることを保証する。
    ///
    /// スキャンから削除までの間に他のプロセスが消していることがある。
    /// 「既に無い」は目的が達成された状態であって、失敗ではない。
    @Test func treatsMissingPathAsSuccess() async throws {
        let temp = try TemporaryDirectory()
        let missing = temp.url.appending(path: "never-existed")

        let report = await Deleter().delete([makeTarget(url: missing, size: 500)])

        #expect(report.failures.isEmpty, "存在しないパスが失敗として報告されている")
    }

    /// 1 つが失敗しても残りが削除され、失敗が記録されることを保証する。
    ///
    /// ルートに removeItem を 1 回撃つ実装だと、権限エラー 1 個で残り全部が
    /// 消えたのか分からなくなる。
    @Test func continuesPastFailuresAndRecordsThem() async throws {
        let temp = try TemporaryDirectory()
        let cache = try temp.makeDirectory("cache")
        try temp.makeFile("cache/deletable.bin", bytes: 1000)
        let locked = try temp.makeDirectory("cache/locked")
        try temp.makeFile("cache/locked/stuck.bin", bytes: 1000)
        // 親を読み取り専用にして、配下の削除を失敗させる。
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: locked.path)

        let report = await Deleter().delete([makeTarget(url: cache, size: 2000)])

        #expect(!report.failures.isEmpty, "失敗が記録されていない")
        #expect(
            !FileManager.default.fileExists(atPath: cache.appending(path: "deletable.bin").path),
            "消せるものが消えていない")
        #expect(report.estimatedBytes == 0, "一部でも失敗したらサイズを計上しない")
    }

    /// 一部だけ消えた場合に、消えた分が deletedCount に乗ることを保証する。
    ///
    /// 場所単位で「失敗」に丸めると、中身の大半が消えているのに
    /// 「0 件削除しました」と報告し、しかし解放量だけが増えるという
    /// 矛盾した結果になる。
    @Test func countsPartialSuccessesInsteadOfReportingZero() async throws {
        let temp = try TemporaryDirectory()
        let cache = try temp.makeDirectory("cache")
        try temp.makeFile("cache/deletable1.bin", bytes: 1000)
        try temp.makeFile("cache/deletable2.bin", bytes: 1000)
        let locked = try temp.makeDirectory("cache/locked")
        try temp.makeFile("cache/locked/stuck.bin", bytes: 1000)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: locked.path)

        let report = await Deleter().delete([makeTarget(url: cache, size: 3000)])

        #expect(report.deletedCount >= 2, "消えた分が数えられていない")
        #expect(!report.failures.isEmpty, "失敗が記録されていない")
    }

    /// advisory な候補を絶対に削除しないことを保証する。
    ///
    /// Docker の仮想ディスクや go/pkg/mod は、直接消すとツールが壊れる。
    /// UI の選択ミスがそのまま事故になる層なので、削除器自身でも拒否する。
    @Test func refusesToDeleteAdvisoryTargets() async throws {
        let temp = try TemporaryDirectory()
        let dockerData = try temp.makeDirectory("docker")
        try temp.makeFile("docker/disk.raw", bytes: 1000)

        var target = makeTarget(url: dockerData, size: 1000)
        target = CleanTarget(
            ruleID: target.ruleID,
            toolName: target.toolName,
            displayName: target.displayName,
            url: target.url,
            risk: target.risk,
            allocatedSize: target.allocatedSize,
            fileCount: target.fileCount,
            skippedCount: 0,
            rationale: target.rationale,
            consequence: target.consequence,
            isAdvisory: true,
            advisoryCommand: "docker system prune"
        )

        let report = await Deleter().delete([target])

        #expect(
            FileManager.default.fileExists(atPath: dockerData.path),
            "advisory な対象が削除されている")
        #expect(report.deletedCount == 0)
    }

    /// まとめられた行が、含まれる全ての場所を削除することを保証する。
    ///
    /// 表示は 1 行でも、削除時には元の N 件すべてを消す必要がある。
    @Test func deletesEveryURLOfACollapsedRow() async throws {
        let temp = try TemporaryDirectory()
        var urls: [URL] = []
        for index in 0..<3 {
            urls.append(try temp.makeDirectory("device\(index)"))
            try temp.makeFile("device\(index)/data.bin", bytes: 100)
        }

        let target = CleanTarget(
            ruleID: "test.collapsed",
            toolName: "Test",
            displayName: "まとめた行",
            url: temp.url,
            deletionURLs: urls,
            risk: .safe,
            allocatedSize: 300,
            fileCount: 3,
            skippedCount: 0,
            rationale: "テスト用",
            consequence: "テスト用"
        )

        let report = await Deleter().delete([target])

        for url in urls {
            #expect(!FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) が残っている")
        }
        #expect(report.failures.isEmpty)
    }

    /// 進捗が総数まで報告されることを保証する。
    @Test func reportsProgressForEveryLocation() async throws {
        let temp = try TemporaryDirectory()
        var targets: [CleanTarget] = []
        for index in 0..<3 {
            let dir = try temp.makeDirectory("cache\(index)")
            try temp.makeFile("cache\(index)/data.bin", bytes: 100)
            targets.append(makeTarget(url: dir, size: 100))
        }

        // 並行に呼ばれるコールバックから安全に集めるため Mutex で包む。
        let observed = Observed()
        _ = await Deleter().delete(targets) { progress in
            observed.record(total: progress.total)
        }

        #expect(observed.total == 3)
        #expect(observed.count == 3)
    }

    /// 削除後に実際の解放量が計測されることを保証する。
    ///
    /// 概算 (APFS クローンで過大に出る) と実測を並べて見せるために使う。
    @Test func measuresActualFreedSpace() async throws {
        let temp = try TemporaryDirectory()
        let cache = try temp.makeDirectory("cache")
        try temp.makeFile("cache/data.bin", bytes: 1000)

        let report = await Deleter().delete([makeTarget(url: cache, size: 1000)])

        #expect(report.freedBytes != nil, "解放量が計測されていない")
    }

    // MARK: - helpers

    private func makeTarget(url: URL, size: Int64) -> CleanTarget {
        CleanTarget(
            ruleID: "test.rule",
            toolName: "Test",
            displayName: "テスト対象",
            url: url,
            risk: .safe,
            allocatedSize: size,
            fileCount: 1,
            skippedCount: 0,
            rationale: "テスト用",
            consequence: "テスト用"
        )
    }

    /// 進捗コールバックの観測値。
    private final class Observed: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        private var _total = 0

        func record(total: Int) {
            lock.lock()
            defer { lock.unlock() }
            _count += 1
            _total = total
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return _count
        }

        var total: Int {
            lock.lock()
            defer { lock.unlock() }
            return _total
        }
    }
}
