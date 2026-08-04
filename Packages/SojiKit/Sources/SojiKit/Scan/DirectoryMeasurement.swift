/// ディレクトリツリー 1 本を走査した結果。
public struct DirectoryMeasurement: Sendable, Equatable {

    /// `.totalFileAllocatedSizeKey` の合計 (バイト)。
    ///
    /// ハードリンクで繋がれた実体は 1 回だけ数える。ただし APFS のクローンは
    /// 検出できず二重に数える (`du` も同じ挙動)。実際に解放される量はこの値
    /// 以下になるため、UI では「概算」として扱うこと。
    public var allocatedSize: Int64

    /// サイズを数えた通常ファイルの数。ディレクトリとシンボリックリンクは含まない。
    public var fileCount: Int

    /// 権限などで読めずスキップした項目の数。
    ///
    /// 0 でなければ「この数値は実際より小さい」ことを UI に示す必要がある。
    public var skippedCount: Int

    public init(allocatedSize: Int64 = 0, fileCount: Int = 0, skippedCount: Int = 0) {
        self.allocatedSize = allocatedSize
        self.fileCount = fileCount
        self.skippedCount = skippedCount
    }

    /// 走査が途中でキャンセルされたか。
    ///
    /// キャンセルされた結果を「そのディレクトリのサイズ」として表示すると
    /// 実際より小さい値を見せてしまうので、呼び出し側で捨てられるようにする。
    public var wasCancelled: Bool = false

    public static func + (lhs: Self, rhs: Self) -> Self {
        var result = Self(
            allocatedSize: lhs.allocatedSize + rhs.allocatedSize,
            fileCount: lhs.fileCount + rhs.fileCount,
            skippedCount: lhs.skippedCount + rhs.skippedCount
        )
        result.wasCancelled = lhs.wasCancelled || rhs.wasCancelled
        return result
    }
}
