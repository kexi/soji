import ArgumentParser
import Foundation
import SojiKit

/// スキャンして、指定された条件で候補を絞り込む。
///
/// scan と clean が同じ結果を返すことを保証するため、両者はこの 1 経路を通る。
///
/// - Parameter showsProgress: 走査の進捗を stderr に出すか。
///   Why stderr か: stdout は --json のパイプ先が読む。進捗を混ぜると
///   JSON パーサが壊れる。
func scanAndFilter(
    _ options: FilterOptions,
    showsProgress: Bool = false,
    forDeletion: Bool = false
) async throws -> [CleanTarget] {
    let parsed = try options.makeFilter()
    // Why 型で落とすか: advisory はツール自身のコマンドでしか安全に消せない。
    // 呼び出し側でフラグを手で倒す書き方だと、経路が増えたときに落とし忘れる。
    let filter = forDeletion ? parsed.forDeletion : parsed

    var targets: [CleanTarget] = []
    var progress = ProgressReporter(enabled: showsProgress)
    let scanner = TargetScanner(resolver: try options.makeResolver())

    for await event in scanner.scan() {
        switch event {
        case .found(let target):
            targets.append(target)
        case .progress(let completed, let total):
            progress.update(completed: completed, total: total)
        }
    }
    progress.finish()

    return targets.filtered(by: filter)
}

extension FilterOptions {
    /// --home が指定されていればそこを、無ければ実ホームを見る resolver。
    func makeResolver() throws -> PathResolver {
        guard let home else { return PathResolver() }

        let url = URL(fileURLWithPath: (home as NSString).expandingTildeInPath)
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            throw ValidationError("--home に指定した '\(home)' はディレクトリではありません。")
        }
        return PathResolver(home: url)
    }

    func makeFilter() throws -> TargetFilter {
        TargetFilter(
            risks: try parseRisks(risk),
            tools: Set(tool),
            ruleIDs: Set(rule),
            minimumBytes: minBytes,
            includesAdvisory: includeAdvisory
        )
    }
}

func parseRisks(_ identifiers: [String]) throws -> Set<Risk> {
    var risks: Set<Risk> = []
    for identifier in identifiers {
        guard let risk = Risk(identifier: identifier) else {
            let valid = Risk.allCases.map(\.identifier).joined(separator: ", ")
            throw ValidationError("不明な危険度 '\(identifier)'。指定できるのは: \(valid)")
        }
        risks.insert(risk)
    }
    return risks
}

/// 走査の進捗を stderr に 1 行で出す。
///
/// Why 必要か: 100 万ファイル規模のスキャンは 30 秒ほど無反応になる。
/// 人間もエージェントも「止まっているのか動いているのか」を判断できないと、
/// 途中で打ち切ってしまう。
struct ProgressReporter {
    let enabled: Bool
    private var lastRendered = ""

    init(enabled: Bool) {
        // 端末でないなら進捗は出さない。パイプやリダイレクト先に
        // 上書き用のエスケープが混ざると読みにくくなる。
        self.enabled = enabled && isatty(FileHandle.standardError.fileDescriptor) == 1
    }

    mutating func update(completed: Int, total: Int) {
        guard enabled, total > 0 else { return }
        let line = "走査中 \(completed)/\(total)"
        guard line != lastRendered else { return }
        lastRendered = line
        FileHandle.standardError.write(Data("\r\u{1B}[K\(line)".utf8))
    }

    func finish() {
        guard enabled, !lastRendered.isEmpty else { return }
        FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
    }
}

/// JSON を安定した形で出力する。
///
/// Why sortedKeys か: 出力を差分で比較できるようにするため。エージェントが
/// 前回との違いを見たいときに、キー順が揺れると差分がノイズだらけになる。
func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(value)
    data.append(0x0A)  // 末尾改行。パイプ先の行指向ツールが扱いやすい。

    // Why String を経由しないか: JSONEncoder の出力は定義上 UTF-8 のバイト列
    // なので、String に変換して print で書き戻すのは往復の無駄。
    FileHandle.standardOutput.write(data)
}

/// 標準エラーに 1 行書く。
func printToStandardError(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

extension CleanTarget {
    /// 人間向けの 1 行表記。
    var summaryLine: String {
        let size = allocatedSize.formatted(.byteCount(style: .file))
        let marker = isAdvisory ? "!" : " "
        return "\(marker) \(size.paddedLeft(to: 10))  \(toolName)/\(displayName)"
    }
}

extension String {
    func paddedLeft(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
