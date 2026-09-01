# Claude Code のプロセス終了を待ってから、worktree とブランチを削除する。
# 待ち時間の秒数は持たない。プロセスの終了そのものを待つ。
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepoPath,
    [string]$WorktreePath,
    [string]$BranchName,
    [int]$WaitPid = 0,
    [string]$LogPath
)

$ErrorActionPreference = 'Continue'

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

Write-Log "=== start Repo=$RepoPath Worktree=$WorktreePath Branch=$BranchName WaitPid=$WaitPid"

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
    if (Test-Path -LiteralPath $WorktreePath) {
        $removed = Invoke-Git @('worktree', 'remove', $WorktreePath)
        if ($removed.ExitCode -ne 0) {
            Write-Log 'worktree を削除できなかった。--force は付けない。内容を確認すること'
        }
    }
    else {
        Write-Log "worktree のパスが既に存在しない: $WorktreePath"
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
