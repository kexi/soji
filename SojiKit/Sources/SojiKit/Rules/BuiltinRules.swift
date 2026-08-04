import Foundation

/// 組み込みルール集。
///
/// 対象は「開発ツールが自分で作り直せるもの」に限る。ソースコードや設定、
/// ユーザーが手で置いたファイルは一切対象にしない。
///
/// Why not 網羅を目指すか: ルールを 1 件足すことは「消してよい」という判断を
/// 1 件足すことであり、間違えると直接データ損失になる。実在確認と再生成手段の
/// 確認が取れたものだけを載せる。
public enum BuiltinRules {

    public static let all: [CleanRule] = safe + slowToRebuild + needsConfirmation

    // MARK: - safe

    /// 完全に再生成可能。次のビルドやインストールで自動的に戻るもの。
    static let safe: [CleanRule] = [
        CleanRule(
            id: "homebrew.downloads",
            toolName: "Homebrew",
            displayName: "ダウンロード済みボトル",
            locations: [.init("Library/Caches/Homebrew/downloads")],
            risk: .safe,
            rationale: "インストール済みパッケージ本体ではなく、取得したアーカイブの控え。",
            consequence: "次回の brew install / upgrade で再ダウンロードされる。"
        ),
        CleanRule(
            id: "xcode.derivedData",
            toolName: "Xcode",
            displayName: "DerivedData",
            // プロジェクト単位で残すか決めたい場面が多いので展開する。
            locations: [
                .init(
                    "Library/Developer/Xcode/DerivedData",
                    expandsChildren: true,
                    childThreshold: 100 * 1024 * 1024)
            ],
            risk: .safe,
            rationale: "中間ビルド生成物とインデックス。ソースからいつでも再生成できる。",
            consequence: "次回ビルドがフルビルドになり時間がかかる。インデックスも作り直しになる。"
        ),
        CleanRule(
            id: "npm.cacache",
            toolName: "npm",
            displayName: "パッケージキャッシュ",
            locations: [.init(".npm/_cacache")],
            risk: .safe,
            rationale: "レジストリから取得した tarball の控え。",
            consequence: "次回 npm install でネットワークから再取得される。"
        ),
        CleanRule(
            id: "yarn.cache",
            toolName: "Yarn",
            displayName: "パッケージキャッシュ",
            locations: [
                .init("Library/Caches/Yarn"),
                .init(".cache/yarn"),
            ],
            risk: .safe,
            rationale: "レジストリから取得したパッケージの控え。",
            consequence: "次回 yarn install で再取得される。"
        ),
        CleanRule(
            id: "bun.installCache",
            toolName: "Bun",
            displayName: "install キャッシュ",
            locations: [.init(".bun/install/cache")],
            risk: .safe,
            rationale: "取得済みパッケージの控え。",
            consequence: "次回 bun install で再取得される。"
        ),
        CleanRule(
            id: "pip.cache",
            toolName: "pip",
            displayName: "wheel キャッシュ",
            locations: [.init("Library/Caches/pip")],
            risk: .safe,
            rationale: "ダウンロード済み wheel とビルド済みの控え。",
            consequence: "次回 pip install で再取得・再ビルドされる。"
        ),
        CleanRule(
            id: "uv.cache",
            toolName: "uv",
            displayName: "パッケージキャッシュ",
            locations: [.init("Library/Caches/uv")],
            risk: .safe,
            rationale: "取得済みパッケージの控え。",
            consequence: "次回 uv 実行時に再取得される。"
        ),
        CleanRule(
            id: "go.buildCache",
            toolName: "Go",
            displayName: "ビルドキャッシュ",
            locations: [.init("Library/Caches/go-build")],
            risk: .safe,
            rationale: "コンパイル結果のキャッシュ。ソースから再生成できる。",
            consequence: "次回ビルドが遅くなるだけ。"
        ),
        CleanRule(
            id: "cargo.registry",
            toolName: "Cargo",
            displayName: "レジストリキャッシュと展開済みソース",
            locations: [
                .init(".cargo/registry/cache"),
                .init(".cargo/registry/src"),
            ],
            risk: .safe,
            rationale: "crates.io から取得した .crate と、その展開結果。",
            consequence: "次回ビルドで再ダウンロード・再展開される。",
            environmentOverride: .init("CARGO_HOME", replaces: ".cargo")
        ),
        CleanRule(
            id: "gradle.caches",
            toolName: "Gradle",
            displayName: "ビルドキャッシュ",
            locations: [.init(".gradle/caches")],
            risk: .safe,
            rationale: "依存 JAR とビルド出力のキャッシュ。",
            consequence: "次回ビルドで再取得され、時間がかかる。",
            environmentOverride: .init("GRADLE_USER_HOME", replaces: ".gradle")
        ),
        CleanRule(
            id: "cocoapods.cache",
            toolName: "CocoaPods",
            displayName: "Pod キャッシュと spec リポジトリ",
            locations: [
                .init("Library/Caches/CocoaPods"),
                .init(".cocoapods/repos"),
            ],
            risk: .safe,
            rationale: "取得済み Pod と spec の控え。Podfile.lock があれば同じ内容を再取得できる。",
            consequence: "次回 pod install で再取得される。"
        ),
        CleanRule(
            id: "swiftpm.cache",
            toolName: "SwiftPM",
            displayName: "パッケージキャッシュ",
            locations: [
                .init("Library/Caches/org.swift.swiftpm"),
                .init(".swiftpm/cache"),
            ],
            risk: .safe,
            rationale: "取得済みパッケージの控え。Package.resolved があれば同じ版を再取得できる。",
            consequence: "次回解決時に再取得される。"
        ),
        CleanRule(
            id: "nodegyp.cache",
            toolName: "node-gyp",
            displayName: "Node ヘッダキャッシュ",
            locations: [.init("Library/Caches/node-gyp")],
            risk: .safe,
            rationale: "ネイティブモジュールのビルドに使う Node ヘッダの控え。",
            consequence: "次回ネイティブビルド時に再ダウンロードされる。"
        ),
        CleanRule(
            id: "playwright.browsers",
            toolName: "Playwright",
            displayName: "ブラウザバイナリ",
            locations: [.init("Library/Caches/ms-playwright")],
            risk: .safe,
            rationale: "テスト用にダウンロードされたブラウザ。playwright install で再取得できる。",
            consequence: "次回テスト実行前に再ダウンロードが必要。数百 MB あり時間がかかる。"
        ),
    ]

