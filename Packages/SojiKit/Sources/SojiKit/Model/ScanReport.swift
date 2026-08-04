import Foundation

/// スキャン結果全体の、機械可読な表現。
///
/// Why SojiKit に置くか: CLI の --json 出力と GUI が同じ語彙を使うため。
/// CLI 側で組み立てると、GUI が見せている数字と CLI が返す数字が
/// いつのまにかずれる。
public struct ScanReport: Sendable, Codable {

    public struct Entry: Sendable, Codable {
        public let id: String
        public let ruleID: String
        public let tool: String
        public let name: String
        public let path: String

        /// まとめられた行なら、実際に削除される場所すべて。
        public let paths: [String]

        /// "safe" | "slowToRebuild" | "needsConfirmation"
        public let risk: String

        public let bytes: Int64
        public let humanSize: String
        public let fileCount: Int

        /// 権限などで読めなかった項目数。0 でなければサイズは実際より小さい。
        public let skippedCount: Int

        /// なぜ消して安全か。
        public let rationale: String

        /// 消すと何が起きるか。
        public let consequence: String

        /// true なら soji は削除せず、`command` の実行を促す。
        public let advisory: Bool

        /// advisory のときに実行すべきコマンド。
        public let command: String?

        /// 既定の選択に含まれるか (safe かつ非 advisory)。
        public let selectedByDefault: Bool
    }

    public struct Totals: Sendable, Codable {
        /// soji が削除できる量。同じ場所を指す複数ルールは 1 回だけ数える。
        public let reclaimableBytes: Int64
        public let humanReclaimable: String

        /// soji は削除せず、ツール自身のコマンドに委ねる量。
        public let advisoryBytes: Int64
        public let humanAdvisory: String

        public let entryCount: Int
    }

    public struct Volume: Sendable, Codable {
        /// 今すぐ使える空き。
        public let availableBytes: Int64

        /// Finder が表示する空き (purgeable 込み)。
        public let availableForImportantUsageBytes: Int64

        /// macOS が必要時に自動解放する分。
        public let purgeableBytes: Int64

        public let totalBytes: Int64
    }

    public let entries: [Entry]
    public let totals: Totals
    public let volume: Volume?

    public init(targets: [CleanTarget], volume capacity: VolumeCapacity?) {
        entries = targets.map(Entry.init(target:))
        totals = Totals(
            reclaimableBytes: targets.reclaimableBytes,
            humanReclaimable: targets.reclaimableBytes.formattedAsBytes,
            advisoryBytes: targets.advisoryBytes,
            humanAdvisory: targets.advisoryBytes.formattedAsBytes,
            entryCount: targets.count
        )
        volume = capacity.map { capacity in
            Volume(
                availableBytes: capacity.available,
                availableForImportantUsageBytes: capacity.availableForImportantUsage,
                purgeableBytes: capacity.purgeable,
                totalBytes: capacity.total
            )
        }
    }
}

extension ScanReport.Entry {
    init(target: CleanTarget) {
        id = target.id
        ruleID = target.ruleID
        tool = target.toolName
        name = target.displayName
        path = target.url.path(percentEncoded: false)
        paths = target.deletionURLs.map { $0.path(percentEncoded: false) }
        risk = target.risk.identifier
        bytes = target.allocatedSize
        humanSize = target.allocatedSize.formattedAsBytes
        fileCount = target.fileCount
        skippedCount = target.skippedCount
        rationale = target.rationale
        consequence = target.consequence
        advisory = target.isAdvisory
        command = target.advisoryCommand
        selectedByDefault = target.risk.isSelectedByDefault && !target.isAdvisory
    }
}

extension Risk {
    /// JSON やコマンドライン引数で使う安定した文字列表現。
    ///
    /// Why rawValue の数値を使わないか: 危険度の順序を保つために enum の
    /// 数値を変えたくなったとき、外部との契約が壊れる。
    public var identifier: String {
        switch self {
        case .safe: return "safe"
        case .slowToRebuild: return "slowToRebuild"
        case .needsConfirmation: return "needsConfirmation"
        }
    }

    public init?(identifier: String) {
        switch identifier {
        case "safe": self = .safe
        case "slowToRebuild": self = .slowToRebuild
        case "needsConfirmation": self = .needsConfirmation
        default: return nil
        }
    }
}

extension Int64 {
    /// 人間が読むサイズ表記。
    var formattedAsBytes: String {
        formatted(.byteCount(style: .file))
    }
}
