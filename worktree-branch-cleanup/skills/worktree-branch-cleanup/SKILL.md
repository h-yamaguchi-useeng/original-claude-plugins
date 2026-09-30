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
- 削除対象を使っているプロセスの強制終了（閉じるのはユーザーに依頼する）

## 測定済みの事実

推測ではなく実測で確認した挙動。手順はこれに依存している。

- **squash マージのリポジトリでは `git branch -d` はマージ済みでも失敗する**
  （`error: the branch 'X' is not fully merged`）。ブランチのコミットが既定ブランチの祖先にならないため
- `git branch -d` / `-D` は、**他の worktree でチェックアウト中のブランチを拒否する**
  （`error: cannot delete branch 'X' used by worktree at ...`）。これは安全弁としてそのまま使える
- **削除対象の worktree 配下の exe が起動中だと `git worktree remove` は失敗する**
  （`error: failed to delete '<パス>': Invalid argument`、exit 255）
- **`git worktree remove` が失敗しても、管理情報の登録解除だけ済んでいることがある。**
  失敗したら必ず `git worktree list` を確認する。行が消えていれば `git worktree remove` を再実行する道は無く、
  以降はディレクトリの直接削除しか手が無い。同時に「worktree でチェックアウト中」という
  ブランチ削除の安全弁も外れるため、ブランチ削除は手順4の判定を必ず自分で通してから行う
- **Bash ツールのシェルの cwd が worktree の中にあっても、`git worktree remove` と配下の中身の削除は通る**
  （Windows / Git Bash で実測）。ただし**ディレクトリ本体の削除は通らない**
  （配下が空になった状態でも `rm -rf` が `Device or resource busy` で失敗し、空ディレクトリが残る）。
  ロック保持者がセッションの作業ディレクトリであることは特定していない（他に候補が無いことからの推定）
- **PowerShell から `git` の出力を読むときは `[Console]::OutputEncoding` を UTF-8 に固定する。**
  既定のコードページのままだと日本語を含むパス（`C:\Users\山口敬史\`、`Git - コクヨ` など）が化け、
  `git worktree list` との突き合わせが必ず外れる（実測。`cleanup-after-exit.ps1` では対処済み）
- **Claude Code のプロセスはチャットのウィンドウを閉じても終了しない。**
  終了タイミングは Claude 側の管理下にあり、操作からは読めない。
  そのため「プロセス終了を待つ常駐」だけでは、1 日の最後に後片付けすると
  PC の終了が先に来てゴミが残る（実測）
- **ロック中のディレクトリは `Move-Item` による退避もできない。** `Remove-Item` と同じく使用中になる（実測）
- **`rd`（`cmd.exe`）は空でないディレクトリには何もしない。** 空でなければ
  `ディレクトリが空ではありません`（exit 145）でディレクトリを残し、空なら削除する（実測）。
  この性質があるため RunOnce の保険として安全に置ける
- **`ExitWorktree` は「このセッションの `EnterWorktree` で作った」worktree にしか効かない。**
  前のセッションで作ったものはパスが `.claude/worktrees/` 配下でも no-op で返る
  （`No-op: there is no active EnterWorktree session to exit.`）

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

### 3. 削除対象の worktree を使っているプロセスが無いか確認する

**worktree を消す前に必ず行う。** 配下の exe が動いていると `git worktree remove` は
`Invalid argument` で失敗し、しかも登録解除だけ済んだ中途半端な状態になる。

```
powershell -NoProfile -Command "Get-Process | Where-Object { $_.Path -like '<worktree のパス>\*' } | Select-Object Id, ProcessName, Path"
```

実機確認のために worktree 内の exe を直接起動する運用のリポジトリでは、ほぼ必ず引っかかる。
動いていたら**ユーザーに閉じてもらう**。自己判断で kill しない。

### 4. 削除してよいブランチかを判定する

**`git branch -d` の成否を判定に使わない。** squash マージでは必ず失敗するため、
判定にならない。ツリーの一致で判定する。

```
git fetch origin --prune
git diff --stat origin/<既定ブランチ> <対象ブランチ>
```

- 出力が空 → 内容は既定ブランチに入っている。削除してよい
- 出力がある → 未マージの変更が残っている。削除しない（理由を添えて報告する）

削除は `git branch -D <対象ブランチ>`。判定を通したうえでの `-D` なので未マージ分は消えない。

### 5. 居場所に応じて削除する

| セッションの作業ディレクトリ | 削除方法 |
|------------------------------|----------|
| worktree の外 | `git checkout <既定ブランチのローカル名>` → `git pull --ff-only` → 手順4の判定 → `git branch -D` |
| worktree の中・**このセッションの** `EnterWorktree` で作った | `ExitWorktree(action: "remove")`。作業ディレクトリを戻したうえで worktree とブランチを削除する |
| worktree の中・手動作成、または**前のセッション**で作った | `git worktree remove` の経路（下記）。`ExitWorktree` は no-op で返るので使わない |

worktree の削除は次の順で行う。

1. 削除前に `git -C <worktree> status --porcelain` を控える。空でなければ内容をユーザーに提示して指示を仰ぐ
   （`--force` を自己判断で付けない）。**この結果は後で必要になるので必ず先に取る**
1. `git worktree remove <パス>` を実行する
1. 失敗したら `git worktree list` を確認する
   - 登録が残っている → 手順3のプロセスを閉じてもらってから再実行する
   - 登録が消えている → `git worktree remove` はもう使えない。ディレクトリの直接削除に切り替える
1. ディレクトリの直接削除は、手順の 1 で「変更なし」を確認できている場合に限り行う。
   セッションの作業ディレクトリがその worktree 内にあると**ディレクトリ本体だけ消せない**ため、
   `assets/cleanup-after-exit.ps1` に任せる

### 6. 残骸を掃除する

```
git worktree prune -v
git fetch origin --prune
git branch -vv
```

`git branch -vv` で `: gone` と表示されるブランチはリモートが消えている。
各ブランチについて手順4の判定を行い、通ったものだけを `git branch -D` する。
判定を通らなかったものは削除せず、一覧にして報告する。

### 7. 報告する

実行したコマンドと結果を表で報告する。削除しなかったもの・消し残したものは理由を必ず書く。
スクリプトに委ねた分は「セッション終了後に削除される」と書き、完了したように書かない。

## セッションの作業ディレクトリが worktree の中にある場合

Claude Code 本体の作業ディレクトリが削除対象の worktree の中にあると、
**配下の中身は削除できてもディレクトリ本体だけ消せない**（実測。`Device or resource busy`）。
この後始末が `assets/cleanup-after-exit.ps1` の役割。

このセッションの `EnterWorktree` で作った worktree なら `ExitWorktree(action: "remove")` が
作業ディレクトリを元に戻したうえで worktree とブランチを削除するため、スクリプトは不要。
手動作成・前のセッション由来のものだけがスクリプトの対象。

### assets/cleanup-after-exit.ps1

Claude Code のプロセス終了を待ってから削除する、切り離し実行用の PowerShell スクリプト。
待ち時間の秒数は持たず、プロセスの終了そのものを待つ。

```
powershell -NoProfile -ExecutionPolicy Bypass -File <スキルの assets>/cleanup-after-exit.ps1 `
  -RepoPath "<メイン作業ツリーのパス>" `
  -WorktreePath "<削除する worktree のパス>" `
  -BranchName "<削除するブランチ名>" `
  -WaitPid <待機するプロセスID> `
  -AllowDirectoryDelete `
  -RegisterRunOnce
