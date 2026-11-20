# 深色注入引擎的生成方式

`assets/dark/engine.js` 不是手写的，由这里的脚本拼装出来：

```
assets/dark/skeleton.js   ← 手写：遍历、调度、跳过规则、防闪白占位
        +
提取出的算法函数/常量       ← 从现成的深色实现里按函数名精确切出来
        ↓
assets/dark/engine.js     ← 产物，应用运行时加载的就是它
```

## 为什么这样做

颜色计算（HSL 转换、亮度映射、极点插值、CSS 变量注册）是很成熟的技术积累，
自己重写只会得到一个更差的结果。这里做的是**提取算法、复用自己的引擎骨架**：

- 算法：保持原样，不改写，保证算色准确
- 骨架：完全自己写，只有 dynamic 一档，没有 filter/static，没有站点规则
- 不含任何商业化、导流、消息通信、站点白名单

## 目录里的脚本

| 脚本 | 作用 |
|---|---|
| `_names.json` | 要提取的函数/对象/变量名清单 |
| `_extract.js` | 按名字切函数（含参数解构、正则字面量的正确配平） |
| `_extract_vars.js` | 切顶层 const/let/var（缓存、颜色表、正则等） |
| `_scan_missing.js` | 扫描算法体里引用、但还没提取的顶层声明 |
| `_merge.js` | 按原始行号合并，输出中间体并做依赖检查 |
| `_build_engine.js` | 把算法体注入 skeleton.js 的占位处，产出 engine.js |

## 重新生成的步骤

```powershell
cd D:\PageReader
$src = '<解包目录>\inject\index.js'

# 1. 提取函数
node tool/dark_engine/_extract.js $src tool/dark_engine/_names.json _extract.json

# 2. 提取顶层变量（清单会随版本变化，先用 _scan_missing 找缺的）
node tool/dark_engine/_extract_vars.js $src _missing2.json _extract_vars.json

# 3. 合并 + 依赖检查（会打印仍缺的声明）
$env:DR_SRC = $src
node tool/dark_engine/_merge.js

# 4. 拼装
node tool/dark_engine/_build_engine.js
```

第 3 步打印"仍缺的源文件声明"时，把缺的名字补进 `_missing2.json` 再跑第 2 步，
直到只剩参数名之类的误报（`theme`、`forEach`）。

## 排查经验

提取器踩过的坑，改脚本时别再踩：

1. **参数解构**：`function f({a, b}) {` 里的 `{` 会被当成函数体开始。
   解法：先配平圆括号跳过参数列表，再找函数体的花括号。
2. **正则字面量**：`/^\/\//` 里的 `\/\/` 会被当成行注释，导致后面的 `{` 漏计。
   解法：识别正则开始（看前一个有效字符），扫到未转义的 `/` 结束。
3. **模板字符串**：反引号内的 `${...}` 整体按字符串处理，内部括号不计数。
4. **无初始值的声明**：`let x;` 没有 `=`，正则不能只匹配 `=` 形式。
5. **变量顺序**：合并时必须按原始行号排序，否则变量初始化会用到后面才定义的东西。

## 引擎骨架的取舍

- **只做 dynamic**：不做 filter 反色（蓝色会变橙），不做静态主题（要站点配合）
- **代码块一起算色**：站点常给 `pre/code` 设白底，而父元素文字会被改浅 ——
  白底浅字直接看不见。让代码块参与算色是唯一稳妥的做法，
  代价是语法高亮的色值会整体调亮
- **公式与媒体跳过**：`.katex`/`.MathJax`/`svg`/`img` 不动，改了就是毁内容
- **占位先于算色**：`html,body{background-color:X}` 在 `document_start` 就注入，
  配合 C++ 侧的 `DefaultBackgroundColor`，翻页不闪白