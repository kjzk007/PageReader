# PageReader

把网页文档当书管理，记住你读到哪一段。

PageReader 尝试解决以下痛点：

1. 你想阅读网页文档方便学习；
2. 每次打开网页非常零散，不利于管理；
3. 每次打开网页忘记自己读到哪里；
4. 网页不像软件，但"作为应用安装"后，每次打开都回到了一开始安装的页面。

> **关于诚信**
>
> 它是通过 vibe coding 开发。即便在动手前做了大量的技术讨论、选型决策、方案探索，
> 也不能取代真实人类工程师的开发过程。所以即使已经过多轮真机验证，
> 难免还有意外情况。遇到问题请提交 issue，我会认真处理。

---

# 使用感受

> 就像阅读软件的读电子书的体验，没别的。

使用流程：

1. 下载 Windows 便携包，解压，双击 `pagereader.exe`
2. 点右上角 `+`，粘贴一个文档站地址（可以自己命名）
3. 点那本书开始读

关掉窗口，下次点同一本书，回到你停下的那一段。

---

# 它能做什么

1. **桌面端内嵌网页内核**（WebView2），网页渲染在程序自己的窗口里
2. **不干扰你的浏览器** —— 程序用自己的数据目录，你平时开的 Edge/Chrome 完全不受影响，也不会被关闭
3. **能用你的浏览器插件** —— 插件读的是你浏览器里已装的那份，不复制文件；在设置里勾选哪些要在阅读时生效
4. **登录态延续** —— 首次运行会搬一份浏览器的登录数据过来，打开网页时通常已是登录状态
5. **精确到段落的位置记录** —— 不是"大概在这个位置"，而是记住具体是哪一段、段内偏移多少
6. **多端同步** —— 桌面端和 Android 之间同步书架与进度
7. 文档、教程加入链接统一管理，支持分组、搜索

---

# 快速开始

## 1 直接用（Windows 便携版）

1. 下载 Release 里的 `PageReader-portable-*.zip`
2. 解压到任意目录，双击 `pagereader.exe`
3. 数据存在 `%APPDATA%\com.pagereader\PageReader\`，删掉程序目录不影响数据

**系统要求**：Windows 10 及以上。需要 WebView2 运行时 —— Win11 自带，
Win10 通常已随 Edge 装好；万一没有，从
[微软官网](https://developer.microsoft.com/microsoft-edge/webview2/) 装一次即可（约 2MB）。

**第一次运行会做两件事**：

- 建立数据目录
- 问一次要用哪些浏览器插件（默认全选，之后可在设置里改）

## 2 直接用（Android）

下载 Release 里的 `PageReader-*.apk` 安装。要求 **Android 8.0+**。

Android 端用的是系统 WebView，所以能不能正常显示取决于系统 WebView 版本。

## 3 从源码构建

需要 Flutter 3.47+ / Dart 3.13+。

```bash
git clone https://github.com/kjzk007/PageReader.git
cd PageReader
flutter pub get

# Windows
flutter build windows --release

# Android
flutter build apk --release
```

桌面端构建需要 WebView2 SDK，已随仓库放在 `windows/webview2/`，不需要额外下载。

改了数据库表结构才需要重跑代码生成：

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

# 桌面端架构：为什么用内嵌内核

早期版本是「启动外部浏览器 + CDP 连过去」，那条路有两个绕不过去的问题：

1. **抢 profile** —— 要用用户的插件和登录态就得用真实 profile，而同一个数据目录
   只能有一个实例持有调试端口。用户开着浏览器时就拿不到端口、记不了进度。
2. **Edge 拒绝在默认目录开调试端口** —— 日志原文是
   `DevTools remote debugging requires a non-default data directory`。
   复制 profile 到别处能开端口，但 Edge 启动时会删掉未注册的插件目录。

现在改成内嵌 WebView2：

| 维度 | 现在 |
|---|---|
| 内核位置 | 程序进程内，独立数据目录 |
| 你的浏览器 | 完全不受影响，不会被关 |
| 插件 | `AddBrowserExtension` 引用原目录，不复制文件 |
| 进度记录 | 页面脚本主动上报，不需要调试端口 |

关键实现细节写在 `windows/runner/webview_host.h` 和
`lib/engine/desktop/webview2_engine.dart` 的注释里，包括踩过的坑。

---

# 项目结构

```
lib/
├── core/
│   ├── domain/        纯 Dart 模型与注入脚本（无 Flutter 依赖）
│   ├── ports/         接口定义：LibraryStore / WebEngine
│   ├── services/      设置存储、主题、图标抓取
│   └── sync/          同步协议、合并、镜像、服务端、客户端、配对设备
├── data/              drift + SQLite 实现
├── engine/
│   ├── desktop/       WebView2 引擎 + 插件探查（内嵌内核）
│   └── android/       WebView 引擎（系统 WebView）
├── features/
│   ├── bookshelf/     书架：网格、分组、搜索、右键/长按菜单
│   ├── reader/        阅读页（Android）
│   ├── settings/      设置、插件开关、首次使用引导
│   ├── sync/          同步页（桌面端二维码 / 手机端扫码）
│   └── diagnostics/   诊断面板
└── main.dart          Provider 装配、启动流程

