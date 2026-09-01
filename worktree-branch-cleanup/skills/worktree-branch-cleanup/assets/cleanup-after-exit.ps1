# Claude Code のプロセス終了を待ってから、worktree とブランチを削除する。
# 待ち時間の秒数は持たない。プロセスの終了そのものを待つ。
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepoPath,
    [string]$WorktreePath,
    [string]$BranchName,
    [int]$WaitPid = 0,
    [string]$LogPath,
    # git worktree remove が使えないときにディレクトリごと削除してよいか。
    # 未コミットの変更が無いことを呼び出し側で確認できたときだけ付ける。
    # 空のディレクトリはこのスイッチが無くても削除する。
    [switch]$AllowDirectoryDelete
)

$ErrorActionPreference = 'Continue'

# git の出力は UTF-8。既定のコードページのままだと日本語を含むパスが化けて
# worktree の登録判定が外れるため、子プロセス出力の解釈を UTF-8 に固定する。
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if (-not $LogPath) {
    $LogPath = Join-Path $env:TEMP 'worktree-branch-cleanup.log'
}

function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogPath -Value "$stamp $Message" -Encoding UTF8
}

function Invoke-Git {
    param([string[]]$GitArgs)
    $output = & git -C $RepoPath @GitArgs 2>&1
    $code = $LASTEXITCODE
    Write-Log ("git " + ($GitArgs -join ' ') + " -> exit=$code")
    foreach ($line in $output) { Write-Log "    $line" }
    return [pscustomobject]@{ ExitCode = $code; Output = ($output | Out-String).Trim() }
}

function ConvertTo-ComparablePath {
    param([string]$Path)
    if (-not $Path) { return '' }
    return $Path.Replace('\', '/').TrimEnd('/').ToLowerInvariant()
}

function Test-WorktreeRegistered {
    param([string]$Path)
    $listed = & git -C $RepoPath worktree list --porcelain 2>&1
    $target = ConvertTo-ComparablePath $Path
    foreach ($line in $listed) {
        if ("$line" -match '^worktree\s+(.+)$') {
            if ((ConvertTo-ComparablePath $Matches[1]) -eq $target) { return $true }
        }
    }
    return $false
}

Write-Log "=== start Repo=$RepoPath Worktree=$WorktreePath Branch=$BranchName WaitPid=$WaitPid AllowDirectoryDelete=$AllowDirectoryDelete"

if (-not (Test-Path -LiteralPath $RepoPath)) {
    Write-Log "リポジトリのパスが存在しないため中止する: $RepoPath"
    exit 1
}

if ($WaitPid -gt 0) {
    try {
        $proc = Get-Process -Id $WaitPid -ErrorAction Stop
        Write-Log "プロセス $WaitPid ($($proc.ProcessName)) の終了を待つ"
        Wait-Process -Id $WaitPid -ErrorAction Stop
        Write-Log "プロセス $WaitPid が終了した"
    }
    catch {
        Write-Log "プロセス $WaitPid は待機できなかった（既に終了しているか取得できない）: $($_.Exception.Message)"
    }
}

$defaultBranch = (Invoke-Git @('symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD')).Output
if (-not $defaultBranch) {
    Write-Log '既定ブランチを特定できないため中止する'
    exit 1
}
Write-Log "既定ブランチ: $defaultBranch"

if ($WorktreePath) {
    if (Test-WorktreeRegistered $WorktreePath) {
        $removed = Invoke-Git @('worktree', 'remove', $WorktreePath)
        if ($removed.ExitCode -ne 0) {
            Write-Log 'git worktree remove が失敗した。--force は付けない'
        }
    }
    else {
        Write-Log "worktree として登録されていない: $WorktreePath"
    }

    if (Test-Path -LiteralPath $WorktreePath) {
        if (Test-WorktreeRegistered $WorktreePath) {
            Write-Log 'まだ worktree として登録が残っているため、ディレクトリは削除しない（何かが掴んでいる可能性がある）'
        }
        else {
            $entries = @(Get-ChildItem -LiteralPath $WorktreePath -Force -ErrorAction SilentlyContinue)
            if ($entries.Count -eq 0) {
                try {
                    Remove-Item -LiteralPath $WorktreePath -Force -ErrorAction Stop
                    Write-Log "空のディレクトリを削除した: $WorktreePath"
                }
                catch {
                    Write-Log "空のディレクトリを削除できなかった: $($_.Exception.Message)"
                }
            }
            elseif ($AllowDirectoryDelete) {
                try {
                    Remove-Item -LiteralPath $WorktreePath -Recurse -Force -ErrorAction Stop
                    Write-Log "ディレクトリを削除した: $WorktreePath"
                }
                catch {
                    Write-Log "ディレクトリを削除できなかった: $($_.Exception.Message)"
                }
            }
            else {
                Write-Log "中身が残っており -AllowDirectoryDelete も指定されていないため残す: $WorktreePath （残り $($entries.Count) 件）"
            }
        }
    }
    else {
        Write-Log "worktree のパスは既に存在しない: $WorktreePath"
    }

    Invoke-Git @('worktree', 'prune', '-v') | Out-Null
}

if ($BranchName) {
    Invoke-Git @('fetch', 'origin', '--prune') | Out-Null
    $diff = Invoke-Git @('diff', '--stat', $defaultBranch, $BranchName)
    if ($diff.ExitCode -ne 0) {
        Write-Log "差分を確認できなかったためブランチを残す: $BranchName"
    }
    elseif ($diff.Output -ne '') {
        Write-Log "既定ブランチに入っていない変更があるためブランチを残す: $BranchName"
    }
    else {
        Invoke-Git @('branch', '-D', $BranchName) | Out-Null
    }
}

Write-Log '=== end'
