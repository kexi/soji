# soji

開発者マシンのディスクを、理由を示して掃除する macOS アプリと CLI。

Homebrew / npm / pnpm / Cargo / Gradle / Xcode などが溜め込んだキャッシュを見つけ、
**何を消すと何が起きるか**を示したうえで削除します。対象は開発ツールが自分で
作り直せるものだけで、ソースコードや設定には一切触れません。

## インストール

```sh
# アプリ
# https://github.com/kexi/soji/releases/latest から soji.dmg を取得

# CLI
brew install kexi/tap/soji
```

macOS 26 以降 / Apple Silicon が必要です。

## アプリ

起動するとスキャンが走り、何がどれだけあるかを一覧にします。上部の
サンバーストで内訳を見て、クリックでドリルダウンできます。

各項目には「消えると何が起きるか」が付きます。既定でチェックが入るのは
完全に再生成できるものだけで、それ以外は自分で選ぶ必要があります。

削除は確認シートを挟みます。取り返しがつかない可能性がある項目が
含まれていれば、個別に列挙されます。完了後は概算と実際の解放量を
並べて表示します。

## CLI

GUI でできることは CLI でもできます。AI エージェントから使えるよう、
構造化された JSON を返します。

```sh
soji scan                 # 候補を一覧する（何も消さない）
soji scan --json          # 構造化 JSON で得る
soji clean                # 何が消えるかを確認する（既定はドライラン）
soji clean --yes          # 実際に削除する
soji rules --json         # 何を消すと何が起きるかを読む
```

**`clean` は `--yes` を付けない限り 1 バイトも削除しません。**

絞り込みは `scan` と `clean` で共通です。

```sh
soji scan --risk safe --risk slowToRebuild   # 危険度で絞る
soji scan --tool Homebrew --tool npm         # ツールで絞る
soji clean --rule npm.cacache --yes          # ルールを指定して消す
soji scan --min-bytes 1000000000             # 1GB 以上だけ見る
soji scan --include-advisory                 # ツールに委ねる項目も表示
soji scan --home /tmp/sandbox                # ホームを差し替えて試す
```

終了コードは `0`（成功）と `3`（一部削除に失敗）です。

`--home` は隔離した場所で挙動を確かめるためのものです。`HOME` 環境変数は
効きません（`FileManager` が `getpwuid` を読むため）。エージェントに
試させるときはこのオプションを使ってください。

## 設計上の判断

### ゴミ箱は使わない

ゴミ箱への移動は同一ボリューム上の rename にすぎず、**空き容量が 1 バイトも
増えません**。実測では 20,000 ファイルの rename が 0.024 秒、実削除が 1.4 秒
でした。この 60 倍の差が「何も解放していない」ことの証拠です。

soji は完全に削除します。だからこそ対象を再生成できるものに絞っています。

### サイズは概算

`.totalFileAllocatedSizeKey` を使うので `du` と一致しますが、APFS のクローンは
`du` を含めて二重に計上されます。実測では 300MB のクローンの実コストが 1,216KB
でした。削除後には実際の解放量（空き容量の前後差）も示します。

### ツールに任せるもの

Docker の仮想ディスクや `~/go/pkg/mod` は直接消すと壊れる、あるいは読み取り
専用で消せません。これらは削除せず、`docker system prune` のような正しい
コマンドを提示します。CLI では `--include-advisory` で一覧に出ます。

### 危険度

| 危険度 | 意味 | 既定 |
|---|---|---|
| `safe` | 完全に再生成可能。次のビルドで自動的に戻る | 選択される |
| `slowToRebuild` | 再生成できるが、取得にネットワークと時間がかかる | 選択されない |
| `needsConfirmation` | 環境を壊しうる、または取り返しがつかない | 選択されない |

## 開発

ツールは nix flake の devShell から供給されます。

```sh
direnv allow          # または nix develop
just                  # タスク一覧
just check            # CI 相当の一括ゲート
just test             # SojiKit のユニットテスト
just run              # GUI をビルドして起動
just build-cli        # CLI をビルド
just install-cli      # CLI を ~/.local/bin に入れる
just lp-serve         # LP をローカルで確認
```

### 構成

```
Packages/SojiKit/     ロジックと CLI（swift test の主戦場）
  Sources/SojiKit/    走査・計測・削除・ルール
  Sources/soji/       CLI
App/                  GUI（View と ViewModel だけ）
docs/                 LP（GitHub Pages）
project.yml           XcodeGen の入力。.xcodeproj は生成物
```

ロジックはすべて `SojiKit` にあり、GUI と CLI は同じコードの上に立ちます。
`.xcodeproj` は `project.yml` から生成するのでコミットしません。

### 書き分け

- **コード**には How、**テストコード**には What
- **コミットログ**には Why、**コードコメント**には Why not

## License

MIT
