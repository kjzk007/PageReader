# PageReader 决策台账


## 一、定位

- 产品名 **PageReader**，Flutter 3.47，Android + Windows
- 把网页文档当"书"管理，记住读到哪一段，两台设备同步
- 阅读窗口里没有我们自己的 UI：桌面内嵌 WebView2 窗口，移动用内嵌系统 WebView

**明确不做**：离线阅读、目录解析、自绘阅读器、进度百分比、广告拦截、书签导入、站点级设置、导出/导入体系（只留一个导出按钮）。

---

## 二、引擎

| 端 | 阅读容器 | 进度采集 |
|---|---|---|
| Windows | 内嵌 WebView2（程序进程内） | 注入脚本 + `WebMessageReceived` |
| Android | 内嵌系统 WebView | 注入脚本 + `JavaScriptChannel` |

### 桌面端为什么从「外部浏览器 + CDP」改成「内嵌 WebView2」

原方案启动 Edge/Chrome 的 `--app` 窗口，靠 CDP 连过去。两个绕不过去的问题：

1. **抢 profile**：要用用户的插件和登录态就得用真实 profile，而同一个数据目录只能有一个
   实例持有调试端口。用户开着浏览器 → 拿不到端口 → 记不了进度。
2. **Edge 拒绝在默认目录开调试端口**：日志原文
   `DevTools remote debugging requires a non-default data directory`。
   复制 profile 到别处能开端口，但 Edge 启动时会删掉未注册的插件目录（实测 19 个只剩 3 个）。

改用内嵌 WebView2 后：内核在程序进程内、独立数据目录、插件用 `AddBrowserExtension`
引用原目录、进度由注入脚本主动上报。用户浏览器完全不参与。

### 关键实现约束（踩过的坑，都写在代码注释里）

- **`AreBrowserExtensionsEnabled` 必须显式设为 TRUE** —— 默认 false 时
  `AddBrowserExtension` 返回 `0x80070032`（ERROR_NOT_SUPPORTED），插件一个都加载不上
- **插件必须在 profile 就绪后立刻加载** —— profile 只在第一个 controller 创建时才存在，
  所以要提前把插件列表交给原生侧，等 profile 就绪的瞬间加载，赶在首页渲染完成前
- **C++ 源码里不能有中文注释** —— MSVC 默认按 GBK 解析 UTF-8，中文注释的字节会把
  后续代码吞掉，报出莫名其妙的语法错误
- **不能把 `FlutterDesktopMessengerRef` 强转成 `flutter::BinaryMessenger*`** ——
  前者是 C 不透明句柄，后者是含虚函数的 C++ 类，vtable 是垃圾，首次虚调用就 BEX64 崩溃。
  必须用 `BinaryMessengerImpl` 桥接
- **通道要延迟注册** —— `GetRegistrarForPlugin` 不能在 `OnCreate` 或首帧回调里调，
  会崩。改成 `PostMessage(WM_APP+1)` 在消息循环跑起来后注册
- **关窗口必须先采位置再销毁** —— 内嵌窗口是直接 `DestroyWindow`，页面收不到
  `pagehide`，所以拦截 `WM_CLOSE` → 采位置 → 回调里再销毁，另设 1.2 秒兜底定时器

---

## 三、书与书架

- 一本书 = 输入的路径前缀；scope 重叠时**长前缀优先**
- scope **可编辑**；进度按 URL 存、与 scope 解耦，改 scope 不删任何进度
- 分组单层（`parentId` 预留不用）
- 网格书架、3:4 封面、最近阅读排序（可切手动拖拽）
- 搜索：书名、URL、上次停留页面标题
- 书架显示"这本书正开着"（订阅引擎的 openBooks）
- 删除语义分离：删组只解散（书进未分组），删书连带进度并留墓碑

### 封面

`manifest.icons` 512 → `apple-touch-icon` 180 → `favicon`（≥96px）→ 标题首字 + 色块。
宽高比 0.8–1.25 才算图标；底色取 `theme_color`，其次图标主色；超时 3 秒不阻塞加书。

### 章节号

从标题正则提取「第 N 章」「Chapter N」「N.M」，提不到显示原标题。

---

## 四、进度模型

- 主键 `(bookId, url)`，一页一条；`url` 去 fragment 归一化
- 另存 `pageHash`：恢复时先跳 `#section`，再用锚点微调
- 归一化：去 fragment、去 `utm_*`/`ref`/`from`/`spm`、query 排序、尾斜杠归一、大小写保留
- **停留 ≥ 5 秒才写入**；本机单调保护 `updatedAt = max(now, 该书最新 + 1s)`
- 锚点三级降级：`cssPath`（本端专用）→ `textFingerprint` + 上下文 → `docRatio`
- **`inChrome` 判断页框必须用「当前遍历到的层级」而不是原始元素** ——
  `el.closest('main')` 在「侧栏嵌在 main 里」的站点（如 hello-algo）会永远找到 main，
  把所有导航判断否掉，锚点记到目录项上，表现是「章节能定位、章节内位置丢失」
