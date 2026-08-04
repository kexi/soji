import Foundation
import Testing

@testable import SojiKit

/// 組み込みルール集が満たすべき不変条件。
///
/// ルールを 1 件足すことは「消してよい」という判断を 1 件足すこと。ここは
/// その判断が壊れていないかを機械的に検査する防波堤であり、soji で最も
/// 重要なテストスイート。
@Suite("BuiltinRules")
struct BuiltinRulesTests {

    /// ルール ID が全件で一意であることを保証する。
    ///
    /// ID は CleanTarget の識別子と UI の選択状態の土台なので、重複すると
    /// 「A を選んだつもりで B が消える」が起きうる。
    @Test func ruleIDsAreUnique() {
        let ids = BuiltinRules.all.map(\.id)
        #expect(Set(ids).count == ids.count, "重複した ID: \(duplicates(in: ids))")
    }

    /// すべてのルールが空でない rationale と consequence を持つことを保証する。
    ///
    /// この 2 つはユーザーが削除を判断するための唯一の材料で、UI にそのまま
    /// 出る。空のまま出荷すると「理由の分からない削除候補」になる。
    @Test func everyRuleExplainsItself() {
        for rule in BuiltinRules.all {
            #expect(!rule.rationale.isEmpty, "\(rule.id): rationale が空")
            #expect(!rule.consequence.isEmpty, "\(rule.id): consequence が空")
            #expect(!rule.displayName.isEmpty, "\(rule.id): displayName が空")
            #expect(!rule.toolName.isEmpty, "\(rule.id): toolName が空")
        }
    }

    /// ホームディレクトリ自身や、その直下の広すぎるパスを対象にしないことを保証する。
    ///
    /// これが soji で最も致命的な事故 (ユーザーの全データ削除) を防ぐ検査。
    /// 相対パスが空、`.`、`..` を含む、絶対パス、あるいは第 1 階層しか
    /// 持たない汎用ディレクトリ (Documents 等) はすべて拒否する。
    @Test func noRuleTargetsHomeOrOverlyBroadPaths() {
        // 単独で指定されたら事故になるトップレベル。
        let forbiddenRoots: Set<String> = [
            "", ".", "..", "Library", "Documents", "Desktop", "Downloads",
            "Movies", "Music", "Pictures", "Public", "Applications", "go", "src",
        ]

        for rule in BuiltinRules.all {
            #expect(!rule.locations.isEmpty, "\(rule.id): locations が空")

            for location in rule.locations {
                let path = location.relativePath

                #expect(!path.isEmpty, "\(rule.id): 空のパス")
                #expect(!path.hasPrefix("/"), "\(rule.id): 絶対パス \(path)")
                #expect(!path.hasPrefix("~"), "\(rule.id): チルダ展開前提のパス \(path)")

                let components = path.split(separator: "/").map(String.init)
                #expect(!components.contains(".."), "\(rule.id): 親参照を含む \(path)")
                #expect(!components.contains("."), "\(rule.id): カレント参照を含む \(path)")
                #expect(
                    !forbiddenRoots.contains(path),
                    "\(rule.id): トップレベルを丸ごと指している \(path)")

                // ドットで始まらないパスは、汎用ディレクトリ直下を丸ごと消さない
                // よう最低 2 階層を要求する (".npm/_cacache" のような隠しディレクトリ
                // は 1 階層でもツール専用なので許す)。
                if !path.hasPrefix(".") {
                    #expect(
                        components.count >= 2,
                        "\(rule.id): 階層が浅すぎる \(path)")
                }
            }
        }
    }

    /// needsConfirmation のルールが既定選択に含まれないことを保証する。
    ///
    /// 掃除アプリの事故は「気づかないうちに選択されていた」ものを消して起きる。
    @Test func riskyRulesAreNotSelectedByDefault() {
        for rule in BuiltinRules.all where rule.risk == .needsConfirmation {
            #expect(!rule.risk.isSelectedByDefault, "\(rule.id) が既定選択になっている")
        }
        #expect(Risk.safe.isSelectedByDefault)
        #expect(!Risk.slowToRebuild.isSelectedByDefault)
    }

    /// advisory なルールが必ず代替コマンドを提示することを保証する。
    ///
    /// advisory は「soji では消さない」という宣言なので、代わりに何をすれば
    /// よいかを示せないなら、ユーザーは行き止まりに置かれる。
    @Test func advisoryRulesProvideACommand() {
        for rule in BuiltinRules.all where rule.isAdvisory {
            let command = rule.advisoryCommand ?? ""
            #expect(!command.isEmpty, "\(rule.id): advisory なのにコマンドが無い")
        }
        // 逆に、advisory でないルールがコマンドだけ持つのは定義漏れ。
        for rule in BuiltinRules.all where !rule.isAdvisory {
            #expect(rule.advisoryCommand == nil, "\(rule.id): 非 advisory なのにコマンドがある")
        }
    }

    /// 各ルールが宣言した Risk のグループに正しく属していることを保証する。
    ///
    /// `all` は 3 グループの連結なので、グループと risk がずれると UI の
    /// 既定選択と実際の危険度が食い違う。
    @Test func rulesAreFiledUnderTheirDeclaredRisk() {
        for rule in BuiltinRules.safe {
            #expect(rule.risk == .safe, "\(rule.id) が safe グループにあるが risk が違う")
        }
        for rule in BuiltinRules.slowToRebuild {
            #expect(rule.risk == .slowToRebuild, "\(rule.id) が slowToRebuild グループにあるが risk が違う")
        }
        for rule in BuiltinRules.needsConfirmation {
            #expect(rule.risk == .needsConfirmation, "\(rule.id) が needsConfirmation グループにあるが risk が違う")
        }
    }

    /// ID が "tool.subject" 形式であることを保証する。
    ///
    /// UI のグルーピングと将来の設定永続化が ID の形に依存するため。
    @Test func ruleIDsFollowTheNamingConvention() {
        for rule in BuiltinRules.all {
            let parts = rule.id.split(separator: ".")
            #expect(parts.count >= 2, "\(rule.id): tool.subject 形式ではない")
            #expect(
                rule.id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "." || $0.isUppercase },
                "\(rule.id): 想定外の文字を含む")
        }
    }

    private func duplicates(in ids: [String]) -> [String] {
        var seen = Set<String>()
        var dupes = Set<String>()
        for id in ids where !seen.insert(id).inserted {
            dupes.insert(id)
        }
        return dupes.sorted()
    }
}
