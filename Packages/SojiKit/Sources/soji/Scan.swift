import ArgumentParser
import Foundation
import SojiKit

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "削除候補を探して一覧する。何も削除しない。",
        discussion: """
            既定では安全に消せるもの (risk=safe) だけを出す。すべて見るには:
              soji scan --risk safe --risk slowToRebuild --risk needsConfirmation --include-advisory
            """
    )

    @OptionGroup var filter: FilterOptions
    @OptionGroup var output: OutputOptions

    func run() async throws {
        // JSON 出力時も進捗は stderr なので邪魔しない。
        let targets = try await scanAndFilter(filter, showsProgress: true)

        guard output.json else {
            printHuman(targets)
            return
        }
        try printJSON(ScanReport(targets: targets, volume: VolumeCapacity.current()))
    }

    private func printHuman(_ targets: [CleanTarget]) {
        guard !targets.isEmpty else {
            print("削除候補は見つかりませんでした。")
            return
        }

        for target in targets {
            print(target.summaryLine)
        }

        print("")
        let reclaimable = targets.reclaimableBytes.formatted(.byteCount(style: .file))
        print("候補 \(targets.count) 件 / 削除できる量 概算 \(reclaimable)")

        let advisory = targets.advisoryBytes
        if advisory > 0 {
            // soji が消さない分を合計に混ぜると「消せる量」の嘘になる。
            let formatted = advisory.formatted(.byteCount(style: .file))
            print("! の付いた \(formatted) は soji では削除せず、ツール自身のコマンドに委ねます。")
        }

        if let capacity = VolumeCapacity.current() {
            let available = capacity.available.formatted(.byteCount(style: .file))
            let purgeable = capacity.purgeable.formatted(.byteCount(style: .file))
            print("現在の空き \(available)（ほかに \(purgeable) は macOS が必要時に自動解放）")
        }

        // 概算であることを明示する。APFS のクローンは du も含めて二重計上する。
        print("※ サイズは概算です。実際の解放量はこれ以下になります。")
    }
}
