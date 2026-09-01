---
name: worktree-branch-cleanup
description: マージ完了後に不要になった作業環境（git worktree・ローカルブランチ・リモート追跡の残骸）を安全に削除するスキル。「後片付け」「作業環境を削除して」「worktree を消して」「マージ済みブランチを掃除」「セッション終了前の整理」「不要になったブランチを削除」などの指示で使用する。squash マージで git branch -d が使えないリポジトリでも、既定ブランチとのツリー一致で削除可否を判定する。
---

# 作業完了後の環境整理

PR がマージされ、作業に使った worktree・ブランチが不要になったときの後片付けを行う。

## いつ使うか

- PR がマージされ、作業していたブランチ・worktree が不要になったとき
- セッションを終える前に、溜まった `: gone` ブランチや worktree の残骸を掃除したいとき

## やらないこと

- 未マージのブランチの削除
- 他のセッション・他の作業が使用中の worktree の削除
- リモートブランチの削除（GitHub の PR マージ時の自動削除に任せる。残っていた場合は報告だけする）
- 既定ブランチ名の決め打ち（`main` とは限らないため必ず取得する）

## 測定済みの事実

推測ではなく実測で確認した挙動。手順はこれに依存している。

- **squash マージのリポジトリでは `git branch -d` はマージ済みでも失敗する**
  （`error: the branch 'X' is not fully merged`）。ブランチのコミットが既定ブランチの祖先にならないため
- `git branch -d` / `-D` は、**他の worktree でチェックアウト中のブランチを拒否する**
  （`error: cannot delete branch 'X' used by worktree at ...`）。これは安全弁としてそのまま使える
- **Bash ツールのシェルの cwd が worktree の中にあっても `git worktree remove` は成功する**
  （Windows / Git Bash で実測）。シェルの cwd はロック要因にならない

## 手順

### 1. 現在地と既定ブランチを確認する

```
git rev-parse --abbrev-ref HEAD
git symbolic-ref --quiet --short refs/remotes/origin/HEAD
git worktree list
```

`symbolic-ref` の出力は `origin/main` のような**リモート追跡名**。
比較には**この追跡名をそのまま使う**（ローカルの既定ブランチが古くても正しく判定できる）。
`git checkout` に使うローカル名は先頭の `origin/` を除いた部分。

`worktree list` の 1 行目がメインの作業ツリー。現在の作業ディレクトリがどの行の配下かで
「worktree の中にいるか外にいるか」を判定する。

### 2. マージされたことを確認する

```
gh pr view <PR番号> --json state,mergedAt,headRefName
```

PR 番号が分からないときは `gh pr list --state merged --head <ブランチ名>`。
MERGED でないブランチは以降の削除対象にしない。

### 3. 削除してよいブランチかを判定する

**`git branch -d` の成否を判定に使わない。** squash マージでは必ず失敗するため、
判定にならない。ツリーの一致で判定する。

```
git fetch origin --prune
git diff --stat origin/<既定ブランチ> <対象ブランチ>
```

- 出力が空 → 内容は既定ブランチに入っている。削除してよい
- 出力がある → 未マージの変更が残っている。削除しない（理由を添えて報告する）

削除は `git branch -D <対象ブランチ>`。判定を通したうえでの `-D` なので未マージ分は消えない。

### 4. 居場所に応じて削除する

| セッションの作業ディレクトリ | 削除方法 |
|------------------------------|----------|
| worktree の外 | `git checkout <既定ブランチのローカル名>` → `git pull --ff-only` → 手順3の判定 → `git branch -D` |
| worktree の中・`EnterWorktree` で作った | `ExitWorktree(action: "remove")`。作業ディレクトリを戻したうえで worktree とブランチを削除する |
| worktree の中・`git worktree add` で手動作成 | まず通常どおり `git worktree remove` を試す。**失敗した場合に限り** `assets/cleanup-after-exit.ps1` を使う |

対象の worktree は `git worktree remove <パス>` で削除する。未コミットの変更があると git が拒否するので、
その場合は内容をユーザーに提示して指示を仰ぐ（`--force` を自己判断で付けない）。

### 5. 残骸を掃除する

```
git worktree prune -v
git fetch origin --prune
git branch -vv
```

`git branch -vv` で `: gone` と表示されるブランチはリモートが消えている。
各ブランチについて手順3の判定を行い、通ったものだけを `git branch -D` する。
判定を通らなかったものは削除せず、一覧にして報告する。

### 6. 報告する

実行したコマンドと結果を表で報告する。削除しなかったものは理由を必ず書く。

## セッションの作業ディレクトリが worktree の中にある場合

Claude Code 本体の作業ディレクトリが削除対象の worktree の中にあると、ディレクトリを削除できない
ことがある（**この失敗は未確認。手順4のとおり、まず通常の削除を試すこと**）。

スクリプト自体の動作は使い捨てリポジトリで実測済み。
マージ済み相当のブランチと worktree は削除され、未マージのブランチは残り、
`-WaitPid` を渡した場合は対象プロセスの終了を待ってから削除が行われた。

`EnterWorktree` で作った worktree なら `ExitWorktree(action: "remove")` が作業ディレクトリを
元に戻したうえで worktree とブランチを削除するため、スクリプトは不要。
`ExitWorktree` は手動で `git worktree add` した worktree には触らないので、そちらだけがスクリプトの対象。

### assets/cleanup-after-exit.ps1

Claude Code のプロセス終了を待ってから削除する、切り離し実行用の PowerShell スクリプト。
待ち時間の秒数は持たず、プロセスの終了そのものを待つ。

```
powershell -NoProfile -ExecutionPolicy Bypass -File <スキルの assets>/cleanup-after-exit.ps1 `
  -RepoPath "<メイン作業ツリーのパス>" `
  -WorktreePath "<削除する worktree のパス>" `
  -BranchName "<削除するブランチ名>" `
  -WaitPid <待機するプロセスID>
```

- `-WaitPid` には Claude Code 本体のプロセス ID を渡す。省略すると待たずに実行する
- スクリプト側でも手順3と同じツリー一致判定を行い、通らなければブランチを残す
- 実行結果は `-LogPath`（既定: ユーザーの TEMP 配下）に追記される。次のセッションで結果を確認できる

起動は親から切り離して行う。

```
Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<スクリプトパス>','-RepoPath','<...>','-WorktreePath','<...>','-BranchName','<...>','-WaitPid','<...>'
```

スクリプトを起動したら、**ユーザーにログの場所と、削除がセッション終了後に行われることを伝える**。
その場で削除が完了したかのように報告しない。