- **跳过空文本元素** —— 空 `<p>` 是分隔符或后填容器，选它会得到
  `textFingerprint=""` 的锚点，只剩比例能兜底
- **恢复完成后要打标记** —— 否则页面自身滚动（图片懒加载撑高）会覆盖恢复好的位置
- 滚动容器探测：向上找 `overflow-y: auto/scroll` 且可滚的祖先，失败退回 `window`
- 锚点连续失败 3 次标记失效；页面结构变化后重采
- **跨端同步时跳过 `cssPath`**，只用文本指纹 + 比例
- scope 外页面不记

---

## 五、插件

- 探查：扫 `%LOCALAPPDATA%` 下 Edge / Chrome / Brave 每个 profile 的每个版本目录。
  版本目录按**数字分段比较**（`1.10 > 1.9`），不能直接用字符串比较 ——
  `"1.10.0_0" < "1.9.0_0"` 会让插件升级后仍加载旧版
- **首次打开书前主动问一次**要让哪些插件在阅读时生效（默认全选）。
  不问的话新用户装完直接开书，插件一个都不加载，而设置里那个区块他未必会注意到
- 设置里改勾选**立刻生效**，不重启：调 `reloadExtensions` 重新加载并刷新已开窗口
- 插件文件**不复制**，引用原目录；插件数据存 WebView2 自己的 user data 目录，与浏览器隔离
- **不备份插件目录**。19 个插件约 600 MB，为"防插件被删"占这么多空间不划算；
  重装插件比找回备份更常见

---

## 六、桌面生命周期

- 关书架询问：全部关闭 / 只关应用；两者都先 flush
- flush 显示遮罩与进度，**超过 3 秒可强制退出**
- 单窗关闭：`WM_CLOSE` → 采位置 → `WM_DESTROY`，书架 3 秒轮询摘掉"阅读中"
- 关窗口期间不能重开同一本：`Session.closing` 标记 + Dart 侧 `_closingBooks` 等待
- 打开失败要报错，不静默黑屏

---

## 七、移动端交互

- **返回键 / 边缘手势 = 回书架**，不消费网页历史
- **双指同向横滑 = 页内前进/后退**，首次提示一次；导航后给 2 秒"撤销"
- WebView 实例保留最近 2 本；被系统回收后横滑退化为一页 URL 直载
- 缩放：`useWideViewPort` + `loadWithOverviewMode`，最小 = 屏宽 ÷ 布局宽度
- 不做捏合关闭；不给"请求桌面版"
- 转屏：manifest 声明 `configChanges` 自行处理，转屏后重新定位锚点

### WebView 边界行为

`target=_blank` → 系统浏览器；PDF / 下载 / `mailto:` / `tel:` → 系统；scope 外页面不记。

---

## 八、同步

- 触发：手动；配对：桌面显示二维码 + `IP:端口` + 6 位码（相机权限被拒可手输）
- 内网 HTTP；快照格式 = 全量 JSON
- 冲突：**系统时间最后写入优先**（不做逻辑时钟、不做冲突弹窗）
- 墓碑保留，不做清理
- **同步前必须 flush 所有打开的书**
- 首次配对真合并（按时间取新、墓碑优先、分组按 ID 对齐），完成后给摘要

---

## 九、工程

- 分层：`core/domain`（纯 Dart）、`core/ports`（接口）、`core/services`（ProgressRecorder / ShelfService / SyncService / SettingsService）、`data`（drift + 实现）、`features`（UI）
- 状态管理：**Riverpod**
- 存储：drift + SQLite，WAL；`(bookId, url)` 建唯一索引
- 启动时跑一次 `integrity_check`，失败则备份重命名并新建空库，不做自动修复
- 诊断面板（简版）：内核状态、窗口数、最近落库时间
- 日志：单个本地文件，不轮转，不外传
- 测试：283 项单元 + 集成测试；锚点靠 `verify_all.dart` 端到端跑
- 数据：库文件 + 一个"导出 JSON"按钮（只导出，不导入）

### 构建注意

- **`flutter build windows` 报成功但可能没重新链接 exe** —— 改了 C++ 之后要
  `Remove-Item build -Recurse -Force` 再构建，否则跑的还是旧 exe
- 桌面构建依赖 `windows/webview2/`（SDK 已随仓库提供，不用额外下载）

---

## 十、仍待定（不阻塞）

- 清空数据是否连带 WebView2 数据目录（默认只清库）
- 书架卡片的具体尺寸与每行数量
