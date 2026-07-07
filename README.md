# original-claude-plugins

USE Engineering 社内向けの自作 Claude Code プラグイン群を管理するリポジトリ（マーケットプレース）。

- **方針**: スキルごとに 1 プラグインとして管理する。
- **マーケットプレース名**: `useeng-original`（`.claude-plugin/marketplace.json`）

## 収録プラグイン

| プラグイン | 説明 |
|-----------|------|
| `test-spec-html` | 機能仕様書(Markdown)から、テスト実施結果をブラウザに保存できる単一 HTML のテスト仕様書を生成するスキル |

## リポジトリ構成

```
original-claude-plugins/
├─ .claude-plugin/
│   └─ marketplace.json          … マーケットプレース定義（収録プラグイン一覧）
└─ <plugin-name>/                … プラグイン（スキルごとに1つ）
    ├─ .claude-plugin/plugin.json … プラグイン定義
    └─ skills/<skill-name>/SKILL.md … スキル本体（必要なら assets/ を同梱）
```

## 適用手順（初回）

1. 変更を commit → push する。
2. マーケットプレースを追加する（未追加の場合のみ）:
   ```
   claude plugin marketplace add h-yamaguchi-useeng/original-claude-plugins
   ```
3. プラグインをインストールする:
   ```
   claude plugin install <plugin-name>@useeng-original
   ```

## 更新手順（2回目以降）

1. スキル/プラグインを修正し commit → push する。
2. マーケットプレースとプラグインを更新する:
   ```
   claude plugin marketplace update useeng-original
   claude plugin update <plugin-name>
   ```
   （反映には Claude Code の再起動が必要な場合があります）

## 新しいスキルを追加するとき

1. `<新plugin-name>/.claude-plugin/plugin.json` と `<新plugin-name>/skills/<skill>/SKILL.md` を作成する。
2. `.claude-plugin/marketplace.json` の `plugins` に追記する。
3. `claude plugin validate .` で妥当性を確認する。
4. commit → push → `claude plugin install <新plugin-name>@useeng-original`。

> 自作スキルの作成フロー全体は、各端末のグローバル設定
> `~/.claude/rules/custom-skill-workflow.md` にルールとして整備されている。
