# PageReader

把网页文档当书管理，记住读到哪一段。

很多技术文档只有网页版，没有 EPUB、没有阅读器。用浏览器读，关掉就忘了读到哪；
用稍后读工具，它管的是"读没读"，不管"读到第几段"。

PageReader 解决这一件事：**给网页文档一个书架，精确记住滚到哪一段**。
Windows 和 Android 两端数据互通，换设备接着读。

---

## 它做什么

**书架**　把文档站加进来，抓站点的图标和主题色做成封面。支持分组、搜索、按最近阅读排序。

**精确进度**　不是"读到 47%"，而是记住具体那一段。页面滚到哪里，关掉（甚至直接杀进程）
再打开，回到原处。多级降级：CSS 路径 → 文本指纹 → 文档比例，前一级失效就退到下一级。

**跨设备同步**　同一局域网内直连，数据不经任何服务器。扫码配对一次，之后书架、分组、
阅读进度双向同步，两端状态一致。

**事件驱动上报**　不是定时轮询。页面滚动（800ms 防抖）、`pushState`、`popstate`、
`hashchange`、`pagehide`、`beforeunload`、切到后台，都会立刻上报一次位置。

---

## 技术选择

### 桌面端：外部浏览器 + CDP

不用内嵌 WebView，而是启动 Edge/Chrome 的 `--app` 窗口（去掉地址栏的独立窗口），
通过 DevTools Protocol 注入脚本、读取位置、恢复锚点。

为什么这么选：Chromium 的内核由浏览器自己更新，不需要应用跟着升级；
`--app` 窗口的观感和原生应用一致；CDP 提供的能力比 WebView API 完整得多
（比如 `Page.addScriptToEvaluateOnNewDocument` 能在文档解析前注入，
这是移动端 WebView 拿不到的时机）。

代价：依赖用户机器上有 Edge 或 Chrome，并且用独立 profile 启动
（这样才能拿到调试端口、同时不干扰用户日常浏览）。

### Android 端：webview_flutter + 页面内脚本

系统 WebView，通过 `JavaScriptChannel` 双向通信。注入脚本在
`onPageStarted` / `onPageFinished` 各跑一次。

手势检测必须在页面内做：`WebViewWidget` 是平台视图，触摸事件由原生消费，
不进 Flutter 的 `PointerRouter`，外层 `GestureDetector` 一个事件都收不到。
所以双指横滑返回是在页面里监听 `touchstart/touchmove/touchend` 实现的。

### 同步：局域网直连 + 二维码配对

桌面端起一个 HTTP 服务（固定端口 47321），手机连过来。二维码里是
`pagereader://pair?host=&port=&code=`，扫一次换长期 token，token 落盘。

冲突策略：**按操作时间取最新**。逐项比较 `updatedAt`，谁动得更晚用谁的状态。
删除也是动作 —— 删得晚的那端赢。两端最终完全一致。

"对端把书删了"和"对端从来没有这本书"在数据上一样，所以本地维护一份
**同步快照**（`sync_snapshots` 表）：快照里有、现在没有 = 被删了；
快照里也没有 = 上次同步后才加的，保留。

---

## 快速开始

### 直接用（Windows 便携版）

1. 下载 Release 里的 `PageReader-portable-*.zip`
2. 解压到任意目录，双击 `pagereader.exe`
3. 数据存在 `%APPDATA%\com.pagereader\PageReader\`，删掉程序目录不影响数据

需要机器上有 Microsoft Edge 或 Google Chrome。

### 直接用（Android）

下载 Release 里的 `PageReader-android-*.apk` 安装。要求 **Android 8.0+**。

### 从源码构建

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

桌面端构建前需要生成数据库代码（`lib/data/db/app_database.g.dart` 已随仓库提供，
改了表结构才需要重跑）：

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## 项目结构

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

## 测试

```bash
flutter test                          # 271 项单元 + 集成测试
dart run tool/verify_all.dart         # 桌面端端到端（真实浏览器）
dart run tool/verify_sync.dart        # 同步服务协议验证
```

`verify_all.dart` 会启动真实浏览器、打开真书、滚动、关窗、重开，
校验进度是否精确恢复。它跑在 `.verify-data/` 沙箱里，
**不碰你的真实书架数据**。

---

## 已知限制

| 限制 | 原因 |
|---|---|
| 桌面端依赖 Edge/Chrome | 用的是外部浏览器 + CDP，不是内嵌内核 |
| 部分设备打开书黑屏 | 详见下方 |
| Android 网页不跟随 app 深浅色 | WebView 没有引擎级的媒体查询覆盖 API |
| 阅读页无浏览器插件 | 独立 profile 下插件会弹欢迎页；用日常 profile 又拿不到 CDP 端口。取舍是保住进度记录 |

### 关于在部分华为设备上黑屏

荣耀 KRJ-W09（Android 10，华为自研 WebView Chromium 83）上打开书是全黑。
同样的 APK 在小米 MI PAD 4 PLUS（Android 8.1，Google 官方 WebView Chromium 68）
上完全正常 —— 系统更老、内核更旧的那台反而跑得起来。

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

## 数据在哪

| 平台 | 位置 |
|---|---|
| Windows | `%APPDATA%\com.pagereader\PageReader\` |
| Android | 应用私有目录 `files/`（需 root 或 `adb backup` 才能取出） |

目录内容：`pagereader.sqlite`（书架与进度）、`settings.json`（主题、同步凭据）、
`browser-profile/`（桌面端的独立浏览器 profile）。

用环境变量 `PAGEREADER_DATA_DIR` 可以重定向数据目录 —— 验收脚本靠它做沙箱隔离。

---

## 开发说明

`DECISIONS.md` 是决策台账，记录"为什么这样选"，以及在哪些方案上碰过壁。
`TODO.md` 记录待办、已知取舍、以及已修问题的根因。

改代码前建议先看这两份 —— 很多看起来"可以优化"的地方，其实是被具体约束逼出来的。

---

## 许可

MIT
