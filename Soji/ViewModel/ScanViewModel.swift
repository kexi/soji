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

    private(set) var phase: Phase = .idle
    private(set) var targets: [CleanTarget] = []
    private(set) var capacity: VolumeCapacity?

    /// チェックが入っている候補の ID。
    var selection: Set<CleanTarget.ID> = []

    private var scanTask: Task<Void, Never>?

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    /// 選択中の候補。
    var selectedTargets: [CleanTarget] {
        targets.filter { selection.contains($0.id) }
    }

    /// 選択中の概算合計 (バイト)。
    var selectedBytes: Int64 {
        selectedTargets.reduce(0) { $0 + $1.allocatedSize }
    }

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

    /// 大きいものから並べる。消したいものが上に来る。
    private func sortTargets() {
        targets.sort { $0.allocatedSize > $1.allocatedSize }
    }
}
