<div align="center">

<img src="docs/icon.png" width="128" alt="Relaunch 图标">

# Relaunch

**把经典版 macOS 启动台带回来。**

macOS 26 (Tahoe) 移除了经典的全屏启动台,Relaunch 用原生方式还原它——毛玻璃背景、分页图标网格、文件夹、输入即搜索。

[![Latest release](https://img.shields.io/github/v/release/JakeLaoyu/relaunch)](https://github.com/JakeLaoyu/relaunch/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/JakeLaoyu/relaunch/total)](https://github.com/JakeLaoyu/relaunch/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue)](#系统要求)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[下载](https://github.com/JakeLaoyu/relaunch/releases/latest) · [功能](#功能) · [从源码构建](#从源码构建) · [English](README.md)

<img src="docs/screenshot.png" alt="Relaunch 全屏启动台" width="800">

</div>

---

## 为什么做这个

macOS 26 把经典全屏启动台换成了 Spotlight 风格的「应用程序」视图。如果你怀念旧版——深色毛玻璃、7×5 网格、文件夹、捏合手势——Relaunch 以一个轻量原生应用把它带回来。没有 Electron、没有后台守护进程、不需要任何特殊权限。

## 功能

- **经典启动台 UI** — 全屏深色毛玻璃,7×5 分页网格,底部分页圆点,顶部搜索框,覆盖 Dock 与菜单栏。
- **五种唤起方式**
  - **触控板捏合** — 拇指 + 三指捏合打开(张开关闭),基于多点触控原始数据,无需辅助功能权限。
  - **全局快捷键** — `⌃⌥L`(Control–Option–L)。
  - **点击 Dock 图标**(可在设置中隐藏)。
  - **点击菜单栏图标** — 下拉菜单可打开设置 / 导入 / 退出。
  - **开机启动** — 基于 `SMAppService`。
- **输入即搜索** — 直接打字开始搜索;`←`/`→` 翻页,`Return` 打开第一个结果,`Esc` 关闭。
- **文件夹与拖拽整理**
  - 把图标拖到**另一个图标中间**创建文件夹(拖到**旁边**则是排序)。
  - 点击文件夹打开浮层;可直接改名、拖拽重排、右键移出。
  - 拖动时靠到**屏幕左右边缘**自动翻页,可跨页移动。
  - 少于两个应用的文件夹自动解散。
- **导入旧版启动台布局** — 首次启动自动读取经典 Launchpad 数据库,还原页面顺序与文件夹;也可随时在菜单或设置中重新导入。
- **不打扰你** — 布局保存在 `~/Library/Application Support/Relaunch/layout.json`;新装应用自动追加,已卸载的自动移除。
- **多语言** — 英语、德语、西班牙语、法语、日语、韩语、简体中文、繁体中文。
- **原生通用二进制** — Swift + AppKit + SwiftUI,同时支持 Apple Silicon 与 Intel。

## 安装

### 下载(推荐)

从 [Releases 页面](https://github.com/JakeLaoyu/relaunch/releases/latest)下载最新 DMG,打开后把 **Relaunch** 拖入**应用程序**文件夹。发布版本经过 Developer ID 签名与公证,Gatekeeper 直接放行。

### 系统要求

- macOS 14.0 (Sonoma) 及以上,Apple Silicon 或 Intel。

## 从源码构建

只需要 Xcode 命令行工具,没有 Xcode 工程。`build.sh` 用 `swiftc` 编译通用二进制并组装 `.app`:

```bash
git clone https://github.com/JakeLaoyu/relaunch.git
cd relaunch
./build.sh                          # -> build/Relaunch.app(ad-hoc 签名)
cp -R build/Relaunch.app /Applications/
open /Applications/Relaunch.app
```

建议安装到 `/Applications`,开机启动注册更稳定,Spotlight 也会索引。本地构建为 ad-hoc 签名;若 Gatekeeper 拦截,可在「系统设置 → 隐私与安全性」中放行,或用自己的证书签名:

```bash
CODESIGN_IDENTITY="Developer ID Application: … (TEAMID)" ./build.sh
```

`Package.swift` 仅用于 IDE 支持(`swift build` 能编译源码,但不会产出可运行的 `.app`)。

## 实现方式

| 部分 | 方案 |
|---|---|
| 覆盖窗口 | 无边框 `NSWindow`,shielding 层级,覆盖 Dock 与菜单栏 |
| 网格 UI | SwiftUI,`.scrollTargetBehavior(.paging)`,拖拽 + 文件夹浮层 |
| 捏合手势 | 私有 `MultitouchSupport.framework`,运行时 `dlopen` 加载(BetterTouchTool 同款机制),无需辅助功能权限 |
| 全局快捷键 | Carbon `RegisterEventHotKey`,系统级、无需权限 |
| 旧版导入 | 读取经典 Launchpad 的 SQLite 数据库,按 bundle ID 匹配已安装应用 |
| 应用扫描 | 扫描 `/Applications`、`/System/Applications`、`~/Applications` |

### 关于私有框架

捏合手势依赖私有 API `MultitouchSupport.framework`。它多年来在各版 macOS 上都很稳定,但未来大版本更新理论上可能需要适配。其余功能——快捷键、Dock、菜单栏——全部使用公开 API,不受影响。手势可在设置中关闭。

## 参与贡献

欢迎提 Issue 和 PR——bug 反馈、功能建议,尤其欢迎新语言翻译。添加语言:复制一份已有翻译(如 `Resources/fr.lproj/Localizable.strings`)为新的 `<locale>.lproj` 目录并翻译其中的值即可(键就是英文原文,保持不变)。

构建/测试流程、架构说明和子系统注意事项见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)(英文)。

## 许可证

[MIT](LICENSE)
