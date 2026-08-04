import Foundation

/// 削除に失敗した項目 1 件。
public struct DeletionFailure: Sendable, Identifiable, Hashable {
    public var id: String { url.path(percentEncoded: false) }

    public let url: URL

    /// ユーザーに見せる失敗理由。
    public let reason: String

    /// この失敗を解消するための案内 (あれば)。
    ///
    /// `~/go/pkg/mod` の読み取り専用のように、別の手段が必要な場合に出す。
    public let suggestion: String?

    public init(url: URL, reason: String, suggestion: String? = nil) {
        self.url = url
        self.reason = reason
        self.suggestion = suggestion
    }
}

/// 削除の結果。
public struct DeletionReport: Sendable {

    /// 削除に成功した項目の、スキャン時点での合計サイズ (バイト)。
    ///
    /// これは「消せたはずの量」であって実際に解放された量ではない。APFS の
    /// クローンがあるため実解放量はこれ以下になる。UI では空き容量の
    /// 前後差 (`freedBytes`) と並べて見せること。
    public var estimatedBytes: Int64 = 0

    /// 削除に成功した項目の数。
    public var deletedCount: Int = 0

    public var failures: [DeletionFailure] = []

    /// 削除前後の空き容量から求めた、実際に解放された量 (バイト)。
    ///
    /// nil なら計測できなかった。
    public var freedBytes: Int64?

    /// キャンセルによって途中で終わったか。
    public var wasCancelled = false

    public init() {}
}

/// 削除の進捗。
public struct DeletionProgress: Sendable {
    /// いま削除しているパス。
    public let currentPath: String

    /// 削除し終えた項目の数。
    public let completed: Int

    /// 削除する項目の総数。
    public let total: Int
}
