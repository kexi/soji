import Foundation
import Observation
import SojiKit

/// スキャンと削除の状態を持つ。
///
/// SojiKit 側は nonisolated 既定で並行 executor 上を走る。この ViewModel が
/// MainActor 境界で、AsyncStream から受け取った結果を UI に渡す。
@MainActor
@Observable
final class ScanViewModel {

    enum Phase: Equatable {
        case idle
        case scanning(completed: Int, total: Int)
        case done
    }

    /// 削除の進行状態。シートの出し分けに使う。
    enum Deletion: Equatable {
        case idle
        /// 確認シートを出している。
        case confirming
        case running(currentPath: String, completed: Int, total: Int)
        case finished(DeletionSummary)
    }

    /// 完了レポートの表示に必要な値だけを持つ。
    struct DeletionSummary: Equatable {
        let deletedCount: Int
        let estimatedBytes: Int64
        /// 空き容量の前後差から求めた実測値。
        let freedBytes: Int64?
        let failures: [DeletionFailure]
        let wasCancelled: Bool
    }

    private(set) var phase: Phase = .idle
    private(set) var targets: [CleanTarget] = []
    private(set) var capacity: VolumeCapacity?
    private(set) var deletion: Deletion = .idle

    /// チェックが入っている候補の ID。
    var selection: Set<CleanTarget.ID> = []

    private var scanTask: Task<Void, Never>?
    private var deleteTask: Task<Void, Never>?

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    var isDeleting: Bool {
        if case .running = deletion { return true }
        return false
    }

    /// 選択中の候補。
    var selectedTargets: [CleanTarget] {
        targets.filter { selection.contains($0.id) }
    }

    /// 実際に削除される候補。advisory は含まれない。
    ///
    /// Why 分けるか: 一覧では advisory も選べるように見えるが、削除経路には
    /// 決して入らない。サマリーバーの「消える量」もこちらで数える。
    var deletableTargets: [CleanTarget] {
        selectedTargets.filtered(by: TargetFilter().forDeletion)
    }

    /// 選択中の概算合計 (バイト)。
    var selectedBytes: Int64 {
        deletableTargets.reclaimableBytes
    }

    /// スキャンで見つかった、soji が削除できる量の合計 (バイト)。
    var reclaimableBytes: Int64 {
        targets.reclaimableBytes
    }

    /// soji では消さず、ツール自身のコマンドに委ねる量の合計 (バイト)。
    var advisoryBytes: Int64 {
        targets.advisoryBytes
    }

    /// 選択中に含まれる、注意して確認すべき候補。
    ///
    /// 確認シートで個別に列挙する。
    var riskySelection: [CleanTarget] {
        deletableTargets.filter { $0.risk == .needsConfirmation }
    }

    // MARK: - scan

    func scan() {
        scanTask?.cancel()
        targets = []
        selection = []
        capacity = VolumeCapacity.current()
        phase = .scanning(completed: 0, total: 0)

        scanTask = Task {
            for await event in TargetScanner().scan() {
                switch event {
                case .found(let target):
                    targets.append(target)
                    // 既定で選ぶのは完全に再生成可能なものだけ。掃除アプリの
                    // 事故は「気づかないうちに選択されていた」もので起きる。
                    if target.risk.isSelectedByDefault && !target.isAdvisory {
                        selection.insert(target.id)
                    }
                case .progress(let completed, let total):
                    phase = .scanning(completed: completed, total: total)
                }
            }
            sortTargets()
            phase = .done
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        sortTargets()
        phase = .done
    }

    // MARK: - delete

    func requestDeletion() {
        guard !deletableTargets.isEmpty else { return }
        deletion = .confirming
    }

    func cancelDeletionRequest() {
        deletion = .idle
    }

    func confirmDeletion() {
        let targetsToDelete = deletableTargets
        guard !targetsToDelete.isEmpty else {
            deletion = .idle
            return
        }

        let total = targetsToDelete.reduce(0) { $0 + $1.deletionURLs.count }
        deletion = .running(currentPath: "", completed: 0, total: total)

        deleteTask = Task {
            // Why 間引くか: 削除は 15,000〜20,000 files/s で進む。コールバック
            // ごとに @Observable を更新すると、UI の再描画自体がボトルネックに
            // なって削除より遅くなる。
            let throttle = ProgressThrottle()
            let report = await Deleter().delete(targetsToDelete) { progress in
                guard throttle.shouldEmit() else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.isDeleting else { return }
                    self.deletion = .running(
                        currentPath: progress.currentPath,
                        completed: progress.completed,
                        total: progress.total)
                }
            }

            deletion = .finished(
                DeletionSummary(
                    deletedCount: report.deletedCount,
                    estimatedBytes: report.estimatedBytes,
                    freedBytes: report.freedBytes,
                    failures: report.failures,
                    wasCancelled: report.wasCancelled))

            // 消えたものを一覧から外す。再スキャンせずに結果を反映する。
            let deletedIDs = Set(targetsToDelete.map(\.id))
            targets.removeAll { deletedIDs.contains($0.id) }
            selection.subtract(deletedIDs)
            capacity = VolumeCapacity.current()
        }
    }

    func cancelDeletion() {
        deleteTask?.cancel()
    }

    func dismissDeletionResult() {
        deletion = .idle
        deleteTask = nil
    }

    /// 大きいものから並べる。消したいものが上に来る。
    private func sortTargets() {
        targets.sort { $0.allocatedSize > $1.allocatedSize }
    }
}

/// 進捗コールバックを一定間隔に間引く。
///
/// Why nonisolated が要るか: app ターゲットは MainActor 既定なので、何も
/// 書かないとこのクラスも MainActor に載る。削除の進捗は SojiKit 側の
/// 並行 executor から呼ばれるため、MainActor 隔離されていると呼べない。
private nonisolated final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastEmitted = ContinuousClock.now
    private let interval = Duration.milliseconds(100)

    func shouldEmit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = ContinuousClock.now
        guard now - lastEmitted >= interval else { return false }
        lastEmitted = now
        return true
    }
}
