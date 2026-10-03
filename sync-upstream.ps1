# sync-upstream.ps1
# Sync upstream master into main, preserving main's customizations.
#
# Usage (run from repo root):
#   powershell -ExecutionPolicy Bypass -File .\sync-upstream.ps1             # full flow incl. push
#   powershell -ExecutionPolicy Bypass -File .\sync-upstream.ps1 -NoPush    # local only
#   powershell -ExecutionPolicy Bypass -File .\sync-upstream.ps1 -DryRun    # print plan, no changes
#
# Prereqs:
#   1. local master tracks origin/master (the upstream sync line)
#   2. main_customizations.md's two tables form the whitelist:
#        - "## 清单" table  : source files to KEEP main's version
#        - "## 永久定制" table: offline/build files to KEEP main's version
#      Union = files resolved with --ours on conflict
#   3. working tree clean

param(
    [switch]$NoPush,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Step($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Fail($msg) {
    Write-Host "[X] $msg" -ForegroundColor Red
    Write-Host "    (if mid-merge, run 'git merge --abort' to revert; main-backup branch keeps customizations safe)"
    exit 1
}

# Single-quoted regexes: PowerShell double-quoted strings treat backtick as escape char
$reManifestRow   = '^\|\s*`(.+?)`\s*\|'
$reManifestDesc  = '^\|\s*`(.+?)`\s*\|\s*\d+\s*\|\s*(.*?)\s*\|'
$rePermHeading = '^##\s*' + [char]0x6C38 + [char]0x4E45 + [char]0x5B9A + [char]0x5236
$reListHeading = '^##\s*' + [char]0x6E05 + [char]0x5355
$reSrcPath       = '^simple_live_(app|tv_app|core|console)/'
$reSkipBuild     = '/build/|/unit_test_assets/|flutter_\d+\.log|\.dill$|problems-report\.html'
$newDesc         = '(newly recorded, please add a description)'

# ---------- 0. whitelist ----------
$manifest = Join-Path $root "main_customizations.md"
if (-not (Test-Path $manifest)) { Fail "missing $manifest, cannot determine whitelist" }
$rawLines = @(Get-Content $manifest -Encoding UTF8)

$whitelist = @()
foreach ($line in $rawLines) {
    $t = $line.Trim()
    if ($t -match $reManifestRow) { $whitelist += $Matches[1] }
}
$whitelist = $whitelist | Sort-Object -Unique
Step "whitelist: $($whitelist.Count) files (conflicts keep main side)"
if (-not $DryRun -and $whitelist.Count -eq 0) { Fail "whitelist empty, manifest table not parsed, check main_customizations.md" }

# ---------- 1. fetch ----------
if ($DryRun) {
    Step "git fetch origin (dry-run)"
} else {
    Step "git fetch origin"
    $fetchOut = & git fetch origin 2>&1
    $fetchCode = $LASTEXITCODE
    if ($fetchCode -ne 0) {
        $fetchOut | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        Fail "fetch failed (exit $fetchCode), check network"
    }
    $fetchOut | Where-Object { $_ -notmatch "remote:" -and $_ -notmatch "^\s*$" } | ForEach-Object { Write-Host "  $_" }
}

# ---------- 2. fast-forward local master ----------
$originMaster = git rev-parse origin/master
if ($DryRun) {
    Step "local master will fast-forward to origin/master ($( $originMaster.Substring(0,7) ))"
} else {
    Step "sync local master -> origin/master"
    $null = git update-ref refs/heads/master $originMaster
}
Step "master now = $(git rev-parse --short master)"

# ---------- 3. checkout main ----------
$curBranch = git symbolic-ref --short HEAD
if ($curBranch -ne "main") {
    if ($DryRun) {
        Step "will switch to main"
    } else {
        Step "git checkout main"
        $coOut = & git checkout main 2>&1
        if ($LASTEXITCODE -ne 0) {
            $coOut | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            Fail "git checkout main failed"
        }
        $coOut | Where-Object { $_ -notmatch "^\s*$" } | ForEach-Object { Write-Host "  $_" }
        $dirty = git status --porcelain
        if ($dirty) { Fail "main working tree dirty, git stash or commit first" }
    }
}

# ---------- 4. merge ----------
Step "git merge master"
if ($DryRun) {
    $ahead = git rev-list --count main..master
    Step "  will merge $ahead upstream commit(s) into main (conflicts auto-resolved by whitelist)"
    Step "dry-run finished, nothing changed"
    exit 0
}

$mergeOut = & git merge master 2>&1
$mergeOk = ($LASTEXITCODE -eq 0)
if (-not $mergeOk) {
    $base = (git merge-base master main 2>$null)
    if ([string]::IsNullOrWhiteSpace($base)) {
        Step "no common ancestor, retrying with --allow-unrelated-histories"
        $null = git merge --abort 2>$null
        $null = git merge master --allow-unrelated-histories 2>&1
        $mergeOk = ($LASTEXITCODE -eq 0)
    }
}

if ($mergeOk) {
    Step "no conflicts, auto-committed $(git rev-parse --short HEAD)"
} else {
    Step "conflicts: resolving by whitelist"
    $conflicted = @(git diff --name-only --diff-filter=U)
    $oursCount = 0
    $theirsCount = 0
    foreach ($f in $conflicted) {
        $fstr = $f.ToString()
        if ($whitelist -contains $fstr) {
            git checkout --ours -- $fstr 2>&1 | Out-Null
            git add -- $fstr 2>&1 | Out-Null
            Write-Host "  [ours]   $fstr  (keep main customization)" -ForegroundColor Green
            $oursCount++
        } else {
            git checkout --theirs -- $fstr 2>&1 | Out-Null
            git add -- $fstr 2>&1 | Out-Null
            Write-Host "  [theirs] $fstr  (take upstream)" -ForegroundColor DarkYellow
            $theirsCount++
        }
    }
    $still = @(git diff --name-only --diff-filter=U)
    if ($still) {
        Fail "$($still.Count) unresolved conflict(s): $($still -join ', '). Add the file to main_customizations.md then git merge --abort and rerun"
    }
    $cmt = "chore: sync upstream master into main"
    if (Test-Path ".git\MERGE_MSG") {
        $cmt = (Get-Content ".git\MERGE_MSG" -Raw) -split "`n" | Where-Object { $_ -notmatch "^#" } -join "`n"
    }
    $null = git commit -m $cmt -m "whitelist kept $oursCount [ours] files, took $theirsCount [theirs] files from upstream"
    Step "conflicts resolved, committed $(git rev-parse --short HEAD)"
}

# ---------- 5. refresh manifest diff-line counts ----------
Step "refreshing main_customizations.md diff-line counts"
$changed = @(git diff --name-only master main | Where-Object {
        ($_ -match $reSrcPath) -and (-not ($_ -match $reSkipBuild))
    })

$descByPath = @{}
foreach ($line in $rawLines) {
    $t = $line.Trim()
    if ($t -match $reManifestDesc) { $descByPath[$Matches[1]] = $Matches[2] }
}

$permIdx = -1
for ($i = 0; $i -lt $rawLines.Count; $i++) {
    if ($rawLines[$i] -match $rePermHeading) { $permIdx = $i; break }
}
$listIdx = -1
for ($i = 0; $i -lt $rawLines.Count; $i++) {
    if ($rawLines[$i] -match $reListHeading) { $listIdx = $i; break }
}

$newTable = @()
$newTable += "| file | diff-lines vs master | description |"
$newTable += "|------|------|------|"
foreach ($f in $changed) {
    $fstr = $f.ToString()
    $ln = (git diff master main -- $fstr | Measure-Object -Line).Lines
    $desc = if ($descByPath.ContainsKey($fstr)) { $descByPath[$fstr] } else { $newDesc }
    $row = "| ``$fstr`` | " + $ln + " | " + $desc + " |"
    $newTable += $row
}

$headText = if ($listIdx -ge 0) {
    ($rawLines[0..($listIdx - 1)] -join "`n")
} else {
    ($rawLines -join "`n")
}
$tailText = if ($permIdx -ge 0) {
    ($rawLines[$permIdx..($rawLines.Count - 1)] -join "`n")
} else {
    ""
}
$newContent = $headText + "`n" + "## " + [char]0x6E05 + [char]0x5355 + "`n" + "`n" + ($newTable -join "`n") + "`n" + "`n" + $tailText + "`n"

$curRaw = Get-Content $manifest -Raw
if (($curRaw -replace "\s+", " ") -ne ($newContent -replace "\s+", " ")) {
    Set-Content -Path $manifest -Value $newContent -Encoding UTF8 -NoNewline
    $null = git add $manifest
    $null = git commit -m "chore: refresh customization manifest"
    Step "manifest refreshed, extra commit added"
} else {
    Step "manifest unchanged"
}

# ---------- 6. push ----------
if ($NoPush) {
    Step "skipped push (-NoPush). local main = $(git rev-parse --short HEAD)"
} else {
    Step "git push origin main"
    # git writes progress lines to stderr; capture & inspect without letting PS treat stderr as an error
    $pushOut = & git push origin main 2>&1
    $pushCode = $LASTEXITCODE
    if ($pushCode -eq 0) {
        $pushOut | Where-Object { $_ -notmatch "remote:" -and $_ -notmatch "^\s*$" } | ForEach-Object { Write-Host "  $_" }
    } else {
        $pushOut | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        Fail "push failed (exit $pushCode), check network/credentials"
    }
}

Step "done. main = $(git rev-parse --short HEAD), whitelist $($whitelist.Count) files preserved"
