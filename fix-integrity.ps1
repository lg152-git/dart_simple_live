# fix-integrity.ps1
# One-click fix for the Windows Mandatory Integrity Label on the workspace.
#
# Background:
#   The workspace root may be tagged "Low Mandatory Level" by the sandbox.
#   All build outputs (Debug/Release exes) inherit the LOW label.
#   A LOW process writing to MEDIUM-integrity AppData/Temp is denied
#   (errno=5), causing white screen / media_kit / hive / DevFS init failure.
#
# When to run (any of these symptoms):
#   - simple_live_app.exe shows black border + white screen, no UI
#   - flutter run reports "_createDevFS: PathAccessException ... errno=5"
#   - log shows "Async Error: PathAccessException: Cannot create file ... com.alexmercerind..."
#
# Usage (normal user, no admin needed):
#   powershell -ExecutionPolicy Bypass -File .\fix-integrity.ps1
#
# Idempotent: safe to run repeatedly.

$ErrorActionPreference = "Stop"

$Root = "D:\project\simple_live"

# All exe targets that should carry a Medium integrity label.
# The script fixes the root dir first, then every exe that exists under the
# build tree (Debug and Release). Newly built exes inherit the root label,
# so a stale exe with a leftover LOW label is covered here.
$Exes = @(
  "$Root\repo\simple_live_app\build\windows\x64\runner\Debug\simple_live_app.exe",
  "$Root\repo\simple_live_app\build\windows\x64\runner\Release\simple_live_app.exe"
)

Write-Host "=== Integrity label BEFORE fix (root) ===" -ForegroundColor Cyan
& icacls "$Root" 2>&1 | Select-String "Mandatory"

# 1. Restore root dir to Medium integrity
icacls "$Root" /setintegritylevel M | Out-Null

# 2. Restore every existing exe to Medium integrity
foreach ($Exe in $Exes) {
    if (Test-Path $Exe) {
        icacls "$Exe" /setintegritylevel M | Out-Null
    } else {
        Write-Host "Note: not found, skipping -> $Exe" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== Integrity label AFTER fix ===" -ForegroundColor Cyan
& icacls "$Root" 2>&1 | Select-String "Mandatory"
foreach ($Exe in $Exes) {
    if (Test-Path $Exe) {
        Write-Host ""
        Write-Host "$Exe" -ForegroundColor DarkGray
        & icacls "$Exe" 2>&1 | Select-String "Mandatory"
    }
}

Write-Host ""
Write-Host "Done. Relaunch simple_live_app.exe to verify (window should render, not white)." -ForegroundColor Green
