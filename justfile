# soji task runner (just)。
#
# 開発でよく打つ xcodegen / xcodebuild / swift test 一連を `just <task>` にまとめる。
# ビルド構成の単一情報源は引き続き project.yml (XcodeGen) と SojiKit/Package.swift。
# 本ファイルは「タイピングの省略形」であってビルドシステムの差し替えではない。
#
# ツール供給は flake.nix の devShell (nix develop / direnv)。just 自体も
# flake.nix packages から供給される (= mise 廃止後の唯一の入り口)。
#
# 使い方:
#   just            # 一覧 (= just --list)
#   just check      # CI 相当の一括ゲート (push 前にこれ)

# 既定ターゲット: 引数なしで叩いたら一覧を出す。
default:
    @just --list

# Why 残すか: flake の shellHook でも冪等に走るので通常は不要だが、nix を
# 使わない人向けの明示的な入口として残す。
#
# git hooks を張る
setup:
    lefthook install

# ───── ビルド / 実行 ─────────────────────────────────────────────────────────

# .xcodeproj は gitignore してあるので clone 直後は必ずこれを打つ。
#
# project.yml から .xcodeproj を再生成する
generate:
    xcodegen generate

# Why xcodebuild: app ターゲットは SwiftUI + Info.plist + 署名が絡むので
# swift build では再現できない。ロジック側のループは `just test` が担う。
#
# app をビルドする
build: generate
    xcodebuild -project Soji.xcodeproj -scheme Soji -configuration Debug build

# Why 分けるか: CI ランナーには Developer ID 証明書が無く、通常の build は
# 署名段階で必ず落ちる。ローカルの build と条件を混ぜないよう別レシピにする。
#
# 署名なしでビルドする (CI 用)
build-unsigned: generate
    xcodebuild -project Soji.xcodeproj -scheme Soji -configuration Debug build \
      CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Xcode.app は開かずビルド成果物を直接叩く。
#
# ビルドして起動する
run: build
    #!/usr/bin/env bash
    set -euo pipefail
    products="$(xcodebuild -project Soji.xcodeproj -scheme Soji -configuration Debug \
      -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR = /{print $3}')"
    open "$products/Soji.app"

# ───── テスト / 品質 ─────────────────────────────────────────────────────────

# Why swift test: Xcode を起動しないので数秒で回る。ロジックは全部 SojiKit に
# あるのでここが主戦場になる。
#
# SojiKit のユニットテスト
test:
    cd SojiKit && swift test

# SwiftLint。--strict で warning も失敗にする (警告の放置を防ぐ)。
lint:
    swiftlint lint --strict

# Why xcrun swift-format: nixpkgs の swift-format は 5.10 で Swift 6.3 構文を
# 解釈できず壊れるため、Xcode 26 同梱版を使う。詳細は flake.nix のコメント。
#
# 整形を適用する
fmt:
    xcrun swift-format format --in-place --recursive --parallel Soji SojiKit/Sources SojiKit/Tests

# 整形差分の検査のみ (CI 用)。差分があれば非ゼロ終了する。
fmt-check:
    xcrun swift-format lint --strict --recursive --parallel Soji SojiKit/Sources SojiKit/Tests

# 履歴全体を見る (pre-commit hook は staged のみ)。
#
# 秘密情報の混入検査
secrets:
    gitleaks git --redact

# GitHub Actions が SHA 固定されているかの検査。
pin-check:
    pinact run --check

# Actions の SHA 固定を実際に適用する。
pin:
    pinact run

# Why この順: 速くて落ちやすいものを先に置き、フィードバックを早める
# (lint/fmt は秒、test は十数秒、build は分)。
# Why build を含めるか: SojiKit のテストが緑でも app 側は Liquid Glass API を
# 多用するためコンパイルエラーが出やすい。「テストは緑なのに起動しない」を防ぐ。
#
# CI 相当のローカル一括ゲート (push 前にこれ)
check: lint fmt-check test secrets pin-check build

# CI 用のゲート。build を署名なし版に差し替えただけ。
check-ci: lint fmt-check test secrets pin-check build-unsigned

# ───── LP (docs/, GitHub Pages) ──────────────────────────────────────────────

# Why python3 -m http.server: LP はビルドステップの無い素の HTML/CSS なので、
# 静的配信さえできれば足りる。Firebase Hosting を使わないので emulator も不要。
#
# LP をローカルで確認する (http://localhost:8000)
lp-serve:
    python3 -m http.server 8000 --directory docs
