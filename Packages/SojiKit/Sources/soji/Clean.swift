import ArgumentParser
import Foundation
import SojiKit

struct Clean: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "候補を削除する。既定はドライランで、--yes を付けたときだけ実際に消す。",
        discussion: """
            Why ドライランが既定か: このコマンドは取り消せない。エージェントが
            意図せず実行しても、--yes が無ければ何も起きない。

            ゴミ箱には入れず完全に削除する。ゴミ箱への移動は同一ボリューム上の
            rename にすぎず、空き容量が 1 バイトも増えないため。対象は
            再生成可能なキャッシュに限っている。
            """
    )

    @OptionGroup var filter: FilterOptions
    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "実際に削除する。指定しなければ何も消さない。")
    var yes = false

    func run() async throws {
        // Why includeAdvisory を強制的に落とすか: advisory はツール自身の
        // コマンドでしか安全に消せないもの。削除経路に混ぜない。
        var deletionFilter = filter
        deletionFilter.includeAdvisory = false
        let targets = try await scanAndFilter(deletionFilter)

        guard yes else {
            try reportDryRun(targets)
            return
        }

        let report = await Deleter().delete(targets)
        try printResult(report, targets: targets)

        if !report.failures.isEmpty {
            throw ExitCode.partialFailure.asParsableError
        }
    }

    private func reportDryRun(_ targets: [CleanTarget]) throws {
        guard output.json else {
            if targets.isEmpty {
                print("削除するものはありません。")
                return
            }
            for target in targets {
                print(target.summaryLine)
            }
            let total = targets.reclaimableBytes.formatted(.byteCount(style: .file))
            print("")
            print("ドライラン: \(targets.count) 件 / 概算 \(total) が削除対象です。")
            print("実際に削除するには --yes を付けてください。")
            return
        }
        try printJSON(DryRunReport(targets: targets))
    }

    private func printResult(_ report: DeletionReport, targets: [CleanTarget]) throws {
        guard output.json else {
            let estimated = report.estimatedBytes.formatted(.byteCount(style: .file))
            print("\(report.deletedCount) 件を削除しました (概算 \(estimated))。")

            if let freed = report.freedBytes {
                // 概算は APFS のクローンで過大に出る。事後の実測を並べて示す。
                let formatted = freed.formatted(.byteCount(style: .file))
                print("実際に解放された容量: \(formatted)")
            }
            // 失敗は stderr へ。成功分の要約を stdout でパイプしている最中に
            // 混ざると、エージェントの解析を壊す。
            for failure in report.failures {
                var line = "失敗: \(failure.url.path(percentEncoded: false)) — \(failure.reason)"
                if let suggestion = failure.suggestion {
                    line += " (\(suggestion))"
                }
                printToStandardError(line)
            }
            return
        }
        try printJSON(CleanResult(report: report))
    }
}

/// ドライランの結果。
private struct DryRunReport: Encodable {
    let dryRun = true
    let entries: [ScanReport.Entry]
    let totals: ScanReport.Totals

    init(targets: [CleanTarget]) {
        let report = ScanReport(targets: targets, volume: nil)
        entries = report.entries
        totals = report.totals
    }
}

/// 実削除の結果。
private struct CleanResult: Encodable {
    let dryRun = false
    let deletedCount: Int
    let estimatedBytes: Int64
    let freedBytes: Int64?
    let cancelled: Bool
    let failures: [Failure]

    struct Failure: Encodable {
        let path: String
        let reason: String
        let suggestion: String?
    }

    init(report: DeletionReport) {
        deletedCount = report.deletedCount
        estimatedBytes = report.estimatedBytes
        freedBytes = report.freedBytes
        cancelled = report.wasCancelled
        failures = report.failures.map {
            Failure(
                path: $0.url.path(percentEncoded: false),
                reason: $0.reason,
                suggestion: $0.suggestion)
        }
    }
}

extension ExitCode {
    /// ArgumentParser に終了コードを伝えるためのエラー。
    var asParsableError: any Error {
        ArgumentParser.ExitCode(rawValue)
    }
}
