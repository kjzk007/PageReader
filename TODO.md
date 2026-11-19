# 待办与待优化

> 已知但暂未处理的问题。修掉的划掉并注明日期，不要直接删。

## 待优化

| # | 问题 | 现象 | 方向 |
|---|---|---|---|
| 1 | 打开书籍要等 2~5 秒 | 点击后要等浏览器冷启动 | 已加"正在打开…"提示缓解；进一步可做进程预热 |
| 2 | 进度偶发延迟落库 | 滚动后上报链路有 800ms 防抖 + 写库延迟 | 已接受。验收脚本改为轮询读取，不再误判 |

## 已知取舍（不是 bug）

| # | 现象 | 为什么这样 |
|---|---|---|
| 3 | 不支持深色主题的站点仍是浅色 | 见下方「Android 端深色跟随：做不到」 |
| 4 | **Android 端网页不跟随 app 的深浅色设置** | 见下方「Android 端深色跟随：做不到」 |
| 5 | 阅读窗口里没有浏览器插件 | 见下方「插件功能：已放弃」 |

## Android 端深色跟随：做不到（2026-11-19）

结论：**不做了**。这是 WebView 引擎级的限制，不是代码问题。

桌面端能跟随，是因为 CDP 有 `Emulation.setEmulatedMedia` —— 它骗的是**引擎本身**，
引擎随后按 dark 求值 CSS 媒体查询。Android WebView 没有对应 API。

| 方案 | 结果 | 卡在哪 |
|---|---|---|
| 覆盖 Activity 的 uiMode（`applyOverrideConfiguration`） | ✗ 崩溃 | 必须在任何 `getResources()` 之前调用，而 Flutter 引擎在 Activity 早期就访问了 resources |
| `WebSettingsCompat.setAlgorithmicDarkeningAllowed` | ✗ 无效 | 这台华为设备的 `HwForceDarkModeConfig` 按白名单覆盖了标准 API（返回 true 但无效果） |
| JS 覆写 `matchMedia` | ✗ 无效 | MDN 的深色靠 CSS `@media (prefers-color-scheme: dark)`，由引擎在样式计算时求值，JS 改不了 |
| `WebViewCompat.addDocumentStartJavaScript` + 覆写 matchMedia | ✗ 无效 | 已实现并实测：脚本确实在文档开始前执行（`window.__prDocStartPatched === true`），`matchMedia('(prefers-color-scheme: dark)').matches === true`，但页面背景仍是 `rgb(255,255,255)`。证明引擎不走 JS 那条路 |

对比实测（同一站点 MDN）：

| 平台 | 机制 | data-theme | html 背景 |
|---|---|---|---|
| 桌面 Edge | `Emulation.setEmulatedMedia`（引擎级） | `light dark` | `rgb(24,25,27)` ✓ |
| Android WebView | JS 覆写 matchMedia（脚本级） | `light dark` | `rgb(255,255,255)` ✗ |

唯一剩下的可能是"注入 CSS 改写站点的 @media 规则"，但要处理跨域样式表、
动态插入样式、@media 嵌套，且不适用所有站点。投入产出不成比例，放弃。

保留的部分：app 自身 UI（书架、设置、阅读页外壳）的深浅色正常跟随。
`androidx.webkit` 依赖与 MainActivity 的注入通道保留着 —— 如果将来 WebView
提供引擎级 API，接上即可。

## 插件功能：已放弃（2026-11-19）

结论：**不做**。三条路都试过，没有一条能同时满足"插件可用 + 进度正常"。

| 方案 | 插件 | 进度 | 卡在哪 |
|---|---|---|---|
| 独立 profile + `--load-extension` | 能跑 | 正常 | 插件认为自己「首次安装」，每次弹欢迎页。要消除得往 `Secure Preferences` 写 30+ 字段的安装记录，而 Edge 启动时会重写该文件，写入被丢弃（实测两次） |
| 直接使用用户的日常 profile | 原生可用 | **完全失效** | Edge 对指向真实 `User Data` 的 `--user-data-dir` 不写 `DevToolsActivePort`（实测等 30 秒没有）。这是安全策略：防止已登录数据被自动化工具读取 |
| 自写 Edge 扩展做进度采集 | 原生可用 | 可做 | 需用户额外安装并维护扩展，工作量远超收益 |

判断依据：进度记录是这个产品的根本，插件是附加能力。不能两全时保住进度。

已删除：`extension_probe.dart`、`extension_migrator.dart`、`login_importer.dart`、
对应 16 项测试、`CdpEngine.extensionPaths` 与两处 `--load-extension`、
设置页「浏览器插件」区块、`settings.dart` 的 `ExtensionSettings`。

## 华为平板上黑屏：设备问题，不是 bug（2026-11-19）

荣耀 KRJ-W09（Android 10）上整个应用黑屏 —— 连书架（纯 Flutter 界面）
都渲染不出来。**换一台更老的小米平板却完全正常**，所以问题不在应用。

| 设备 | 系统 | WebView | 结果 |
|---|---|---|---|
| 荣耀 KRJ-W09 | Android 10 | 华为自研 `com.huawei.webview` Chromium 83 | 黑屏 |
| 小米 MI PAD 4 PLUS | Android 8.1 | Google 官方 `com.google.android.webview` Chromium 68 | 完全正常 |

