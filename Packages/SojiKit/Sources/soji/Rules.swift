import ArgumentParser
import Foundation
import SojiKit

struct Rules: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "組み込みルールを一覧する。ディスクは走査しない。",
        discussion: """
            「何を消すと何が起きるか」の一覧。実際に存在するかどうかは見ないので
            即座に返る。判断材料が欲しいときはこちらを読む。
            """
    )

    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "危険度で絞り込む (safe, slowToRebuild, needsConfirmation)。")
    var risk: [String] = []

    @Flag(name: .long, help: "ツール自身のコマンドに委ねるルールだけを出す。")
    var advisoryOnly = false

    func run() throws {
        let risks = risk.isEmpty ? Set(Risk.allCases) : try parseRisks(risk)
        let rules =
            BuiltinRules.all
            .filter { risks.contains($0.risk) }
            .filter { !advisoryOnly || $0.isAdvisory }

        guard output.json else {
            printHuman(rules)
            return
        }
        try printJSON(rules.map(RuleDescription.init(rule:)))
    }

    private func printHuman(_ rules: [CleanRule]) {
        for rule in rules {
            let marker = rule.isAdvisory ? "!" : " "
            print("\(marker) \(rule.id)  [\(rule.risk.identifier)]  \(rule.toolName)/\(rule.displayName)")
            for location in rule.locations {
                print("    ~/\(location.relativePath)")
            }
            print("    なぜ安全か: \(rule.rationale)")
            print("    消えると:   \(rule.consequence)")
            if let command = rule.advisoryCommand {
                print("    実行すべきコマンド: \(command)")
            }
            print("")
        }
        print("\(rules.count) 件のルール")
    }
}

/// ルール 1 件の機械可読な表現。
private struct RuleDescription: Encodable {
    let id: String
    let tool: String
    let name: String
    let paths: [String]
    let risk: String
    let rationale: String
    let consequence: String
    let advisory: Bool
    let command: String?
    let environmentOverride: String?
    let selectedByDefault: Bool

    init(rule: CleanRule) {
        id = rule.id
        tool = rule.toolName
        name = rule.displayName
        paths = rule.locations.map { "~/" + $0.relativePath }
        risk = rule.risk.identifier
        rationale = rule.rationale
        consequence = rule.consequence
        advisory = rule.isAdvisory
        command = rule.advisoryCommand
        environmentOverride = rule.environmentOverride?.variable
        selectedByDefault = rule.risk.isSelectedByDefault && !rule.isAdvisory
    }
}
