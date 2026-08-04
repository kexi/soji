import Foundation

/// ルールのホーム相対パスを、実在する絶対 URL に解決する。
///
/// 環境変数による移動 (`CARGO_HOME` 等) を尊重し、実在しないパスは落とす。
/// ルールが指すパスは「実在しないのが正常」なので、存在判定は失敗ではない。
public struct PathResolver: Sendable {

    /// ホームディレクトリ。
    ///
    /// Why 注入可能にするか: テストで実ホームを触らせないため。
    /// サンドボックス下では `FileManager.homeDirectoryForCurrentUser` が
    /// コンテナを返すが、soji は非サンドボックスなので実ホームが返る。
    let home: URL

    /// 環境変数の参照。テストで差し替える。
    let environment: [String: String]

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.home = home
        self.environment = environment
    }

    /// ルール 1 件を、実在する削除候補の URL 群に解決する。
    ///
    /// `expandsChildren` が指定された location は、直下のエントリごとに
    /// 展開する (DerivedData をプロジェクト単位で選ばせるため)。
    public func resolve(_ rule: CleanRule) -> [ResolvedLocation] {
        var results: [ResolvedLocation] = []

        for location in rule.locations {
            guard let base = absoluteURL(for: location, rule: rule) else { continue }
            guard isDirectory(base) else { continue }

            if location.expandsChildren {
                let children =
                    (try? FileManager.default.contentsOfDirectory(
                        at: base,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [])) ?? []
                for child in children where isDirectory(child) {
                    results.append(ResolvedLocation(url: child, displayName: child.lastPathComponent))
                }
            } else {
                results.append(ResolvedLocation(url: base, displayName: rule.displayName))
            }
        }

        return results
    }

    /// location をホーム相対または環境変数由来の絶対 URL に変換する。
    ///
    /// 環境変数が設定されていれば既定のホーム相対パスより優先する。
    /// 例: `CARGO_HOME=/opt/cargo` なら `.cargo/registry/cache` は
    /// `/opt/cargo/registry/cache` を指す。
    private func absoluteURL(for location: CleanRule.Location, rule: CleanRule) -> URL? {
        let homeRelative = home.appending(path: location.relativePath).standardizedFileURL

        guard let override = rule.environmentOverride else { return homeRelative }
        guard let root = environment[override.variable], !root.isEmpty else { return homeRelative }
        guard let suffix = suffix(of: location.relativePath, after: override.replaces) else {
            return homeRelative
        }

        let overrideRoot = URL(fileURLWithPath: root).standardizedFileURL
        let isWholeToolHome = suffix.isEmpty
        return isWholeToolHome
            ? overrideRoot
            : overrideRoot.appending(path: suffix).standardizedFileURL
    }

    /// `relativePath` が `prefix` で始まるなら、残りのサブパスを返す。
    ///
    /// Why prefix 一致を要求するか: 1 つのルールが複数の location を持つとき、
    /// 環境変数が当たるのは片方だけということがある (pnpm の
    /// `Library/pnpm/store` と `.local/share/pnpm/store`)。当たらない方は
    /// nil を返してホーム相対の解決に落とす。
    private func suffix(of relativePath: String, after prefix: String) -> String? {
        let pathComponents = relativePath.split(separator: "/").map(String.init)
        let prefixComponents = prefix.split(separator: "/").map(String.init)
        guard pathComponents.starts(with: prefixComponents) else { return nil }
        return pathComponents.dropFirst(prefixComponents.count).joined(separator: "/")
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}

/// 解決済みの削除候補の場所。
public struct ResolvedLocation: Sendable, Hashable {
    public let url: URL

    /// UI に出す名前。`expandsChildren` で展開された場合は子の名前になる。
    public let displayName: String
}