    // MARK: - slowToRebuild

    /// 再生成はできるが、取得にネットワークと時間がかかるもの。
    static let slowToRebuild: [CleanRule] = [
        CleanRule(
            id: "xcode.iosDeviceSupport",
            toolName: "Xcode",
            displayName: "iOS DeviceSupport",
            locations: [.init("Library/Developer/Xcode/iOS DeviceSupport", expandsChildren: true)],
            risk: .slowToRebuild,
            rationale: "実機デバッグ用のシンボルファイル。実機を再接続すれば再生成される。",
            consequence: "古い iOS バージョンの実機が手元に無いと再生成できず、その版のデバッグができなくなる。"
        ),
        CleanRule(
            id: "xcode.watchosDeviceSupport",
            toolName: "Xcode",
            displayName: "watchOS DeviceSupport",
            locations: [.init("Library/Developer/Xcode/watchOS DeviceSupport", expandsChildren: true)],
            risk: .slowToRebuild,
            rationale: "実機デバッグ用のシンボルファイル。実機を再接続すれば再生成される。",
            consequence: "古い watchOS バージョンの実機が手元に無いと再生成できない。"
        ),
        CleanRule(
            id: "coresimulator.caches",
            toolName: "CoreSimulator",
            displayName: "シミュレータキャッシュ",
            locations: [.init("Library/Developer/CoreSimulator/Caches")],
            risk: .slowToRebuild,
            rationale: "シミュレータのランタイムキャッシュ。シミュレータ再起動で作り直される。",
            consequence: "次回シミュレータ起動が遅くなる。"
        ),
        CleanRule(
            id: "go.modDownloadCache",
            toolName: "Go",
            displayName: "モジュールダウンロードキャッシュ",
            locations: [.init("go/pkg/mod/cache/download")],
            risk: .slowToRebuild,
            rationale: "取得済みモジュールの zip とメタデータ。go.sum があれば同じ内容を再取得できる。",
            consequence: "次回ビルドでネットワークから再取得される。依存が多いと数分かかる。",
            environmentOverride: .init("GOPATH", replaces: "go")
        ),
        CleanRule(
            id: "maven.repository",
            toolName: "Maven",
            displayName: "ローカルリポジトリ",
            locations: [.init(".m2/repository")],
            risk: .slowToRebuild,
            rationale: "取得済み JAR の控え。pom.xml から再取得できる。",
            consequence: "次回ビルドで全依存を再ダウンロードする。非常に遅い。"
        ),
        CleanRule(
            id: "nuget.packages",
            toolName: "NuGet",
            displayName: "パッケージキャッシュ",
            locations: [.init(".nuget/packages")],
            risk: .slowToRebuild,
            rationale: "取得済みパッケージの控え。",
            consequence: "次回 restore で再取得される。"
        ),
        CleanRule(
            id: "gradle.wrapperDists",
            toolName: "Gradle",
            displayName: "Gradle 本体 (wrapper)",
            locations: [.init(".gradle/wrapper/dists")],
            risk: .slowToRebuild,
            rationale: "wrapper が取得した Gradle 本体。gradlew 実行時に再取得される。",
            consequence: "次回 gradlew 実行時に Gradle 本体を再ダウンロードする。",
            environmentOverride: .init("GRADLE_USER_HOME", replaces: ".gradle")
        ),
    ]

