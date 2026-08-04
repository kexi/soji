import ArgumentParser
import Foundation
import SojiKit

/// スキャンして、指定された条件で候補を絞り込む。
///
/// scan と clean が同じ結果を返すことを保証するため、両者はこの 1 経路を通る。
/// ここが分かれると「scan で見えたのに clean で消えない」が起きる。
func scanAndFilter(_ filter: FilterOptions) async throws -> [CleanTarget] {
    let risks = try parseRisks(filter.risk)

    var targets: [CleanTarget] = []
    for await event in TargetScanner().scan() {
        guard case .found(let target) = event else { continue }
        targets.append(target)
    }

    let tools = Set(filter.tool)
    let rules = Set(filter.rule)

    return
        targets
        .filter { risks.contains($0.risk) }
        .filter { tools.isEmpty || tools.contains($0.toolName) }
        .filter { rules.isEmpty || rules.contains($0.ruleID) }
        .filter { $0.allocatedSize >= filter.minBytes }
        .filter { filter.includeAdvisory || !$0.isAdvisory }
        .sorted { $0.allocatedSize > $1.allocatedSize }
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
