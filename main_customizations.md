# main 分支定制文件清单（权威）

> 本清单由 `sync-upstream.ps1` 在每次同步上游时自动维护（第 11 步）。
> 手动新增定制文件后，下次运行同步脚本会自动补录；**删除某行 = 下次同步时该文件恢复为 master 版本**，请谨慎删除。

## 规则

- 上游 `master` 是权威主线，同步时 master 更新会被合入 `main`。
- 清单中列出的文件 = **main 侧的定制**，冲突解决时**必须取 main 侧**（`--ours`），
  上游对这些文件的更新需要在合并后手工挑拣回来，不能整文件丢弃 main 版本。
- 未列出的文件：冲突时默认取 master 侧（上游权威）。

## 清单

| file | diff-lines vs master | description |
|------|------|------|
| `simple_live_app/lib/main.dart` | 25 | 火花数值只保留 HTTP 轮询的正在观看人数；窗口生命周期定制 |
| `simple_live_app/lib/modules/follow_user/follow_user_controller.dart` | 234 | 关注页自动刷新性能优化 |
| `simple_live_app/lib/modules/follow_user/follow_user_page.dart` | 185 | 关注页精简状态/平台分组与进度提示 |
| `simple_live_app/lib/widgets/follow_user_item.dart` | 80 | 关注列表卡片：去除"正在观看"标识等 UI 调整 |
| `simple_live_app/lib/modules/live_room/live_room_controller.dart` | 114 | 直播间关注列表仅显示开播中并按平台排序 |
| `simple_live_app/lib/services/follow_service.dart` | 173 | 关注列表刷新策略定制 |
| `simple_live_app/windows/runner/flutter_window.cpp` | 23 | 窗口创建后立即以正常尺寸显示，避免 media_kit 阻塞首帧时窗口隐藏 |
| `simple_live_app/windows/runner/flutter_window.h` | 21 | 窗口生命周期声明（配合上方实现） |
| `simple_live_app/windows/runner/win32_window.cpp` | 86 | 白闪修复 + 最大化/恢复窗口保持启动尺寸 |
| `simple_live_app/windows/runner/win32_window.h` | 52 | 窗口尺寸状态声明 |
| `simple_live_console/pubspec.lock` | 614 | console 模块依赖锁定 |
| `simple_live_tv_app/lib/modules/live_room/live_room_controller.dart` | 13 | TV 端直播间适配 |
| `simple_live_tv_app/pubspec.lock` | 1373 | TV 模块依赖锁定 |
| `simple_live_core/lib/src/huya_site.dart` | 294 | 虎牙断流修复 |
| `simple_live_core/packages/tars_dart/lib/tars/net/base_tars_http.dart` | 33 | tars HTTP 层适配 |
| `simple_live_app/.metadata` | 30 | Flutter 工具链版本记录 |

## 永久定制（不参与"取 master"策略，即使上游改了也保留 main 版本）

以下文件是 main 侧为离线构建/本地环境刻意修改的，**上游 master 的同名文件是"原样"版**，
合并时必须保留 main 版本（否则离线 vendor 构建会坏）：

| 文件 | 说明 |
|------|------|
| `third_party/media_kit_libs_windows_video/windows/CMakeLists.txt` | vendor 模式：跳过 GitHub 下载，直接用本地预取的 7z |
| `third_party/media_kit_libs_windows_video/ANGLE.7z` | 本地预取资源（二进制） |
| `third_party/media_kit_libs_windows_video/mpv-dev-x86_64-*.7z` | 本地预取资源（二进制） |
| `fix-integrity.ps1` | 完整性标签一键修复脚本（Debug + Release 双 exe） |
| `FIX_LOG.md` | 修复/构建记录 |
| `main_customizations.md` | 本清单自身 |
| `sync-upstream.ps1` | 同步上游脚本 |
| `simple_live_app/pubspec.yaml` | 固定 dynamic_color 1.8.1，规避 1.9.0+ Android 编译 bug |
| `.github/workflows/build_android_apk.yml` | 自定义 CI：构建 main 最新 commit 的 Android APK |
| `.github/workflows/build_ios_ipa.yml` | 自定义 CI：构建 iOS 未签名 IPA |
| `.github/workflows/publish_app_dev.yaml` 等 | 上游发布工作流本地化调整（仅手动触发，省 CI 配额） |
| `.gitignore` | 本地忽略规则（不忽略 vendor 7z；豁免 FIX_LOG.md / main_customizations.md） |

## 维护

- 新增定制：把文件加入上方"清单"表，写明定制说明。
- 删除定制（接受上游版本）：从表中删掉该行即可，下次同步自动恢复 master 版本。
- 本文件由脚本自动重写第 1 张表（差异行数），**手工维护的是"定制说明"列与"永久定制"表**。

## 冲突解决纪律（重要，必读）

> 见 `FIX_LOG.md` 的"冲突解决纪律"一节。核心原则：**本白名单 = 冲突时保留 main 侧的文件**。
> 白名单之外的冲突文件 → 取 master（上游权威）。绝不对全部冲突无脑 `--theirs`
> （曾因此覆盖本地 vendor 构建 + 8 个功能定制文件，事后逐个从 main-backup 找回）。

新增定制文件时务必加进对应表，否则下次 `sync-upstream.ps1` 同步它的冲突会被默认取
master（上游），你的定制就丢了。拿不准时：先 `git log -p master..main -- <file>` 看 main
侧为什么改，再判断该保留 main 还是取 master。
