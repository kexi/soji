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
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages =
            with pkgs;
            [
              git
              just
              lefthook
              gitleaks
              pinact
            ]
            # Why optionals: xcodegen / swiftlint は darwin 専用パッケージで、
            # Linux では解決に失敗して flake の評価ごと壊れる。CI を macos に
            # 寄せていても `nix flake check` が Linux で回る余地を潰さない。
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
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
            if [ -d .git ]; then
              lefthook install >/dev/null 2>&1 || true
            fi
          '';
        };

        formatter = pkgs.nixfmt;
      }
    );
}
