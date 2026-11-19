# PageReader

PageReader 尝试解决以下痛点：

1. 你想阅读网页文档方便学习；
2. 每次打开网页非常零散，不利于管理；
3. 每次打开网页忘记自己读到哪里；
4. 网页不像软件，但“作为应用安装”后，每次打开都回到了一开始安装的页面。

> **我想强调的诚信**：
> 
> 它是通过 vibe coding 开发，即便在动手前做了大量的技术讨论、选型决策、方案探索，但也不能取代真实人类工程师的开发过程，所以即使已经通过多个真机验证，也难免出现一些某些意外情况，如果您在使用过程中遇到什么问题，请向我提交issue


# 不用技术参数遮掩体验，直接描述使用 PageReader 的感受

> 就像阅读软件的读电子书的体验，没别的

使用流程：

1. 下载 Windows 便携包并解压
2. 打开桌面应用，并点击右上角添加你的链接（添加时也可以自己命名链接的名称）
3. 点击添加的“书籍”，开始阅读即可


---

# 它能做什么


1. Windows 阅读窗口复用 Chrome/Edge 浏览器的 `--app` 作为应用打开，从而获得更好的阅读体验
2. Android 阅读窗口复用系统 WebView 作为阅读窗口，原因同上，且原本就是网页文档，所以用 WebView 兼容和统一性更好
3. 文档、教程加入链接，统一管理，进度同步，关掉后，下次打开仍然是同一个地方
4. 添加的书籍、阅读进度、分组等功能可以多端同步

---

# 快速开始

## 1 直接用（Windows 便携版）

1. 下载 Release 里的 `PageReader-portable-*.zip`
2. 解压到任意目录，双击 `pagereader.exe`
3. 数据存在 `%APPDATA%\com.pagereader\PageReader\`，删掉程序目录不影响数据

需要机器上有 Microsoft Edge 或 Google Chrome。

## 2 直接用（Android）

下载 Release 里的 `PageReader-android-*.apk` 安装。要求 **Android 8.0+**。

## 3 从源码构建

需要 Flutter 3.47+ / Dart 3.13+。

```bash
git clone https://github.com/<your-account>/PageReader.git
cd PageReader
flutter pub get

# Windows
flutter build windows --release

# Android
flutter build apk --release
```

桌面端构建前需要生成数据库代码（`lib/data/db/app_database.g.dart` 已随仓库提供，改了表结构才需要重跑）：

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

# 项目结构

```
lib/
├── core/
│   ├── domain/        纯 Dart 模型与注入脚本（无 Flutter 依赖）
│   ├── ports/         接口定义：LibraryStore / WebEngine
│   ├── services/      设置存储、主题、图标抓取
│   └── sync/          同步协议、合并、镜像、服务端、客户端、配对设备
├── data/              drift + SQLite 实现（Books / Groups / ProgressEntries / SyncSnapshots）
├── engine/
│   ├── desktop/       CDP 引擎：启动浏览器、注入、采集、恢复
│   └── android/       WebView 引擎：通道、注入、手势
├── features/
│   ├── bookshelf/     书架：网格、分组、搜索、右键/长按菜单
│   ├── reader/        阅读页
│   ├── settings/      设置
│   ├── sync/          同步页（桌面端二维码 / 手机端扫码）
│   └── diagnostics/   诊断面板
└── main.dart          Provider 装配、启动流程
```

分层原则：`core/domain` 不依赖 Flutter，可以用纯 Dart 测试；
`engine` 依赖平台能力但只暴露 `WebEngine` 接口；`features` 只认接口不认实现。

---

# 测试

```bash
flutter test                          # 271 项单元 + 集成测试
dart run tool/verify_all.dart         # 桌面端端到端（真实浏览器）
dart run tool/verify_sync.dart        # 同步服务协议验证
```

`verify_all.dart` 会启动真实浏览器、打开真书、滚动、关窗、重开，
校验进度是否精确恢复。它跑在 `.verify-data/` 沙箱里，**不碰你的真实书架数据**。

---

# 已知限制

| 限制                    | 原因                                                    |
| --------------------- | ----------------------------------------------------- |
| 桌面端依赖 Edge/Chrome     | 用的是外部浏览器 + CDP，不是内嵌内核                                 |
| 部分设备打开书黑屏             | 详见下方                                                  |
| Android 网页不跟随 app 深浅色 | WebView 没有引擎级的媒体查询覆盖 API                              |
| 阅读页无浏览器插件             | 独立 profile 下插件会弹欢迎页；用日常 profile 又拿不到 CDP 端口。取舍是保住进度记录 |

# 关于在部分华为设备上黑屏

+ 华为（Android 10，华为自研 WebView Chromium 83）上打开书是全黑
+ 小米（Android 8.1，Google 官方 WebView Chromium 68）上完全正常

日志显示是 GPU 缓冲区拿不到：

```
Gralloc3: allocator 3.x is not supported
mali_winsys: new_window_surface(...) returns 0x3000
OpenGLRenderer: dequeueBuffer failed, error = -110
```

关 Impeller、给 WebView 设软件层都试过，只能做到"能显示但掉帧 78~99%"，而且同一份 APK 两次结果不一致。这台设备的 WebView 也无法升级（无 GMS、无 Chrome、Fallback 默认关闭、bootloader 锁死）。

结论：不是应用的问题，是那套 WebView + gralloc 组合的兼容性。不做妥协性适配。

---

# 数据存储位置

| 平台 | 位置 |
|---|---|
| Windows | `%APPDATA%\com.pagereader\PageReader\` |
| Android | 应用私有目录 `files/`（需 root 或 `adb backup` 才能取出） |

目录内容：`pagereader.sqlite`（书架与进度）、`settings.json`（主题、同步凭据）、
`browser-profile/`（桌面端的独立浏览器 profile）。

用环境变量 `PAGEREADER_DATA_DIR` 可以重定向数据目录 —— 验收脚本靠它做沙箱隔离。

---

# 许可

MIT
