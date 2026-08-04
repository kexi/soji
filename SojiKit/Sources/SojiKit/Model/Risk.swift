/// 削除の取り返しのつかなさ。UI の既定選択と警告文はこれで決まる。
///
/// 「消したら何が起きるか」を段階で表す。容量の大小とは独立で、100GB の
/// DerivedData は `safe` だが 10MB の Archives は `needsConfirmation`。
public enum Risk: Int, Sendable, Comparable, CaseIterable, Codable {
    /// 完全に再生成可能。次のビルドやインストールで自動的に戻る。
    case safe = 0

    /// 再生成可能だが、再取得にネットワークと時間がかかる。
    case slowToRebuild = 1

    /// 再生成にユーザーの操作が要る、または環境を壊しうる。既定では選択しない。
    case needsConfirmation = 2

    public static func < (lhs: Risk, rhs: Risk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// スキャン後に既定でチェックを入れてよいか。
    ///
    /// Why safe のみか: 掃除アプリの事故は「気づかないうちに選択されていた」
    /// ものを消して起きる。既定選択は再生成が自動で完結するものに限る。
    public var isSelectedByDefault: Bool {
        self == .safe
    }
}