小米那台的实测数据（作为"正常"的基准）：

- 书架、阅读页、正文/目录/代码块 → 全部正常渲染
- 滚动 915 帧，掉帧 5.25%，中位 6ms
- 长按菜单 → 正常
- 进度记录 → 正常（书架显示「1 分钟前 · 猜数字游戏」）
- 同步 → 正常

华为那台的日志：

```
Gralloc3: allocator 3.x is not supported
mali_winsys: new_window_surface(...) returns 0x3000
OpenGLRenderer: dequeueBuffer failed, error = -110
BufferQueueProducer: [SurfaceTexture-0-...] disconnect: not connected
```

试过但**都无效**的方案（别再重走）：

| 方案 | 结果 |
|---|---|
| 关 Impeller（`EnableImpeller=false`，改走 Skia）| 书架能显示了，阅读页仍黑 |
| WebView 设软件层（`setLayerType(LAYER_TYPE_SOFTWARE)`）| 时而能显示时而黑，且掉帧 78~99% |
| 两者叠加 | 仍不稳定，同一份 APK 两次结果不同 |
| 升级 WebView | 升不了：无 GMS、无 Chrome、Fallback 默认关闭（`Fallback logic enabled: false`）、`cmd webviewupdate set-webview-implementation` 直接失败、华为市场里查不到该组件 |
| root | 不可能：麒麟 985，`flash.locked=1`、`verifiedbootstate=green`、`unlock_supported` 为空。华为不提供解锁码 |

结论：**这台设备上不用内嵌 WebView 才可能可用**。已放弃适配，不做这个妥协。

## 回收站：不做（2026-11-19）

考虑过在设置里加「回收站」：列出已删除的书，长按/右键可恢复书及其进度。

**决定不做，保持功能精简。**

原因：要支持"连进度一起恢复"，就必须把进度也改成软删（打标记而不 DELETE）。
代价是数据库持续增长，还得再加「彻底删除」「清空回收站」等一整套管理入口。
为了一个低频的误删场景引入这些复杂度，不划算。

当前删除行为（保持不变）：

| 对象 | 处理 | 为什么 |
|---|---|---|
| 书 | 软删（写 `deletedAt` 墓碑） | 墓碑要参与同步 —— 否则一端的删除传不到另一端，删了又回来 |
| 进度 | 硬删（`DELETE`） | 书都没了，进度留着只会被同步到处传、让库变大 |

误删的后果：书仍在数据库里（墓碑），但界面上看不到，也没有入口恢复。

## 待办（功能缺口）

| # | 功能 | 说明 |
|---|---|---|
| 6 | 内网同步的真机验证 | 代码与端到端测试已完成（配对码、双向合并、幂等），但尚未在两台真实设备间跑过一次 |
| 7 | 书签导入 | 已定不做 |

## 已修

- 2026-11-18 `setState` 回调返回 Future：`_reload` 与分组点击的箭头写法
- 2026-11-18 GUI 模式 `targetId` 字段名写错，导致永远 attach 失败
- 2026-11-18 CDP 错误响应被吞，失败时只看到类型错误
- 2026-11-18 过期端口文件未清理，导致 `errno 1225` 连接被拒
- 2026-11-19 对话框崩溃：`TextEditingController` 在退出动画期间被 dispose，
  导致新建/改名分组、改书名全部报 build scope 断言
- 2026-11-19 右键菜单：字号不一致（"从书架移除"缺 `fontSize`）、文字被截断
  （`RelativeRect` 把 `dx` 同时当 left/right）
- 2026-11-19 菜单固定贴右：`RelativeRect.fromLTRB(dx, dy, 0, 0)` 让 Flutter
  理解成"可延伸到屏幕边缘"
- 2026-11-19 浏览器检测盲区：只硬编码 4 个路径，用户级安装和便携版全漏。
  改为注册表 → 环境变量推导 → `where` 三级检测
- 2026-11-19 验收脚本污染用户数据：直接删 `%APPDATA%` 下的库。
  改为 `PAGEREADER_DATA_DIR` 沙箱隔离
- 2026-11-19 `inChrome` 误判布局容器：MDN 正文容器叫 `layout__header`，
  被 `/header/` 命中导致整本书不记进度。BEM 命名只查 block 部分
- 2026-11-19 注入脚本缺 `anchorScript`：桌面端只执行了 `positionReportScript`，
  `window.__pr` 不存在，表现为"有上报但锚点永远 null"
- 2026-11-19 scroll 只监听 window：用 `scrollTop` 赋值时不冒泡，
  验收时滚动完全没反应。改为同时监听 `document`
- 2026-11-19 平台视图吞掉 Flutter 手势：WebView 外层包 `Listener` 收不到事件，
  双指横滑必须在页面内用 JS 检测
- 2026-11-19 验收脚本类型错误：轮询改造时把 `List<String>?` 写成 `Map`
- 2026-11-19 Chromium 单实例锁残留：上次异常退出留下 `SingletonLock` 等文件，
  新进程误以为已有实例、启动即退出。启动前清理这四个文件
- 2026-11-19 构建产物陈旧：`flutter build windows` 报成功但 exe 未重新链接，
  导致改的代码没生效、反复验证"修好了"其实是旧程序。
  验收脚本已加第 0 步：比对 exe 与源码时间戳，过期直接 FAIL
