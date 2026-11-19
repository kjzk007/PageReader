# PageReader 决策台账

> 需求讨论的收口记录。实现与本文冲突时以本文为准；要改先改这里。
> 定位：**个人自用、可开源自部署**。不按商业产品的可用性、并发、观测性标准设计。
> 最后更新：2026-11-18（第 2 版，按"砍掉过度设计"重写）

---

## 一、定位

- 产品名 **PageReader**，Flutter 3.47，Android + Windows
- 把网页文档当"书"管理，记住读到哪一段，两台设备同步
- 阅读窗口里没有我们自己的 UI：桌面用 Edge/Chrome 的 `--app` 窗口，移动用内嵌 WebView

**明确不做**：离线阅读、目录解析、自绘阅读器、进度百分比、浏览器扩展、广告拦截、书签导入、站点级设置、导出/导入体系（只留一个导出按钮）。

---

## 二、引擎

| 端 | 阅读容器 | 进度采集 |
|---|---|---|
| Windows | Edge/Chrome `--app` + 专用 profile + CDP | `frameNavigated` + 注入脚本 |
| Android | 内嵌 WebView | `onUpdateVisitedHistory` + 注入脚本 |

- 所有书共用一个专用 profile；CDP 端口不写死，实际端口写入状态文件
- 端口被占或进程未就绪时串行化启动，不并发 spawn
- **同一本书只允许一个窗口**，再次点击聚焦已有窗口（`Target.activateTarget`）
- 单实例锁：第二个进程把已有窗口激活后退出

---

## 三、书与书架

- 一本书 = 输入的路径前缀；scope 重叠时**长前缀优先**
- scope **可编辑**；进度按 URL 存、与 scope 解耦，改 scope 不删任何进度
- 分组单层（`parentId` 预留不用）
- 网格书架、3:4 封面、最近阅读排序（可切手动拖拽）
- 搜索：书名、URL、上次停留页面标题
- 书架显示"这本书正开着"（订阅 target 列表）
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
- 滚动容器探测：向上找 `overflow-y: auto/scroll` 且可滚的祖先，失败退回 `window`
- 锚点连续失败 3 次标记失效；页面结构变化后重采
- **跨端同步时跳过 `cssPath`**，只用文本指纹 + 比例
- scope 外页面不记

---

## 五、桌面生命周期

- 关书架询问：全部关闭 / 只关应用；两者都先 flush
- flush 显示遮罩与进度，**超过 3 秒可强制退出**
- 下次启动自动接管孤儿窗口，书架提示一行
- 单窗关闭：`targetDestroyed` 立即写最后一次
- CDP 连不上：标"降级模式"，退化为默认浏览器打开

---

## 六、移动端交互

- **返回键 / 边缘手势 = 回书架**，不消费网页历史
- **双指同向横滑 = 页内前进/后退**，首次提示一次；导航后给 2 秒"撤销"
- WebView 实例保留最近 2 本；被系统回收后横滑退化为一页 URL 直载
- 缩放：`useWideViewPort` + `loadWithOverviewMode`，最小 = 屏宽 ÷ 布局宽度
- 不做捏合关闭；不给"请求桌面版"
- 转屏：manifest 声明 `configChanges` 自行处理，转屏后重新定位锚点

### WebView 边界行为

`target=_blank` → 系统浏览器；PDF / 下载 / `mailto:` / `tel:` → 系统；scope 外页面不记。

---

## 七、同步

- 触发：手动；配对：桌面显示二维码 + `IP:端口` + 6 位码（相机权限被拒可手输）
- 内网 HTTP；快照格式 = 全量 JSON
- 冲突：**系统时间最后写入优先**（不做逻辑时钟、不做冲突弹窗）
- 墓碑保留，不做清理
- **同步前必须 flush 所有打开的书**
- 首次配对真合并（按时间取新、墓碑优先、分组按 ID 对齐），完成后给摘要

---

## 八、工程

- 分层：`core/domain`（纯 Dart）、`core/ports`（接口）、`core/services`（ProgressRecorder / ShelfService / SyncService / SettingsService）、`data`（drift + 实现）、`features`（UI）
- 状态管理：**Riverpod**
- 存储：drift + SQLite，WAL；`(bookId, url)` 建唯一索引
- 启动时跑一次 `integrity_check`，失败则备份重命名并新建空库，不做自动修复
- 诊断面板（简版）：端口、target 数、最近落库时间
- 日志：单个本地文件，不轮转，不外传
- 测试：**只写 URL 归一化与合并逻辑的单测**；锚点靠手动试
- 数据：库文件 + 一个"导出 JSON"按钮（只导出，不导入）

---

## 九、仍待定（不阻塞）

- 清空数据是否连带浏览器 profile（默认只清库）
- 首次启动的浏览器检测失败文案
- 书架卡片的具体尺寸与每行数量
