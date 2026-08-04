import Foundation

/// 組み込みルール 1 件。「どのツールの、どのパスが、なぜ消せるか」を持つ。
///
/// Why not 外部設定ファイル: ルールにはパス以外に「なぜ安全か」の判断が埋まって
/// おり、これを JSON に出すと判断の根拠がコードレビューの外に出る。ユーザーが
/// 独自ルールを足したくなったら、その時に拡張点を切る。
public struct CleanRule: Sendable, Identifiable, Hashable {

    /// ルールが指す場所ひとつ。
    public struct Location: Sendable, Hashable {
        /// ホームディレクトリからの相対パス。`PathResolver` が絶対 URL に解決する。
        public let relativePath: String

        /// true なら `relativePath` 直下の各エントリを個別の削除単位に展開する。
        ///
        /// DerivedData のように「プロジェクトごとに残すか決めたい」場所で使う。
        public let expandsChildren: Bool

        public init(_ relativePath: String, expandsChildren: Bool = false) {
            self.relativePath = relativePath
            self.expandsChildren = expandsChildren
        }
    }

    /// 安定した識別子。`"homebrew.downloads"` のようなドット区切り。
    public let id: String

    /// 表示上のグループ名。サイドバーとサンバーストの最内周がこの単位になる。
    public let toolName: String

    /// このルールが指すものの名前。
    public let displayName: String

    public let locations: [Location]

    public let risk: Risk

    /// なぜ消して安全なのか。UI にそのまま出してユーザーの判断材料にする。
    public let rationale: String

    /// 消した後に何が起きるか。UI にそのまま出す。
    public let consequence: String

    /// パスを上書きする環境変数名 (`CARGO_HOME`, `GOPATH` 等)。
    ///
    /// 設定されていればホーム相対の既定パスより優先する。
    public let environmentOverride: String?

    /// true なら削除せず、代わりに `advisoryCommand` を案内する。
    ///
    /// Docker のように、ファイルを直接消すとツール自身が壊れるものに使う。
    public let isAdvisory: Bool

    /// `isAdvisory` のときにユーザーへ提示するコマンド。
    public let advisoryCommand: String?

    public init(
        id: String,
        toolName: String,
        displayName: String,
        locations: [Location],
        risk: Risk,
        rationale: String,
        consequence: String,
        environmentOverride: String? = nil,
        isAdvisory: Bool = false,
        advisoryCommand: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.displayName = displayName
        self.locations = locations
        self.risk = risk
        self.rationale = rationale
        self.consequence = consequence
        self.environmentOverride = environmentOverride
        self.isAdvisory = isAdvisory
        self.advisoryCommand = advisoryCommand
    }
}
