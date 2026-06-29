# Relaunch

一个还原 macOS 经典版「启动台 (Launchpad)」的轻量菜单栏应用。macOS 26 的启动台改版后不好用，Relaunch 把它带回来：全屏毛玻璃背景、分页图标网格、输入即搜索。

## 功能

- **经典启动台 UI** — 全屏深色毛玻璃，7×5 分页网格，底部分页圆点，顶部搜索框。
- **四种唤起方式**
  - 触控板 **拇指 + 三指捏合**（经典手势，基于多点触控原始数据）。
  - 全局**快捷键** `⌃⌥L`（Control + Option + L）。
  - 点击菜单栏**常驻图标**。
  - 触控板四指捏合同样触发（与经典手势共用同一套检测）。
- **菜单栏常驻图标** — 下拉菜单可开关手势 / 快捷键 / 开机启动，并随时打开启动台或退出。
- **开机启动** — 基于 `SMAppService`（macOS 13+），菜单里一键开关。
- **文件夹与拖拽整理**
  - 拖一个图标到**另一个图标中间**→ 自动创建文件夹（拖到**左/右侧**则是重新排序）。
  - 拖图标到文件夹上 → 加入该文件夹。
  - 点击文件夹 → 打开浮层；浮层顶部可直接改名；文件夹内可拖拽重排，右键「移出文件夹」。
  - 文件夹只剩一个 App 会自动解散。布局保存到 `~/Library/Application Support/Relaunch/layout.json`，新装的应用自动追加。
  - **拖到屏幕左/右边缘**会自动翻页，可跨页移动图标。
- **导入旧版启动台分组**：首次启动若没有自己的布局，会自动读取旧版 Launchpad 数据库（`<DARWIN_USER_DIR>com.apple.dock.launchpad/db`）还原页面顺序与文件夹；也可随时通过菜单栏「导入旧版启动台分组」手动重新导入。按 bundle id 匹配已安装应用，已卸载的自动忽略。
- 输入即搜索；`Esc` 关闭（文件夹打开时先关文件夹，再清空搜索，最后关闭）；`←/→` 翻页；`Return` 打开第一个结果；点击空白处关闭。

## 构建

需要 Xcode 命令行工具（已含 Swift 6 / macOS 14+ SDK）。

```bash
./build.sh
```

产物为 `build/Relaunch.app`。

## 安装与运行

```bash
# 安装到 应用程序 文件夹（推荐，开机启动注册更稳定）
cp -R build/Relaunch.app /Applications/
open /Applications/Relaunch.app
```

启动后没有 Dock 图标（菜单栏应用），在屏幕右上角菜单栏会出现 ▦ 图标。点击它，或按 `⌃⌥L`，或在触控板上拇指 + 三指捏合，即可唤起启动台。

在菜单里勾选「开机启动」即可下次登录自动运行。

## 备注

- 多点触控手势使用系统私有框架 `MultitouchSupport`（运行时 `dlopen` 加载，无需特殊权限）。这是 BetterTouchTool 等工具采用的同一套机制；未来系统大版本升级理论上可能需要适配。
- 应用经过 ad-hoc 签名。若 Gatekeeper 拦截，可在「系统设置 → 隐私与安全性」中放行，或对其重新签名。
- 跨页拖动靠拖到屏幕左右边缘**停留**约 0.7 秒自动翻页，再松手落到目标页。

## 项目结构

```
Sources/Relaunch/
  main.swift                入口（accessory 应用）
  AppDelegate.swift         协调器：串联窗口 / 菜单栏 / 手势 / 快捷键
  AppInfo.swift             应用模型
  AppScanner.swift          扫描已安装应用
  LaunchpadModel.swift      网格状态与搜索过滤
  LaunchpadView.swift       SwiftUI 启动台界面
  LaunchpadController.swift 全屏覆盖窗口的显示/隐藏
  StatusBarController.swift  菜单栏图标与菜单
  HotkeyManager.swift       Carbon 全局快捷键
  MultitouchGesture.swift   触控板捏合手势检测
  LoginItem.swift           开机启动 (SMAppService)
Resources/Info.plist        LSUIElement 菜单栏应用配置
build.sh                    编译并打包为 .app
Package.swift               供 IDE / `swift build` 使用
```
