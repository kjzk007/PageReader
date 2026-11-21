# 更新计划

已知问题与待办。**这些问题不影响当前版本正常使用**，等积累到一定程度一起修、一起发版，
避免为单个小改动反复构建发布。

格式约定：每条写清「现象 / 根因 / 修法 / 影响面」，方便将来直接照做，不用重新排查。

---

## 一、待修

（暂无）

上一版的三项已全部修完，见「二、已完成」。

---

## 二、已完成

### 插件版本目录按数字分段比较（2026-11-21）

**位置**：`lib/engine/desktop/extension_probe.dart`

**原问题**：字符串比较导致 `1.10.0_0` 被判成小于 `1.9.0_0`，
插件升级后如果旧版本目录还残留会继续加载旧版。

**修法**：新增 `_compareVersion`，按 `.` `_` 切段，能转 int 的按数值比，
转不动的退回字符串比。

---

### 删掉插件备份目录的死代码（2026-11-21）

**原问题**：`extension_probe.dart` 会读
`%APPDATA%\com.pagereader\PageReader\extensions-backup\`，
但全项目没有任何代码写入。README 和 DECISIONS 里「会备份插件」的描述不存在。

**修法**：删掉读取逻辑，文档改为「不备份插件目录」并说明理由
（19 个插件约 600 MB，重装插件比找回备份更常见）。

---

### 新装插件主动提示（2026-11-21）

**原问题**：`asked` 标记写过一次就不再问，用户后来装的插件不会被告知。

**修法**：
- `ExtensionSettings` 新增 `seenIds`（上次见过的插件集合）+ `newIdsAgainst()`
- `ExtensionSection._load` 在列表**真正渲染之后**才 `markSeen` ——
  启动时标记等于替用户把没看到的新插件标成已读
- 书架工具栏的设置按钮换成 `_SettingsButton`，有新插件时右上角点红点

---

### 书籍封面蓝点已删除（2026-11-21）

**位置**：`bookshelf_page.dart` 的 `_BookCard`

右下角那个表示「有阅读进度」的 6×6 蓝点已移除。它本来就是冗余信息 ——
书名下面那行小字已经写了读到哪。

---

### 引擎死代码清理（2026-11-21）

**位置**：`assets/dark/engine.js`（构建产物）

**背景**：从成熟实现里提取算法时把整片相关函数都带上了，其中 26 个
（`parseGradient`、`getRGBValues`、`createOptimizedTreeObserver`、
`throttle` 等）服务的是 filter / static 模式和早期 DOM 工具，
我们的 dynamic-only 引擎用不到。

**修法**：`tool/dark_engine/_drop.json` 列出可安全删除的名单
（每项都验证过「全引擎只出现一次且不被保留函数引用」），
`_merge.js` 构建时排除。引擎从 **88.3 KB / 2783 行** 降到 **71.8 KB / 2292 行**。

**注意**：新增死代码时可以用 `_find_unused.js` 的思路重新扫描，
但**必须人工核对**后再加进 `_drop.json` —— 有些函数看似没用，
其实是运行时回调入口。

---

### 主题预设系统（2026-11-21）

**能力**：不依赖任何浏览器插件，程序自己把页面配色改成用户预设的样子。

| 维度 | 说明 |
|---|---|
| 背景色 | 页面主底色（html/body） |
| 次级背景 | 卡片、表格头、侧栏、引用块 |
| 文字色 | 正文 |
| 次级文字 | 说明、页脚、表头 |
| 链接色 | 正文里的链接（按钮类排除） |
| 选中色 | `::selection` |
| 文字亮度 | 100 为基准，向白/向黑插值（最多 30% 余量） |
| 文字对比度 | 以页面底色为基准缩放差值 |
| 图片亮度 | `filter: brightness()`，作用 img/video/picture |
| 代码块 | **背景跟随主题，文字和语法高亮完全不动** |

**绑定方式**：书架右键 → 主题设置 → 选预设或「默认」（不注入）。
存 `books.preset_id`，数据库 v2 → v3 加列，老书全部 null。

**踩过的坑**（都写在代码注释里）：
1. `secondaryBackgroundColor` / `secondaryTextColor` 不能给空串 ——
   极点插值会算出无意义的高饱和色，实测 body 背景变成 `rgb(0,255,255)` 青色
2. 占位样式给 html/body 刷了底色，算色**不能再碰这两层的背景** ——
   否则把用户选的色当输入再算一遍，蓝色被映射成黑色
3. 亮度必须用插值不能用乘法 —— 乘法会把中亮文字直接顶到 255，整页纯白
4. 调整必须放在算色**之后** —— 算法假设输入是站点原本的浅色配色
5. `flush()` 的 `flushing` 标志必须 try/finally 复位，否则首个异常就让队列永久卡死
6. `body.querySelectorAll('*')` 不含 body 本身，会漏掉根节点
7. 提取脚本要处理参数解构的 `{}` 和正则字面量里的 `\/`，否则函数会被切坏

**引擎重建**：`node tool/dark_engine/build_all.js <解包目录>/inject/index.js`
（详见 `tool/dark_engine/README.md`）

---

### 删除外部浏览器依赖（2026-11-21）

内嵌 WebView2 之后不再需要启动外部浏览器，以下全部删除：

| 文件/代码 | 原因 |
|---|---|
| `engine/desktop/cdp_engine.dart` | 驱动外部 Edge/Chrome |
| `engine/desktop/browser_locator.dart` | 只给 CdpEngine 找 exe |
| `features/diagnostics/diagnostics_page.dart` | 显示端口、pageCount，WebView2 下无意义 |
| 「没有找到浏览器」弹窗 | 内嵌内核没有外部依赖 |
| `isDegraded`「不记进度」徽章 | 只对 CDP 降级有意义 |
| `_showLaunchHelp`「先退出 Edge」 | 同上 |
| `adoptProvider` 孤儿窗口认领 | 外部浏览器才需要 |
| `progress_recorder` 的 `onBookOpened` 钩子 | 内嵌内核的页面自己会上报 |

`BrowserProfile` 新增 `resolveAny()`：不需要知道 exe 路径，
按优先级遍历 Edge/Chrome/Brave 的 profile 目录，把 Cookie 和登录态搬过来。

---

## 三、已验证

### 浅色主题下的阅读窗口（通过）

主题跟随已经实现（`SetDarkMode` → 深色标题栏 + 主题背景刷）。
深色与浅色都已实机确认。

### 防闪白（通过）

三层：
1. C++ `put_DefaultBackgroundColor`（预设底色，不注入时为不透明白）
2. `document_start` 注入 `html,body{background-color:X}` 占位
3. 算色完成后覆盖占位

---

## 四、已知限制（不做）

### Android 主题预设已接入（2026-11-21）

**现状**：六个颜色维度在 Android 上也生效，和桌面端跑同一份引擎。

**和桌面端的唯一差别是闪不闪**：桌面端用 `AddScriptToExecuteOnDocumentCreated`
在 `document_start` 注入（第一帧之前）；Android 只能等 `onPageFinished`
之后 `runJavaScript`，所以打开书时会先看到原色闪一下。

实测两台设备都不支持 `DOCUMENT_START_SCRIPT`：
- MI PAD 4 PLUS：WebView 68.0.3440.91
- 荣耀 KRJ-W09：`com.huawei.webview` 11.1.5.315（华为自家内核）

所以闪这一下是**当前设备的硬限制**，不是实现没做好。将来设备升级
WebView 支持 document-start 后，改注入时机即可消除。

**踩过的坑（重要）**：

1. **引擎里的 class 字段在 WebView 68 上解析失败**
   - 现象：注入成功、不抛错，但脚本一行都不执行 —— 连第一行的
     `window.__PR_DARK_PRESET` 都没赋值。`evaluateJavascript` 不上报
     解析错误，所以看起来像「注入成功但没效果」。
   - 解决：构建时用 esbuild 转译到 es2017，产出 `engine.legacy.js`。
     运行时按 WebView 主版本挑一个（< 85 用降级版）。
   - 教训：**不要手写降级规则**。早前写的 `lower_syntax.js` 只处理了
     `?.` / `??` / `replaceAll`，漏了 class 字段 —— 正是那次踩的坑。

2. **`requestAnimationFrame` 在 WebView 里可能不触发**
   - 现象：SPA 站点只改了初始几个元素，正文全是原色，而队列里明明
     堆着 200 多个待处理节点。
   - 原因：Flutter PlatformView 内的 WebView，页面不可见或合成原因
     会让 rAF 不执行。
   - 解决：批量调度改用 `setTimeout`。

3. **注入时机不确定，需要重试**
   - 现象：同一份代码同一台机器，约 1/5 概率首次不生效。
   - 原因：`onPageFinished` 时 `readyState` 在 WebView 68 上有时仍报
     `loading`，引擎的启动分支等不到 `DOMContentLoaded` 就永远不跑。
   - 解决：骨架里加 300ms 兜底（还没标记就直接 `start()`），
     Dart 侧加 6 次重试 + 引擎暴露 `__prForceWalk` 供宿主主动补算。

4. **分块注入是个弯路**
   - 早前误判「72KB 单次注入会静默失败」，于是改成分块 + `new Function`，
     结果引入跨轮缓冲污染（长度从 58k 涨到 86k，报 SyntaxError 位置乱跳）。
   - 真相：那个「静默失败」是第 1 条的 class 字段语法错误造成的。
   - 现在：**优先单次整段注入**，失败才用带唯一 token 缓冲的分块兜底。

### 次级背景需要用户自己配成同色系

如果用户把背景设成蓝色、次级背景留默认深灰，页面上仍会有色块差异。
这是**用户选择的问题**，软件不替他推导。

### 插件 UI 在阅读窗口里打不开

WebView2 拒绝导航到 `chrome-extension://`（会回退到空白错误页）。
需要 popup 才能配置的插件（如开关类）在阅读窗口里用不了。
能通过 `chrome.storage` 配置的插件理论上可以用 CDP 控制，但目前没做。

---

## 五、发版约定

- 攒够一批改动再发版，不为单个小修反复构建
- 桌面端改了 C++ 之后要 `Remove-Item build -Recurse -Force` 再构建，
  否则 `flutter build windows` 报成功但不会重新链接 exe
- 构建前需要 VS 工具链检测桩（`vswhere.exe` 的 JSON 替身），
  因为本机 VS 安装注册信息缺失，真实 `vswhere` 返回空
- **构建时程序可能在运行**，robocopy 会卡住等文件解锁。
  用逐文件复制并跳过被占用的方式部署更稳（dll/exe 被占用不影响
  `app.so` 和 `engine.js` 这两个真正承载逻辑的文件）