# fix-integrity.ps1
# 一键修复 D:\project\simple_live 工作区的 Windows 完整性级别标签。
#
# 背景：
#   该工作区根目录曾被 sandbox 标记为 "Low Mandatory Level"，
#   导致其下所有构建产物（simple_live_app.exe 等）继承 LOW 完整性标签。
#   LOW 进程写 MEDIUM 完整性的 AppData/Temp 会被 Windows 强制拒绝
#   （errno=5），表现为应用白屏、media_kit/hive/DevFS 初始化失败。
#
# 触发条件（出现以下任一现象即需运行本脚本）：
#   - 启动 simple_live_app.exe 后黑边框 + 白屏，无 UI 渲染
#   - flutter run 报 "_createDevFS: PathAccessException ... 拒绝访问 errno=5"
#   - 日志出现 "Async Error: PathAccessException: Cannot create file ... com.alexmercerind.media_kit..."
#
# 用法：以普通用户身份运行即可（不需要管理员）：
#   powershell -ExecutionPolicy Bypass -File .\fix-integrity.ps1
#
# 幂等：可重复运行，不会造成副作用。

$ErrorActionPreference = "Stop"

$Root   = "D:\project\simple_live"
$Exe    = "$Root\repo\simple_live_app\build\windows\x64\runner\Debug\simple_live_app.exe"

Write-Host "=== 修复前完整性标签 ===" -ForegroundColor Cyan
& icacls "$Root" 2>&1 | Select-String "Mandatory"

# 1. 根目录恢复 Medium 完整性
icacls "$Root" /setintegritylevel M | Out-Null
# 2. 当前已构建的 exe 恢复 Medium（新构建的 exe 会继承根目录标签，
#    但如果旧 exe 残留，也一并修）
if (Test-Path $Exe) {
    icacls "$Exe" /setintegritylevel M | Out-Null
} else {
    Write-Host "提示: exe 尚不存在（未构建），跳过 exe 标签修复。" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== 修复后完整性标签 ===" -ForegroundColor Cyan
& icacls "$Root" 2>&1 | Select-String "Mandatory"
if (Test-Path $Exe) {
    & icacls "$Exe" 2>&1 | Select-String "Mandatory"
}

Write-Host ""
Write-Host "完成。重新启动 simple_live_app.exe 验证（窗口应正常渲染，非白屏）。" -ForegroundColor Green