    // MARK: - needsConfirmation

    /// 既定では選択しない。消すと環境が壊れる、または取り返しがつかないもの。
    static let needsConfirmation: [CleanRule] = [
        CleanRule(
            id: "xcode.archives",
            toolName: "Xcode",
            displayName: "Archives",
            locations: [
                .init(
                    "Library/Developer/Xcode/Archives",
                    expandsChildren: true,
                    childThreshold: 100 * 1024 * 1024)
            ],
            risk: .needsConfirmation,
            rationale: "提出済みビルドの成果物と dSYM を含む。再生成には当時のソースでの再ビルドが要る。",
            consequence: "過去バージョンのクラッシュログを記号化できなくなる。App Store 提出済みビルドの dSYM は取り戻せない。"
        ),
        CleanRule(
            id: "coresimulator.devices",
            toolName: "CoreSimulator",
            displayName: "シミュレータ本体",
            locations: [
                .init(
                    "Library/Developer/CoreSimulator/Devices",
                    expandsChildren: true,
                    // 実測: 88 件中の大半が 18MB 以下の未起動デバイスだった。
                    childThreshold: 100 * 1024 * 1024)
            ],
            risk: .needsConfirmation,
            rationale: "シミュレータのディスクイメージ。デバイス定義は再作成できる。",
            consequence: "シミュレータにインストール済みのアプリと、その中のデータが全部消える。"
        ),
        CleanRule(
            id: "cargo.gitCheckouts",
            toolName: "Cargo",
            displayName: "git 依存の checkout",
            locations: [
                .init(".cargo/git/checkouts"),
                .init(".cargo/git/db"),
            ],
            risk: .needsConfirmation,
            rationale: "git 依存のクローン。ネットワークがあれば再取得できる。",
            consequence: "オフラインではビルドできなくなる。参照先ブランチが消えていると再取得も失敗する。",
            environmentOverride: .init("CARGO_HOME", replaces: ".cargo")
        ),
        CleanRule(
            id: "go.modRoot",
            toolName: "Go",
            displayName: "モジュールキャッシュ全体",
            locations: [.init("go/pkg/mod")],
            risk: .needsConfirmation,
            // 実測: ~/go/pkg/mod 配下は dr-xr-xr-x / -r--r--r-- で作られる。
            rationale: "展開済みモジュール。読み取り専用権限で作られるため通常の削除では消せない。",
            consequence: "削除には go clean -modcache が必要。手動削除は権限エラーで途中失敗する。",
            environmentOverride: .init("GOPATH", replaces: "go"),
            isAdvisory: true,
            advisoryCommand: "go clean -modcache"
        ),
        CleanRule(
            id: "pnpm.store",
            toolName: "pnpm",
            displayName: "コンテンツアドレスストア",
            locations: [
                .init("Library/pnpm/store"),
                .init(".local/share/pnpm/store"),
            ],
            risk: .needsConfirmation,
            // pnpm は node_modules の実体をこのストアと共有する (ハードリンク
            // または APFS クローン)。ストアを消すと既存プロジェクトが壊れる。
            rationale: "全プロジェクトの node_modules が実体を共有するストア。",
            consequence: "既存プロジェクトの node_modules が壊れ、各プロジェクトで pnpm install のやり直しが要る。",
            environmentOverride: .init("PNPM_HOME", replaces: "Library/pnpm")
        ),
        CleanRule(
            id: "docker.data",
            toolName: "Docker",
            displayName: "イメージとコンテナ",
            locations: [.init("Library/Containers/com.docker.docker/Data")],
            risk: .needsConfirmation,
            // Why advisory: このディレクトリは Docker の仮想ディスク本体で、
            // ファイルを直接消すと Docker Desktop 自体が起動しなくなる。
            // 容量の可視化だけ行い、削除は docker 自身にやらせる。
            rationale: "Docker の仮想ディスク本体。イメージ・コンテナ・ボリュームが含まれる。",
            consequence: "直接削除すると Docker Desktop が壊れる。docker 自身のコマンドで整理すること。",
            isAdvisory: true,
            advisoryCommand: "docker system prune -a --volumes"
        ),
    ]
}
