import Foundation

/// 組み込みルール 1 件。「どのツールの、どのパスが、なぜ消せるか」を持つ。
///
/// Why not 外部設定ファイル: ルールにはパス以外に「なぜ安全か」の判断が埋まって
/// おり、これを JSON に出すと判断の根拠がコードレビューの外に出る。ユーザーが
/// 独自ルールを足したくなったら、その時に拡張点を切る。
public struct CleanRule: Sendable, Identifiable, Hashable {

    /// 環境変数によるツールのホーム移動。
    ///
    /// `CARGO_HOME` は `~/.cargo` を、`PNPM_HOME` は `~/Library/pnpm` を
    /// 置き換える。変数ごとに「相対パスのどこまでを置き換えるか」が違うため、
    /// 置換対象を prefix として明示させる。
    ///
    /// Why 先頭 1 要素の置換で済ませないか: PNPM_HOME が置き換えるのは
    /// `Library/pnpm` の 2 階層で、先頭だけ置換すると `Library` が消えて
    /// 無関係なパスを指す。
    public struct EnvironmentOverride: Sendable, Hashable {
        /// 環境変数名 (`CARGO_HOME` 等)。
        public let variable: String

        /// この変数が置き換えるホーム相対の prefix (`".cargo"`, `"Library/pnpm"`)。
        public let replaces: String

        public init(_ variable: String, replaces: String) {
            self.variable = variable
            self.replaces = replaces
        }
    }

    /// ルールが指す場所ひとつ。
    public struct Location: Sendable, Hashable {
        /// ホームディレクトリからの相対パス。`PathResolver` が絶対 URL に解決する。
        public let relativePath: String

        /// true なら `relativePath` 直下の各エントリを個別の削除単位に展開する。
        ///
        /// DerivedData のように「プロジェクトごとに残すか決めたい」場所で使う。
        public let expandsChildren: Bool

        /// 展開した子のうち、これ未満のものは親にまとめる (バイト)。
        ///
        /// Why 必要か: CoreSimulator/Devices は実機で 88 件に展開され、その
        /// 大半が 18MB 以下の未起動デバイスだった。一覧がノイズで埋まり、
        /// 本当に消したい上位 (数十 GB) が見えなくなる。小さい子は 1 行に
        /// まとめて「その他 N 件」として扱う。
        public let childThreshold: Int64

        public init(
            _ relativePath: String,
            expandsChildren: Bool = false,
            childThreshold: Int64 = 0
        ) {
            self.relativePath = relativePath
            self.expandsChildren = expandsChildren
            self.childThreshold = childThreshold
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

    /// パスを上書きする環境変数による移動先の指定。
    public let environmentOverride: EnvironmentOverride?

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
        environmentOverride: EnvironmentOverride? = nil,
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
