import ArgumentParser
import Foundation

@main
struct Soji: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "soji",
        abstract: "開発者向けキャッシュとビルド成果物を掃除する。",
        discussion: """
            GUI 版 (Soji.app) と同じロジックの上に立つ。GUI でできることは
            すべて CLI でもできる。

            AI エージェントから使う場合:
              soji scan --json          候補を構造化 JSON で得る
              soji clean --json         何が消えるかを確認する (既定は dry-run)
              soji clean --yes          実際に削除する
              soji rules --json         「何を消すと何が起きるか」を読む

            削除は --yes を明示しない限り実行しない。
            """,
        version: "0.1.0",
        subcommands: [Scan.self, Clean.self, Rules.self],
        defaultSubcommand: Scan.self
    )
}

/// 候補を絞り込む共通の条件。scan と clean で同じ書き味にする。
struct FilterOptions: ParsableArguments {
    @Option(
        name: .long,
        help: "対象にする危険度 (safe, slowToRebuild, needsConfirmation)。既定は safe のみ。")
    var risk: [String] = ["safe"]

    @Option(name: .long, help: "ツール名で絞り込む (例: --tool Homebrew)。複数指定可。")
    var tool: [String] = []

    @Option(name: .long, help: "ルール ID で絞り込む (例: --rule homebrew.downloads)。複数指定可。")
    var rule: [String] = []

    @Option(name: .long, help: "このバイト数未満の候補を除外する。")
    var minBytes: Int64 = 0

    @Flag(name: .long, help: "ツール自身のコマンドに委ねる項目 (Docker 等) も一覧に含める。")
    var includeAdvisory = false

    // Why 環境変数ではなくオプションか: FileManager.homeDirectoryForCurrentUser は
    // getpwuid を読むため HOME を差し替えても効かない。隔離した場所で試したい
    // ときに、環境変数では意図が通らず実ホームを消しかねない。
    @Option(name: .long, help: "ホームディレクトリを差し替える。検証用。", completion: .directory)
    var home: String?
}

/// 出力形式の共通オプション。
struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "機械可読な JSON で出力する。")
    var json = false
}

/// 終了コード。エージェントが分岐に使えるよう意味を固定する。
enum ExitCode: Int32 {
    /// 正常終了。
    case success = 0
    /// 削除中に失敗した項目があった。
    case partialFailure = 3
}
