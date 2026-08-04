import Foundation

/// スキャン中に流れるイベント。
public enum ScanEvent: Sendable {
    /// 実在してサイズが判明した削除候補が 1 件見つかった。
    case found(CleanTarget)

    /// 進捗。`completed` は測り終えた場所の数。
    case progress(completed: Int, total: Int)
}

/// 組み込みルールを実在チェックし、並列にサイズを測って候補に変換する。
public struct TargetScanner: Sendable {

    /// 実測で 4 / 8 / 16 並列がすべて約 124,000 files/s と同値だった。
    /// メタデータ走査は共有 APFS b-tree 律速で CPU 律速ではないため、
    /// これ以上広げてもファイルディスクリプタとメモリを食うだけ。
    static let maxConcurrency = 4

    let rules: [CleanRule]
    let resolver: PathResolver

    public init(rules: [CleanRule] = BuiltinRules.all, resolver: PathResolver = PathResolver()) {
        self.rules = rules
        self.resolver = resolver
    }

    /// スキャンを開始し、見つかった端から結果を流す。
    ///
    /// 戻り値のストリームを破棄するか、囲む Task をキャンセルすると走査は止まる。
    public func scan() -> AsyncStream<ScanEvent> {
        let units = resolveUnits()

        return AsyncStream { continuation in
            let task = Task {
                await run(units: units, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 実在する場所だけを、測定単位に展開する。
    ///
    /// ルールが指すパスは実在しないのが正常なので、ここで大半が落ちる。
    func resolveUnits() -> [ScanUnit] {
        rules.flatMap { rule in
            resolver.resolve(rule).map { location in
                ScanUnit(rule: rule, location: location)
            }
        }
    }

    private func run(units: [ScanUnit], continuation: AsyncStream<ScanEvent>.Continuation) async {
        var completed = 0

        // 閾値未満だった子は、ルールごとにまとめて 1 行にする。
        var collapsed: [String: CollapsedGroup] = [:]

        // 測定結果から元の unit を引くための索引。線形探索だと候補数の
        // 二乗になる (実機で 100 件超)。
        let index = Dictionary(units.map { ($0.location.url, $0) }, uniquingKeysWith: { first, _ in first })

        await withTaskGroup(of: CleanTarget?.self) { group in
            var iterator = units.makeIterator()

            // 固定幅ウィンドウ: 常に maxConcurrency 本だけ走らせ続ける。
            // 全件を一度に addTask すると、数千の場所があるときに同時に
            // ファイルディスクリプタを掴んでしまう。
            var inFlight = 0
            while inFlight < Self.maxConcurrency, let unit = iterator.next() {
                group.addTask { await Self.measure(unit) }
                inFlight += 1
            }

            // Why 集計をこの for await 側でやるか: actor に 1 件ずつ送ると
            // アクターホップ (5〜15µs) が件数分積み上がる。ここは単一の
            // 実行文脈なので共有可変状態が無く、actor そのものが不要。
            for await target in group {
                completed += 1
                if let target {
                    if let group = collapsingGroupKey(for: target, index: index) {
                        collapsed[group.key, default: group.empty].absorb(target)
                    } else {
                        continuation.yield(.found(target))
                    }
                }
                continuation.yield(.progress(completed: completed, total: units.count))

                if Task.isCancelled { break }
                if let unit = iterator.next() {
                    group.addTask { await Self.measure(unit) }
                }
            }
        }

        // まとめた行は全件測り終えてから流す (合計サイズが確定しないため)。
        for group in collapsed.values {
            if let target = group.makeTarget() {
                continuation.yield(.found(target))
            }
        }
    }

    /// この候補を「小さい兄弟」としてまとめるべきかを判定し、まとめ先の鍵を返す。
    private func collapsingGroupKey(
        for target: CleanTarget, index: [URL: ScanUnit]
    ) -> (key: String, empty: CollapsedGroup)? {
        guard let unit = index[target.url] else { return nil }
        let threshold = unit.location.collapsesBelow
        let isCollapsible = threshold > 0 && target.allocatedSize < threshold
        guard isCollapsible else { return nil }

        return (
            key: unit.rule.id,
            empty: CollapsedGroup(rule: unit.rule, parentName: unit.location.parentDisplayName)
        )
    }

    /// 1 つの場所を測る。
    ///
    /// Why @concurrent: この処理は数秒〜数十秒 I/O を占める。呼び出し元が
    /// MainActor だった場合に暗黙で MainActor に載るのを禁じ、必ず並行
    /// executor へ逃がす (Xcode 26 の app ターゲットは MainActor 既定)。
    @concurrent
    static func measure(_ unit: ScanUnit) async -> CleanTarget? {
        let measurement = measureDirectory(at: unit.location.url) { Task.isCancelled }

        // キャンセルされた結果は「途中までの合計」なので、実際より小さい値を
        // 候補として見せないよう捨てる。
        if measurement.wasCancelled { return nil }

        // 空のディレクトリを候補に出すと、UI が 0 バイトの行で埋まる。
        let isEmpty = measurement.fileCount == 0 && measurement.allocatedSize == 0
        if isEmpty { return nil }

        let rule = unit.rule
        return CleanTarget(
            ruleID: rule.id,
            toolName: rule.toolName,
            displayName: unit.location.displayName,
            url: unit.location.url,
            risk: rule.risk,
            allocatedSize: measurement.allocatedSize,
            fileCount: measurement.fileCount,
            skippedCount: measurement.skippedCount,
            rationale: rule.rationale,
            consequence: rule.consequence,
            isAdvisory: rule.isAdvisory,
            advisoryCommand: rule.advisoryCommand
        )
    }
}

/// 測定 1 単位 = ルールと、それが解決した実在の場所。
struct ScanUnit: Sendable {
    let rule: CleanRule
    let location: ResolvedLocation
}

/// 閾値未満の小さい兄弟を 1 行にまとめるための蓄積器。
///
/// 実機で CoreSimulator/Devices が 88 件に展開され、その大半が 18MB 以下の
/// 未起動デバイスだった。一覧がノイズで埋まると、本当に消したい上位が
/// 見えなくなる。
private struct CollapsedGroup {
    let rule: CleanRule
    let parentName: String?

    private var urls: [URL] = []
    private var totalSize: Int64 = 0
    private var totalFiles = 0
    private var totalSkipped = 0

    init(rule: CleanRule, parentName: String?) {
        self.rule = rule
        self.parentName = parentName
    }

    mutating func absorb(_ target: CleanTarget) {
        urls.append(contentsOf: target.deletionURLs)
        totalSize += target.allocatedSize
        totalFiles += target.fileCount
        totalSkipped += target.skippedCount
    }

    func makeTarget() -> CleanTarget? {
        guard let first = urls.first else { return nil }
        let base = parentName ?? rule.displayName
        return CleanTarget(
            ruleID: rule.id,
            toolName: rule.toolName,
            displayName: "\(base) (小さい項目 \(urls.count) 件)",
            // 代表 URL は親ディレクトリ。UI にはこのパスが出る。
            url: first.deletingLastPathComponent(),
            deletionURLs: urls,
            risk: rule.risk,
            allocatedSize: totalSize,
            fileCount: totalFiles,
            skippedCount: totalSkipped,
            rationale: rule.rationale,
            consequence: rule.consequence,
            isAdvisory: rule.isAdvisory,
            advisoryCommand: rule.advisoryCommand
        )
    }
}
