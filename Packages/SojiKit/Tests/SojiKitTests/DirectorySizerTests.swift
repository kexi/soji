import Foundation
import Testing

@testable import SojiKit

/// ディレクトリサイズ計測が保証すること。
///
/// ここが間違うとユーザーに嘘のサイズを見せる。「削除したら何 GB 空くか」に
/// 答えられる数値であることを、実ファイルシステム上で検証する。
///
/// Why 実 FS を使うか: このコードの本質は FileManager と APFS の挙動そのもの。
/// mock に差し替えるとテストしたい当のものが消える。
@Suite("DirectorySizer")
struct DirectorySizerTests {

    /// 通常のツリーのサイズが実際の割り当て量と一致することを保証する。
    @Test func sumsAllocatedSizeOfRegularFiles() throws {
        let temp = try TemporaryDirectory()
        try temp.makeFile("a.bin", bytes: 100_000)
        try temp.makeFile("nested/b.bin", bytes: 200_000)
        try temp.makeFile("nested/deep/c.bin", bytes: 300_000)

        let measurement = measureDirectory(at: temp.url) { false }

        #expect(measurement.fileCount == 3)
        #expect(measurement.skippedCount == 0)
        // ブロック単位に切り上がるため下限だけ検証する。
        #expect(measurement.allocatedSize >= 600_000)
        #expect(measurement.allocatedSize < 700_000)
    }

    /// ハードリンクで繋がれた同一実体を二重計上しないことを保証する。
    ///
    /// 二重計上すると「消せば 2 倍空く」と誤報する。実際に解放されるのは
    /// 最後のリンクを消したときの 1 個分だけ。
    @Test func countsHardlinkedFileOnlyOnce() throws {
        let temp = try TemporaryDirectory()
        let original = try temp.makeFile("original.bin", bytes: 1_000_000)
        try FileManager.default.linkItem(at: original, to: temp.url.appending(path: "link.bin"))

        let measurement = measureDirectory(at: temp.url) { false }

        #expect(measurement.fileCount == 1, "ハードリンクは 1 実体として数える")
        #expect(measurement.allocatedSize < 1_200_000, "2 倍に計上されている")
    }

    /// スパースファイルを論理サイズではなく実割り当て量で数えることを保証する。
    ///
    /// `.fileSizeKey` (論理サイズ) を使っていたらこのテストが落ちる。Docker.raw
    /// のように論理 64GB / 実 9GB のファイルで壊滅的に誤報するため。
    @Test func countsSparseFileByAllocationNotLogicalSize() throws {
        let temp = try TemporaryDirectory()
        let sparse = temp.url.appending(path: "sparse.img")
        try makeSparseFile(at: sparse, logicalBytes: 200 * 1024 * 1024)  // 論理 200MB

        let measurement = measureDirectory(at: temp.url) { false }

        #expect(measurement.fileCount == 1)
        #expect(
            measurement.allocatedSize < 1024 * 1024,
            "論理サイズ (200MB) を数えている。allocated 系のキーを使うこと")
    }

    /// 読めないサブツリーがあっても走査は完走し、skippedCount に計上される
    /// ことを保証する。
    ///
    /// 権限のないディレクトリ 1 つで走査全体が落ちると、「一部が見えない」が
    /// 「何も見えない」に化ける。
    @Test func continuesPastUnreadableSubtreeAndCountsIt() throws {
        let temp = try TemporaryDirectory()
        try temp.makeFile("readable.bin", bytes: 100_000)
        let locked = try temp.makeDirectory("locked")
        try temp.makeFile("locked/hidden.bin", bytes: 500_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let measurement = measureDirectory(at: temp.url) { false }

        #expect(measurement.fileCount >= 1, "読める分は数えられている")
        #expect(measurement.skippedCount > 0, "読めなかったことが記録されている")
    }

    /// キャンセルが巨大な単一ディレクトリの途中でも効くことを保証する。
    ///
    /// ディレクトリ単位でしかキャンセルを見ないと、node_modules のような
    /// 巨大な単一ディレクトリに入った瞬間から数十秒効かなくなる。
    @Test func cancellationTakesEffectMidEnumeration() throws {
        let temp = try TemporaryDirectory()
        // 1 ディレクトリに大量のファイルを平置きする (階層で逃げられない状況)。
        for index in 0..<2000 {
            try temp.makeFile("flat/f\(index).bin", bytes: 128)
        }

        var seen = 0
        let measurement = measureDirectory(at: temp.url) {
            seen += 1
            return seen > 50  // 50 件見たところでキャンセル
        }

        #expect(measurement.wasCancelled, "キャンセルされたことが結果に現れる")
        #expect(measurement.fileCount < 2000, "キャンセル後も全件走査している")
    }

    /// ディレクトリとシンボリックリンク自体をファイルとして数えないことを保証する。
    ///
    /// シンボリックリンクのサイズを数えるとリンク先を二重計上しうる。
    @Test func ignoresDirectoriesAndSymlinks() throws {
        let temp = try TemporaryDirectory()
        let target = try temp.makeFile("target.bin", bytes: 100_000)
        try temp.makeDirectory("emptydir")
        try FileManager.default.createSymbolicLink(
            at: temp.url.appending(path: "alias.bin"), withDestinationURL: target)

        let measurement = measureDirectory(at: temp.url) { false }

        #expect(measurement.fileCount == 1, "通常ファイルだけを数える")
    }

    /// バンドル (.app など) の中身も数えることを保証する。
    ///
    /// `.skipsPackageDescendants` を付けると、キャッシュ配下の .app や
    /// .framework の中身が丸ごと数から漏れる。実測では ~/Library/Caches で
    /// 5.624 GiB が 3.484 GiB に落ちた (2.14 GiB の過小報告)。中身も削除対象
    /// なので、必ず数える。
    @Test func countsContentsInsideBundles() throws {
        let temp = try TemporaryDirectory()
        // Finder がパッケージとして扱う拡張子のディレクトリを作る。
        try temp.makeFile("Some.app/Contents/MacOS/binary", bytes: 500_000)
        try temp.makeFile("outside.bin", bytes: 100_000)

        let measurement = measureDirectory(at: temp.url) { false }

        #expect(measurement.fileCount == 2, "バンドル内のファイルが数えられていない")
        #expect(measurement.allocatedSize >= 600_000, "バンドル内のサイズが漏れている")
    }

    /// 存在しないパスを渡してもクラッシュせず、空の結果を返すことを保証する。
    ///
    /// ルールが指すパスは実在しないのが正常なので、頻繁に起きる経路。
    @Test func returnsEmptyForMissingPath() throws {
        let temp = try TemporaryDirectory()
        let missing = temp.url.appending(path: "does-not-exist")

        let measurement = measureDirectory(at: missing) { false }

        #expect(measurement.fileCount == 0)
        #expect(measurement.allocatedSize == 0)
    }
}