windows/
├── runner/
│   ├── webview_host.h/.cpp   WebView2 宿主（COM、窗口、脚本注入、插件）
│   ├── flutter_window.h/.cpp Flutter 窗口 + 通道注册时机
│   └── main.cpp
└── webview2/          WebView2 SDK（头文件 + 加载器，随仓库提供）
```

分层原则：`core/domain` 不依赖 Flutter，可以用纯 Dart 测试；
`engine` 依赖平台能力但只暴露 `WebEngine` 接口；`features` 只认接口不认实现。

---

# 插件怎么工作

1. 程序扫描你浏览器的插件目录（Edge / Chrome / Brave），列出所有插件
2. 你勾选哪些要在阅读时生效
3. 打开书时，程序把勾选的插件路径交给 WebView2 加载
4. **插件文件不被复制** —— 用的就是你浏览器里那份，所以随时在设置里增减，立刻生效

插件的数据（登录 token、配置）存在程序自己的数据目录，和浏览器各存各的，不会打架。

---

# 测试

```bash
flutter test                      # 283 项单元 + 集成测试
dart run tool/verify_all.dart     # 桌面端端到端（真实内核）
dart run tool/verify_sync.dart    # 同步服务协议验证
```

`verify_all.dart` 跑在 `.verify-data/` 沙箱里，**不碰你的真实书架数据**。

---

# 已知限制

| 限制 | 原因 |
|---|---|
| 桌面端只支持 Windows | WebView2 是 Windows 组件 |
| 插件只扫 Edge / Chrome / Brave | 其它 Chromium 系浏览器（Vivaldi、360、QQ 等）暂时扫不到 |
| 部分老安卓设备打开书黑屏 | 系统 WebView 与 GPU 驱动兼容性，详见下方 |
| Android 网页不跟随 app 深浅色 | WebView 没有引擎级的媒体查询覆盖 API |
| 跨域名跳转算新的一页 | 进度按「书 + URL」记录，换域名就是新页面 |

# 关于在部分华为/P30 设备上黑屏

+ 华为（Android 10，华为自研 WebView Chromium 83）上打开书是全黑
+ 小米（Android 8.1，Google 官方 WebView Chromium 68）上完全正常

日志显示是 GPU 缓冲区拿不到：

```
Gralloc3: allocator 3.x is not supported
mali_winsys: new_window_surface(...) returns 0x3000
OpenGLRenderer: dequeueBuffer failed, error = -110
```

关 Impeller、给 WebView 设软件层都试过，只能做到"能显示但掉帧 78~99%"，
而且同一份 APK 两次结果不一致。这台设备的 WebView 也无法升级
（无 GMS、无 Chrome、Fallback 默认关闭、bootloader 锁死）。

结论：不是应用的问题，是那套 WebView + gralloc 组合的兼容性。不做妥协性适配。

---

# 数据存储位置

| 平台 | 位置 |
|---|---|
| Windows | `%APPDATA%\com.pagereader\PageReader\` |
| Android | 应用私有目录 `files/`（需 root 或 `adb backup` 才能取出） |

Windows 目录内容：

```
pagereader.sqlite    书架与阅读进度
settings.json        设置、插件勾选、同步凭据
webview2\            网页内核数据（插件数据、Cookie）
webview2.log         内核诊断日志（排查问题用）
extensions-backup\   插件备份（浏览器把插件删了还能救回来）
```

**彻底重置**：删掉整个 `PageReader` 目录即可。

用环境变量 `PAGEREADER_DATA_DIR` 可以重定向数据目录 —— 验收脚本靠它做沙箱隔离。

---

# 卸载

Windows 便携版：直接删掉解压出来的文件夹。
程序不在系统里留下任何东西（没有注册表项、没有服务、没有计划任务）。

想连数据一起清掉，再删 `%APPDATA%\com.pagereader\PageReader\`。

---

# 许可

MIT
