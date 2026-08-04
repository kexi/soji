import Foundation

/// スキャン結果 1 件 = 「実在して、サイズが判明した」削除候補。
///
/// `CleanRule` が「消せるかもしれない場所の定義」なのに対し、こちらは実際に
/// ディスク上に存在してサイズを測り終えたもの。UI が扱うのは常にこちら。
public struct CleanTarget: Sendable, Identifiable, Hashable {

    /// `ruleID` と URL から導く安定した識別子。
    ///
    /// `expandsChildren` で 1 ルールが複数ターゲットに展開されるため、
    /// ruleID だけでは一意にならない。
    public let id: String

    public let ruleID: String

    public let toolName: String

    public let displayName: String

    public let url: URL

    public let risk: Risk

    /// `.totalFileAllocatedSizeKey` の合計 (バイト)。
    ///
    /// APFS のクローンを二重計上するため厳密値ではない。`du` も同じ嘘をつくので
    /// 数値としては `du` と整合するが、実際に解放される量はこれ以下になる。
    /// UI では必ず「概算」と明示すること。
    public let allocatedSize: Int64

    public let fileCount: Int

    /// 走査中に権限等で読めなかった項目の数。0 でなければ UI に注記を出す。
    public let skippedCount: Int

    public let rationale: String

    public let consequence: String

    public let isAdvisory: Bool

    public let advisoryCommand: String?

    public init(
        ruleID: String,
        toolName: String,
        displayName: String,
        url: URL,
        risk: Risk,
        allocatedSize: Int64,
        fileCount: Int,
        skippedCount: Int,
        rationale: String,
        consequence: String,
        isAdvisory: Bool = false,
        advisoryCommand: String? = nil
    ) {
        self.id = "\(ruleID)|\(url.path(percentEncoded: false))"
        self.ruleID = ruleID
        self.toolName = toolName
        self.displayName = displayName
        self.url = url
        self.risk = risk
        self.allocatedSize = allocatedSize
        self.fileCount = fileCount
        self.skippedCount = skippedCount
        self.rationale = rationale
        self.consequence = consequence
        self.isAdvisory = isAdvisory
        self.advisoryCommand = advisoryCommand
    }
}