```

- `-WaitPid` には Claude Code 本体のプロセス ID を渡す。省略すると待たずに実行する
- `git worktree remove` が失敗した場合・登録が既に無い場合は、ディレクトリの直接削除に切り替える
  - **空のディレクトリは常に削除する**（残していても意味が無いため）
  - 中身が残っている場合は `-AllowDirectoryDelete` を付けたときだけ削除する。
    このスイッチは、**手順5の 1 で「未コミットの変更なし」を確認できたときだけ**付ける。
    付いていなければ削除せずログに残す
- ブランチ削除は手順4と同じツリー一致判定を行い、通らなければ残す
- `-RegisterRunOnce` を付けると、**待機に入る前に** `HKCU\...\RunOnce` へ
  `cmd.exe /c rd "<パス>"` を登録する。待機中に PC が終了しても、次回ログオン時に 1 回だけ削除が走る。
  管理者権限は不要で、RunOnce のエントリは実行時に自動で消える
  - `-AllowDirectoryDelete` も付いている場合だけ `rd /s /q` になる。付いていなければ素の `rd` なので、
    中身が残っているディレクトリには何もしない
  - 常駐側でディレクトリを削除できた場合は、その場で RunOnce の登録を解除する
  - **保険が片付けるのはディレクトリだけ。** ブランチ削除と `prune` は常駐側の担当なので、
    PC 終了が先に来た場合はブランチが残る。次回セッションの手順6 で拾う
- 実行結果は `-LogPath`（既定: ユーザーの TEMP 配下）に追記される。次のセッションで結果を確認できる

起動は親から切り離して行う。

```
Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<スクリプトパス>','-RepoPath','<...>','-WorktreePath','<...>','-BranchName','<...>','-WaitPid','<...>','-AllowDirectoryDelete','-RegisterRunOnce'
```

スクリプトを起動したら、**ユーザーにログの場所と、削除がセッション終了後に行われることを伝える**。
その場で削除が完了したかのように報告しない。
