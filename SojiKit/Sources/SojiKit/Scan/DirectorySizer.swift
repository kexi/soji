import Foundation

/// ディレクトリツリーを再帰的に走査し、割り当て済みサイズを合計する。
///
/// 「このディレクトリを消したら何バイト空くか」に答えるための計測。
///
/// - Parameters:
///   - url: 走査するディレクトリ。存在しなくてもエラーにはならず空の結果を返す。
///   - isCancelled: 各ファイルごとに評価される中断条件。
///
/// - Note: APFS のクローンは検出できず二重に計上する (`du` も同じ)。実際に
///   解放される量はこの戻り値以下になる。
public func measureDirectory(at url: URL, isCancelled: () -> Bool) -> DirectoryMeasurement {
    // Why ここに全キーを列挙するか: enumerator に宣言しなかったキーを後から
    // resourceValues で読むと、ファイルごとに追加の syscall が走る。100 万
    // ファイル規模ではこれが支配的コストになる。
    let keys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .linkCountKey,
        .fileIdentifierKey,
    ]

    var result = DirectoryMeasurement()

    // Why not .skipsHiddenFiles: 対象の大半 (.npm / .gradle / .cargo / .cache)
    // がドットディレクトリなので、付けると本命を丸ごと取り逃がす。
    //
    // Why not .skipsPackageDescendants: 「.app の中身は 1 個の塊」という直感は
    // ここでは有害。実測で ~/Library/Caches に対し 5.624 GiB (du 一致) が
    // 3.484 GiB まで落ちた ― パッケージ扱いされる .app や .framework が
    // キャッシュ配下に多数あり、その中身も削除対象なのに数えられなくなる。
    // 2.14 GiB の過小報告はディスクフル解消という目的を直接損なう。
    let options: FileManager.DirectoryEnumerationOptions = [
        .producesRelativePathURLs
    ]

    // errorHandler の中から更新するのでローカルに置く。
    var skipped = 0

    guard
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: options,
            errorHandler: { _, _ in
                // Why 常に true を返すか: 権限のないサブツリー 1 つで走査全体を
                // 中断すると「一部が見えない」が「何も見えない」に化ける。
                // 読めなかった事実だけ数えて先へ進む。
                skipped += 1
                return true
            }
        )
    else {
        // ディレクトリ自体が開けない (存在しない・権限がない)。
        return DirectoryMeasurement(skippedCount: 1)
    }

    // Why linkCount > 1 の項目だけ Set に入れるか: 実測でハードリンク保有率は
    // 0.07% (56,595 件中 42 件)。全ファイルを入れると 100 万要素のハッシュ集合を
    // 作ることになり、得られる精度に見合わない。
    var seenHardlinkIDs = Set<UInt64>()

    for case let fileURL as URL in enumerator {
        // Why ループの内側で見るか: ディレクトリ単位でしか確認しないと、
        // node_modules のような巨大な単一ディレクトリに入った瞬間から
        // キャンセルが数十秒効かなくなる。
        if isCancelled() {
            result.wasCancelled = true
            break
        }

        guard let values = try? fileURL.resourceValues(forKeys: keys) else {
            skipped += 1
            continue
        }

        // ディレクトリとシンボリックリンクは数えない。前者は中身を個別に数え、
        // 後者はリンク先を二重計上してしまうため。
        guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }

        // 同一実体への 2 本目以降のハードリンクは、消しても容量が空かない。
        let isHardlinked = (values.linkCount ?? 1) > 1
        if isHardlinked, let identifier = values.fileIdentifier {
            // fileIdentifier はプロセス内でのみ有効で永続化してはいけない
            // (NSURL.h が明記)。ここでは 1 回の走査の中だけで使う。
            let isAlreadyCounted = !seenHardlinkIDs.insert(identifier).inserted
            if isAlreadyCounted { continue }
        }

        // Why totalFileAllocatedSize か: 実際に割り当てられたブロック量 (du 相当)。
        // fileSize 系の論理サイズはスパースファイル (Docker.raw の論理 64GB /
        // 実 9GB) で壊滅的に誤報する。
        result.allocatedSize += Int64(values.totalFileAllocatedSize ?? 0)
        result.fileCount += 1
    }

    result.skippedCount = skipped
    return result
}
