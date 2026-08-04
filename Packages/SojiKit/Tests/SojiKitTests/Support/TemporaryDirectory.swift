import Foundation

/// テスト用の一時ディレクトリ。スコープを抜けたら必ず消える。
///
/// Why UUID で毎回分けるか: swift-testing は既定でテストを並列実行するため、
/// 固定名だとテスト同士が同じパスを掴んで互いの前提を壊す。
///
/// Why ~Copyable か: コピーできると deinit が複数回走り、まだ使っている
/// 側のディレクトリを消してしまう。所有権を 1 つに固定する。
struct TemporaryDirectory: ~Copyable {
    let url: URL

    init() throws {
        url = URL.temporaryDirectory.appending(path: "soji-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        // 読み取り専用属性を付けたテストがあるので、消す前に書き込み権限を戻す。
        // そうしないとテストが一時ファイルを残したままになる。
        restoreWritePermissions(at: url)
        try? FileManager.default.removeItem(at: url)
    }

    /// ツリー内に通常ファイルを作る。中間ディレクトリは自動で作る。
    @discardableResult
    func makeFile(_ relativePath: String, bytes: Int) throws -> URL {
        let fileURL = url.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: fileURL)
        return fileURL
    }

    @discardableResult
    func makeDirectory(_ relativePath: String) throws -> URL {
        let dirURL = url.appending(path: relativePath)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        return dirURL
    }

    private func restoreWritePermissions(at root: URL) {
        let manager = FileManager.default
        guard
            let enumerator = manager.enumerator(
                at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in true })
        else { return }
        for case let item as URL in enumerator {
            try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: item.path)
        }
        try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
    }
}

/// APFS のスパースファイルを作る。
///
/// `truncate` で論理サイズだけ伸ばし、実ブロックは割り当てない。Docker.raw の
/// ような「論理 64GB / 実 9GB」を再現するために使う。
func makeSparseFile(at url: URL, logicalBytes: off_t) throws {
    let descriptor = open(url.path, O_CREAT | O_WRONLY, 0o644)
    guard descriptor >= 0 else { throw POSIXError(.EIO) }
    defer { close(descriptor) }
    guard ftruncate(descriptor, logicalBytes) == 0 else { throw POSIXError(.EIO) }
}
