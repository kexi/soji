import Foundation

/// 削除候補を完全削除する。
///
/// Why not ゴミ箱: ゴミ箱への移動は同一ボリューム上の rename にすぎず、
/// 空き容量が 1 バイトも増えない。実測で 20,000 ファイルの rename は 0.024 秒、
/// 実削除は 1.4 秒 ― この 60 倍の速度差が「何も解放していない」ことの証拠。
/// ディスクフル解消のために起動されるアプリが目的を達成できないのは論外なので、
/// removeItem で完全に消す。対象は再生成可能なキャッシュに限っている。
public struct Deleter: Sendable {

    public init() {}

    /// 指定された候補を削除する。
    ///
    /// - Parameters:
    ///   - targets: 削除する候補。`isAdvisory` のものは無視される。
    ///   - progress: 進捗の通知。呼び出し頻度が高いので、UI 側で間引くこと。
    @concurrent
    public func delete(
        _ targets: [CleanTarget],
        progress: @Sendable (DeletionProgress) -> Void = { _ in }
    ) async -> DeletionReport {
        var report = DeletionReport()

        // 削除前後の差から実際の解放量を出す。概算 (allocatedSize) は APFS の
        // クローンで過大に出るため、事後の実測を並べて見せる。
        let capacityBefore = VolumeCapacity.current()?.available

        // Why advisory を弾くか: Docker の仮想ディスクや go/pkg/mod のように、
        // ファイルを直接消すとツールが壊れる、あるいは権限で消せないもの。
        // UI 側の選択ミスがそのまま事故になる層なので、削除器自身でも拒否する。
        let deletable = targets.filter { !$0.isAdvisory }
        let allURLs = deletable.flatMap(\.deletionURLs)
        var completed = 0

        for target in deletable {
            if Task.isCancelled {
                report.wasCancelled = true
                break
            }

            var didFailAnywhere = false
            for url in target.deletionURLs {
                if Task.isCancelled {
                    report.wasCancelled = true
                    break
                }

                progress(
                    DeletionProgress(
                        currentPath: url.path(percentEncoded: false),
                        completed: completed,
                        total: allURLs.count))

                let failures = removeContents(of: url, advisory: target.advisoryCommand)
                if failures.isEmpty {
                    report.deletedCount += 1
                } else {
                    didFailAnywhere = true
                    report.failures.append(contentsOf: failures)
                }
                completed += 1
            }

            if !didFailAnywhere {
                report.estimatedBytes += target.allocatedSize
            }
        }

        if let before = capacityBefore, let after = VolumeCapacity.current()?.available {
            report.freedBytes = max(0, after - before)
        }
        return report
    }

    /// 1 つの場所を消す。
    ///
    /// Why 直下を 1 段掘ってから消すか: removeItem はツリーの途中で失敗すると
    /// throw するが「どこまで消えたか」を返さない。ルートに 1 回だけ撃つと、
    /// 権限エラー 1 個で残り全部が消えたのか消えていないのか判別できなくなる。
    /// 1 段掘って個別に try/catch し、失敗した枝だけを報告する。
    private func removeContents(of url: URL, advisory: String?) -> [DeletionFailure] {
        let manager = FileManager.default
        let children =
            (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []))
            ?? []

        var failures: [DeletionFailure] = []

        for child in children {
            if let failure = remove(child, advisory: advisory) {
                failures.append(failure)
            }
        }

        // 中身が消えていれば、入れ物自体も消す。中身が残っている場合は
        // ここも失敗するが、原因は既に failures に載っているので報告しない。
        let isEmptyNow = failures.isEmpty
        if isEmptyNow, let failure = remove(url, advisory: advisory) {
            failures.append(failure)
        }
        return failures
    }

    private func remove(_ url: URL, advisory: String?) -> DeletionFailure? {
        do {
            // Why not fileExists で事前確認するか: TOCTOU で意味が無い上、
            // 50 万回の余分な stat になる。存在しないなら ENOENT が返るので
            // それを見る (try, don't check)。
            try FileManager.default.removeItem(at: url)
            return nil
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // 既に無い = 目的は達成されている。
            return nil
        } catch {
            return DeletionFailure(
                url: url,
                reason: describe(error),
                suggestion: suggestion(for: error, advisory: advisory)
            )
        }
    }

    private func describe(_ error: Error) -> String {
        let cocoaError = error as? CocoaError
        switch cocoaError?.code {
        case .fileWriteNoPermission, .fileReadNoPermission:
            return "権限がありません"
        case .fileWriteVolumeReadOnly:
            return "読み取り専用のボリュームです"
        case .fileLocking:
            return "使用中です"
        default:
            return error.localizedDescription
        }
    }

    private func suggestion(for error: Error, advisory: String?) -> String? {
        if let advisory { return advisory }

        let isPermissionProblem =
            (error as? CocoaError)?.code == .fileWriteNoPermission
            || (error as? CocoaError)?.code == .fileReadNoPermission
        guard isPermissionProblem else { return nil }

        // 読み取り専用で作られるキャッシュ (go/pkg/mod 等) は、ツール自身の
        // コマンドでしか消せない。
        return "このディレクトリは読み取り専用です。ツール自身のクリーンコマンドを使ってください。"
    }
}
