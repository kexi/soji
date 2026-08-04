{
  # soji の dev tool を決定的に供給する devShell。
  #
  # Why nix: xcodegen / swiftlint を brew で入れるとマシン間でバージョンがずれ、
  # `swiftlint --strict` の警告差分が CI とローカルで食い違う。flake.lock で
  # exact version を固定してこれを消す。
  description = "soji: macOS developer cache cleaner (nix develop + direnv)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    # Why aarch64-darwin だけか: soji は macOS 26 の Liquid Glass と Xcode 26 を
    # 前提とする macOS 専用アプリで、他システムでビルドできる余地が無い。
    # eachDefaultSystem のままだと x86_64-darwin まで展開され、nixpkgs が
    # そのシステムのサポートを打ち切っている今 `nix flake check --all-systems`
    # が評価に失敗する。動かせない対象を宣言しない。
    flake-utils.lib.eachSystem [ "aarch64-darwin" ] (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        # Why mkShellNoCC: 既定の mkShell は stdenv の clang wrapper を PATH と
        # LD / NIX_LDFLAGS に注入する。すると xcodebuild が nix の ld を使って
        # しまい、SojiKit のリンクが失敗する (Ld ... SojiKit.o)。soji は Swift
        # だけで書かれており C ツールチェーンを必要としないので、丸ごと外す。
        devShells.default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            git
            just
            lefthook
            gitleaks
            pinact
            xcodegen
            swiftlint
          ];

          # Why not swift-format from nixpkgs: nixpkgs の swift-format は 5.10.1 で、
          # このリポジトリの Swift 6.3 構文 (@concurrent 等) をパースできない。
          # 決定性のために入れたものが壊れるという逆転が起きるので載せない。
          # 代わりに Xcode 26 同梱の `xcrun swift-format` を justfile から呼ぶ。
          # swiftformat (nixpkgs 0.61) は 6.x 対応済みだが使用実績がゼロで、
          # 設定の学習コストを新規に払うことになるため採らなかった。

          # Wire up git hooks on every devShell entry. lefthook install is
          # idempotent, so re-running it on each entry keeps .git/hooks in sync
          # with lefthook.yml without a manual setup step after clone.
          shellHook = ''
            # Why 手当てが要るか: nixpkgs の darwin stdenv は DEVELOPER_DIR /
            # SDKROOT を同梱の apple-sdk (14.4) に固定する。すると Xcode 26 の
            # swift 6.3 が macOS 14.4 SDK と組み合わされ、その SDK が持つ
            # Swift 5.10 の module interface を読もうとして `swift test` が
            # 落ちる。soji は macOS 26 SDK (Liquid Glass) が必須。
            #
            # Why not unset だけで済ませないか: unset すると xcrun が SDK を
            # 見つけられなくなり (`unable to find sdk: macosx`)、xcodebuild が
            # 動かない。xcode-select の指すパスを明示的に入れ直す。
            #
            # Why env -u で問い合わせるか: xcode-select -p 自体が DEVELOPER_DIR を
            # 優先して読むため、そのまま呼ぶと nix が設定した値をそのまま返す
            # (自己参照)。環境変数を外した状態で真の設定値を取りに行く。
            unset SDKROOT
            if xcode_dir="$(env -u DEVELOPER_DIR /usr/bin/xcode-select -p 2>/dev/null)"; then
              export DEVELOPER_DIR="$xcode_dir"
            else
              unset DEVELOPER_DIR
              echo "warning: Xcode not selected; run: sudo xcode-select -s /Applications/Xcode.app" >&2
            fi

            # Why SDK バージョンを確かめるか: Xcode があっても macOS 26 SDK が
            # 無ければ Liquid Glass の API が解決できず、原因の分かりにくい
            # コンパイルエラーになる。入口で気づけるようにしておく。
            sdk_version="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo 0)"
            case "$sdk_version" in
              26.*) : ;;
              *)
                echo "warning: macOS SDK $sdk_version found; soji needs the macOS 26 SDK (Liquid Glass)." >&2
                ;;
            esac

            if [ -d .git ]; then
              lefthook install >/dev/null 2>&1 || true
            fi
          '';
        };

        formatter = pkgs.nixfmt;
      }
    );
}
