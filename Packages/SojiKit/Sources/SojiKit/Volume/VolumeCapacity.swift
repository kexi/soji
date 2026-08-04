import Foundation

/// ボリュームの空き容量。
///
/// macOS は「空き」を 2 通りに数える。この差を見せないと「Finder は 100GB
/// 空きと言うのに soji は 20GB と言う」という不信を招く。
public struct VolumeCapacity: Sendable, Equatable {

    /// 今すぐ使える真の空き容量 (バイト)。
    public let available: Int64

    /// purgeable を含む空き容量 (バイト)。Finder が表示するのはこちら。
    ///
    /// macOS が必要に応じて自動削除する領域 (Time Machine のローカル
    /// スナップショット、キャッシュ等) を空きとして数えた値。
    public let availableForImportantUsage: Int64

    /// ボリュームの総容量 (バイト)。
    public let total: Int64

    /// Finder が「空き」と呼んでいるもののうち、実際には purgeable な分。
    ///
    /// soji が削除しなくても、ディスクが逼迫すれば macOS が自動的に解放する。
    public var purgeable: Int64 {
        max(0, availableForImportantUsage - available)
    }

    /// 指定パスが属するボリュームの容量を読む。
    public static func current(for url: URL = URL(fileURLWithPath: "/")) -> VolumeCapacity? {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }

        // volumeAvailableCapacityForImportantUsage だけ Int64、他は Int。
        let importantUsage = values.volumeAvailableCapacityForImportantUsage ?? 0
        return VolumeCapacity(
            available: Int64(values.volumeAvailableCapacity ?? 0),
            availableForImportantUsage: importantUsage,
            total: Int64(values.volumeTotalCapacity ?? 0)
        )
    }
}
