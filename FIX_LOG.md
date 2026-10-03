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

### 前置要求（Windows 端）

| 依赖 | 版本要求 | 说明 |
|------|----------|------|
| Flutter | 3.x（含 Windows desktop 支持） | 需在 `flutter doctor` 中显示 Windows 工具链正常 |
| Visual Studio 2022 | Build Tools 或完整版 | 勾选 "Desktop development with C++" 工作负载（MSVC v143 + Windows 10/11 SDK） |
| CMake | 3.x | 随 VS Build Tools 安装，或单独安装 |
| Git | 任意 | 克隆仓库用 |

### 构建命令

```powershell
git clone -b main https://github.com/lg152-git/dart_simple_live.git
cd dart_simple_live

# 1. 应用模块
cd simple_live_app
flutter pub get
flutter build windows --debug
# 运行
.\build\windows\x64\runner\Debug\simple_live_app.exe

# 2. 如需编译其他模块
cd ..\simple_live_console
flutter pub get
cd ..\simple_live_tv_app
flutter pub get
```

构建全程使用本地 vendor 的 7z 文件，**无需访问 GitHub**，网络环境受限也可正常编译。

### 首次构建注意事项

- `flutter build` 会自动触发 CMake 配置 + 编译所有 native 插件（media_kit、inappwebview、permission_handler 等），首次约 3~5 分钟。
- 构建完成后 `build\windows\x64\runner\Debug\` 下会有 `simple_live_app.exe` + 全套 `.dll`（libmpv-2.dll、libEGL.dll、libGLESv2.dll、flutter_windows.dll 等），**exe 必须和这些 dll 放在同一目录运行**，不能单独移动 exe。
- 如需 Release 版本：`flutter build windows --release`，产物在 `build\windows\x64\runner\Release\`。

### 已知构建警告（不影响运行，可忽略）

- `dart_quickjs.dll was not found during CMake configure` — 配置期找不到，但链接/运行期正常加载。
- `CMP0175` / inappwebview 的 `C4819`/`C4244`/`C4458` — MSVC 编码/类型转换噪音警告，不影响功能。

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

## 同步上游 master 的固定流程（保留 main 定制）

> 2026-10-03 更新。main 与 master 在 Git 历史里**没有共同祖先**（上游曾重建过仓库），
> 首次合并用了 `--allow-unrelated-histories`；此后两条线已建立共同祖先，正常 `git merge` 即可。

### 原则

- **master = 上游权威线**，跟踪 `origin/master`（上游镜像）
- **main = 定制线**，包含自己的修改（关注页、直播间、离线 vendor 构建等）
- 同步时：master 的新提交合入 main；**冲突按白名单解决**
  - `main_customizations.md` 两张表并集 = 白名单，**冲突时保留 main 版本（--ours）**
  - 白名单之外的文件 → 取 master 版本（上游权威）

### 一键脚本

```powershell
# 仓库根目录执行，自动 fetch + 快进 master + merge + 白名单冲突解决 + 推送
powershell -ExecutionPolicy Bypass -File .\sync-upstream.ps1

# 只看计划，不动仓库
powershell -ExecutionPolicy Bypass -File .\sync-upstream.ps1 -DryRun

# 只本地合并，不推送
powershell -ExecutionPolicy Bypass -File .\sync-upstream.ps1 -NoPush
```

脚本会顺带刷新 `main_customizations.md` 的差异行数，并在改动后追加一个
`chore: refresh customization manifest` 提交。

### 新增定制后怎么维护

1. 在 `main` 上提交你的修改。
2. 打开 `main_customizations.md`：
   - 是"源码定制" → 加进 **清单** 表（写清定制说明）
   - 是"离线/构建文件" → 加进 **永久定制** 表
3. 下次运行 `sync-upstream.ps1` 时，该文件自动进入白名单，冲突时保留 main 版本。
4. 想放弃某个定制（接受上游版本）：从表里删掉对应行，下次同步自动恢复 master 版。

### 安全网

- `main-backup` 分支（本地 + `origin/main-backup`）= 首次合并前的 main 快照
  （`b9c7705`，含全部 16 个定制提交），出问题随时 `git reset --hard main-backup` 回滚。
- 脚本中途失败：`git merge --abort` 即可回到执行前状态，定制不丢。

### 维护记录（2026-10-03 首次同步）

| 提交 | 说明 |
|------|------|
| `a00d7b3` | `--allow-unrelated-histories` 合并 master（c67a138）进 main |
| `2420476` | 修正 CMakeLists 回 vendor 模式（merge 时误取 master 原版导致 7z 校验失败） |
| `1e933c6` | 从 main-backup 找回被覆盖的 8 个定制文件 |
| `7f1700a` | 首用 `sync-upstream.ps1` 合入 master 3d5a9f3 的 3 个新提交（TV tag / 斗鱼断流 / README） |

main_customizations.md 里两张表的并集 = 白名单（冲突时保留 main 版本）：

- **清单表**：源码定制（关注页 / 直播间 / 火花数值等），main 改了 master 也改了的同名文件 → 保留 main
- **永久定制表**：离线/构建文件（vendor CMakeLists、ANGLE.7z、mpv-dev 7z、build_windows_release.bat、fix-integrity.ps1、FIX_LOG.md），**永远保留 main 版本**，上游改了也不覆盖

新增定制流程：在 main 上改完提交 → 把文件加进 `main_customizations.md` 对应表 → 下次运行 `sync-upstream.ps1` 自动纳入白名单。
放弃定制：从表里删掉该行 → 下次同步自动恢复 master 版本。

## 已验证

- `flutter build windows --debug` 编译通过
- 双击 exe 窗口正常渲染（抖音直播 / 弹幕 / 播放全通）
- `flutter run -d windows` 热重载正常（完整性标签修复后）
