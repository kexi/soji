import Foundation
import Testing

@testable import SojiKit

/// ルールのパス解決が保証すること。
///
/// Why 実ホームを使わないか: テストが実行環境のキャッシュの有無に左右されると、
/// 「あるマシンでだけ落ちる」テストになる。さらに、実ホームを指したまま削除の
/// テストを書くと事故になる。すべて一時ディレクトリで完結させる。
@Suite("PathResolver")
struct PathResolverTests {

    /// 実在するディレクトリだけを候補として返すことを保証する。
    ///
    /// ルールが指すパスは「実在しないのが正常」。存在しないものを候補に出すと
    /// UI が空の削除候補で埋まる。
    @Test func returnsOnlyExistingDirectories() throws {
        let temp = try TemporaryDirectory()
        try temp.makeDirectory("Library/Caches/present")

        let rule = makeRule(locations: [.init("Library/Caches/present"), .init("Library/Caches/absent")])
        let resolver = PathResolver(home: temp.url, environment: [:])

        let resolved = resolver.resolve(rule)

        #expect(resolved.count == 1)
        #expect(resolved.first?.url.lastPathComponent == "present")
    }

    /// ファイルをディレクトリと誤認しないことを保証する。
    @Test func ignoresRegularFiles() throws {
        let temp = try TemporaryDirectory()
        try temp.makeFile("Library/Caches/notADirectory", bytes: 10)

        let rule = makeRule(locations: [.init("Library/Caches/notADirectory")])
        let resolved = PathResolver(home: temp.url, environment: [:]).resolve(rule)

        #expect(resolved.isEmpty)
    }

    /// expandsChildren が直下の各ディレクトリを個別の候補に展開することを保証する。
    ///
    /// DerivedData を「今触っているプロジェクトだけ残す」ために使う。
    @Test func expandsChildrenIntoIndividualTargets() throws {
        let temp = try TemporaryDirectory()
        try temp.makeDirectory("DerivedData/ProjectA-abc")
        try temp.makeDirectory("DerivedData/ProjectB-def")
        try temp.makeFile("DerivedData/stray.log", bytes: 10)

        let rule = makeRule(locations: [.init("DerivedData", expandsChildren: true)])
        let resolved = PathResolver(home: temp.url, environment: [:]).resolve(rule)

        #expect(resolved.count == 2, "ディレクトリだけを展開する")
        #expect(Set(resolved.map(\.displayName)) == ["ProjectA-abc", "ProjectB-def"])
    }

    /// 環境変数がツールのホームを移動していれば、そちらを見ることを保証する。
    ///
    /// CARGO_HOME=/opt/cargo なら ".cargo/registry/cache" は
    /// "/opt/cargo/registry/cache" を指す。ホーム相対のままだと存在しない
    /// パスを見て「キャッシュ無し」と誤報する。
    @Test func honorsEnvironmentOverride() throws {
        let temp = try TemporaryDirectory()
        let elsewhere = try temp.makeDirectory("elsewhere/registry/cache")
        let home = try temp.makeDirectory("home")

        let rule = makeRule(
            locations: [.init(".cargo/registry/cache")],
            environmentOverride: .init("CARGO_HOME", replaces: ".cargo")
        )
        let resolver = PathResolver(
            home: home,
            environment: ["CARGO_HOME": temp.url.appending(path: "elsewhere").path]
        )

        let resolved = resolver.resolve(rule)

        #expect(resolved.count == 1)
        #expect(resolved.first?.url.samePath(as: elsewhere) == true)
    }

    /// 環境変数の prefix に当たらない location はホーム相対のまま解決される
    /// ことを保証する。
    ///
    /// pnpm は "Library/pnpm/store" と ".local/share/pnpm/store" の 2 つを
    /// 持つが、PNPM_HOME が置き換えるのは前者だけ。先頭 1 要素だけを機械的に
    /// 置換する実装だと、後者が無関係なパスを指してしまう。
    @Test func leavesUnmatchedLocationsRelativeToHome() throws {
        let temp = try TemporaryDirectory()
        let home = try temp.makeDirectory("home")
        let fallback = try temp.makeDirectory("home/.local/share/pnpm/store")

        let rule = makeRule(
            locations: [
                .init("Library/pnpm/store"),
                .init(".local/share/pnpm/store"),
            ],
            environmentOverride: .init("PNPM_HOME", replaces: "Library/pnpm")
        )
        // PNPM_HOME は存在しない場所を指す (= 前者は候補から落ちる)。
        let resolver = PathResolver(
            home: home,
            environment: ["PNPM_HOME": temp.url.appending(path: "nonexistent").path]
        )

        let resolved = resolver.resolve(rule)

        #expect(resolved.count == 1, "prefix に当たらない location が失われている")
        #expect(resolved.first?.url.samePath(as: fallback) == true)
    }

    /// 環境変数が空文字なら無視してホーム相対で解決することを保証する。
    ///
    /// `export CARGO_HOME=` のような設定でホームが `/` 側に化けると、
    /// 無関係なパスを削除候補に出しかねない。
    @Test func ignoresEmptyEnvironmentValue() throws {
        let temp = try TemporaryDirectory()
        let home = try temp.makeDirectory("home")
        let expected = try temp.makeDirectory("home/.cargo/registry/cache")

        let rule = makeRule(
            locations: [.init(".cargo/registry/cache")],
            environmentOverride: .init("CARGO_HOME", replaces: ".cargo")
        )
        let resolver = PathResolver(home: home, environment: ["CARGO_HOME": ""])

        let resolved = resolver.resolve(rule)

        #expect(resolved.first?.url.samePath(as: expected) == true)
    }

    private func makeRule(
        locations: [CleanRule.Location],
        environmentOverride: CleanRule.EnvironmentOverride? = nil
    ) -> CleanRule {
        CleanRule(
            id: "test.rule",
            toolName: "Test",
            displayName: "テスト対象",
            locations: locations,
            risk: .safe,
            rationale: "テスト用",
            consequence: "テスト用",
            environmentOverride: environmentOverride
        )
    }
}

extension URL {
    /// 末尾スラッシュの有無を無視してパスを比較する。
    ///
    /// createDirectory が返す URL はディレクトリとして末尾に "/" が付く一方、
    /// PathResolver が組み立てた URL には付かない。standardizedFileURL も
    /// path(percentEncoded:) も末尾スラッシュを落とさないため、明示的に削る。
    func samePath(as other: URL) -> Bool {
        normalizedPath == other.normalizedPath
    }

    private var normalizedPath: String {
        let path = standardizedFileURL.path(percentEncoded: false)
        let isBareRoot = path == "/"
        if isBareRoot { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
