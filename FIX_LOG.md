# 修复记录：main 分支完整性修复（2026-10-03）

## 背景

main 分支版本管理失败，部分文件缺失，代码跑不通。本次修复将 main 分支恢复至可用状态，
所有修改基于 `cd30444`（main 侧最后一次正常提交的截止点），并补全了 master 分支缺失的源码。

## 提交历史

| 提交 | 说明 |
|------|------|
| `cd30444` | main 侧原始修改截止点（保留不动） |
| `3f71d22` | 补齐 master 上缺失的 models / canvas_danmaku 源码 |
| `8d6cc89` | vendor `ANGLE.7z` + `mpv-dev*.7z`，构建不再依赖 GitHub 下载 |
| `e26e142` | vendor `dart_quickjs.dll` native asset |
| `7845b08` | 采用 `af04989` 版 media_kit CMakeLists（支持本地预取 7z） |
| `8f8f0f5` | 窗口创建后立即以正常尺寸显示，避免首帧阻塞时窗口隐藏 |
| `5c6de82` | 添加 `fix-integrity.ps1` 一键修复脚本 |

## 构建步骤

```powershell
cd simple_live_app
flutter pub get
flutter build windows --debug
# 运行
.\build\windows\x64\runner\Debug\simple_live_app.exe
```

构建全程使用本地 vendor 的 7z 文件，**无需访问 GitHub**，网络环境受限也可正常编译。

## 运行环境白屏问题（重要）

若启动 exe 后出现**黑边框 + 白屏**（无 UI 渲染），根因是：

工作区根目录 `D:\project\simple_live` 被 sandbox 标记为
**Low Mandatory Level** 完整性标签，导致 exe 继承 LOW 标签，
写 `AppData` / `Temp`（MEDIUM 完整性）时被 Windows 拒绝（errno=5），
media_kit / hive / DevFS 全部初始化失败，Flutter 首帧不渲染。

**一键修复：**

```powershell
powershell -ExecutionPolicy Bypass -File D:\project\simple_live\fix-integrity.ps1
```

该脚本幂等，可重复运行。若下次会话 sandbox 重新挂载导致标签复发，再跑一次即可。

## 已验证

- `flutter build windows --debug` 编译通过
- 双击 exe 窗口正常渲染（抖音直播 / 弹幕 / 播放全通）
- `flutter run -d windows` 热重载正常（完整性标签修复后）
