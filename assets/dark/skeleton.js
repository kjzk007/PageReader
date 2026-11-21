/**
 * PageReader 深色注入引擎 —— 骨架部分。
 *
 * 算法部分（颜色解析、亮度映射、极点插值、缓存、CSS 规则遍历）单独生成，
 * 以 `/* @ALGORITHM *\/` 为占位注入到本文件头部。
 *
 * 设计要点：
 *
 * 1. 只做 dynamic 一种模式。不做 filter / static，减少分支。
 * 2. 代码容器、数学公式、媒体元素一律跳过算色 —— 不是选项，是硬规则。
 * 3. 占位样式先于算色生效，避免翻页白闪。
 * 4. 遍历有上限，MutationObserver 有节流，避免长文档卡死。
 */
(function () {
  'use strict';

  /* @ALGORITHM */

  // ===== 预设（由宿主在注入时填入）=====
  var PRESET = window.__PR_DARK_PRESET;
  if (!PRESET || PRESET.enabled !== true) return;

  // mode 1 = 深色方案，0 = 浅色方案。
  // 由预设的底色明暗决定，用户不需要理解这个机制。
  var THEME = {
    mode: PRESET.mode == null ? 1 : PRESET.mode,
    brightness: PRESET.brightness == null ? 100 : PRESET.brightness,
    contrast: PRESET.contrast == null ? 100 : PRESET.contrast,
    grayscale: PRESET.grayscale == null ? 0 : PRESET.grayscale,
    sepia: PRESET.sepia == null ? 0 : PRESET.sepia,
    useFont: !!PRESET.forceFont,
    fontFamily: PRESET.forceFont || 'Segoe UI',
    textStroke: 0,
    // 必须是字符串 'dynamicTheme'，算法里按它分支
    engine: 'dynamicTheme',
    stylesheet: '',
    darkSchemeBackgroundColor:
      PRESET.background || 'rgb(24, 26, 27)',
    darkSchemeTextColor: PRESET.text || 'rgb(232, 230, 227)',
    lightSchemeBackgroundColor: 'rgb(255, 255, 255)',
    lightSchemeTextColor: 'rgb(24, 26, 27)',
    // 极点（pole）计算要读这两个。
    //
    // 不能用空串：算法会把 "" 传进 parseColorWithCache，解析失败后
    // 插值出来的是一个无意义的高饱和色 —— 实测整个 body 背景变成
    // rgb(0,255,255) 青色。给它们一对「次要背景/次要文字」的实色即可，
    // 语义上正好对应站点里的卡片、侧栏这类次级区域。
      secondaryBackgroundColor:
        PRESET.secondaryBackground || PRESET.background || 'rgb(24, 26, 27)',
      secondaryTextColor:
        PRESET.secondaryText || PRESET.text || 'rgb(232, 230, 227)',
    scrollbarColor: '',
    selectionColor: 'auto',
    styleSystemControls: false,
    lightColorScheme: 'Default',
    darkColorScheme: 'Default',
    immediateModify: false,
  };

  // 错误记录必须在这里初始化 —— 放在 note() 附近的话，第一次异常
  // 发生在赋值之前，note 内部 arr.length 会再抛一次，把原始错误吞掉。
  var errors = [];
  window.__prDarkErrors = errors;

  var MAX_ELEMENTS = 6000;
  var BATCH_SIZE = 400;
  var processed = new WeakSet();
  var pending = [];
  var flushing = false;

  // ===== 跳过规则 =====
  //
  // 只跳过"算色会彻底毁掉内容"的元素：媒体、公式渲染器。
  //
  // 代码块（pre/code）**不跳过**。站点常给代码块设白色底，而父元素的
  // 文字色会被我们改成浅色 —— 白底浅字直接看不见。唯一稳妥的做法
  // 是让代码块一起算色：底色变深、文字变浅，语法高亮的彩色 span
  // 仍保留自己的色相（只是整体调亮）。
  // 代价是语法色值会变，这是"可读"与"原色"之间必须做的取舍。
  var SKIP_TAGS = {
    SCRIPT: 1, STYLE: 1, LINK: 1, META: 1, HEAD: 1, TITLE: 1,
    IMG: 1, VIDEO: 1, AUDIO: 1, CANVAS: 1, IFRAME: 1, OBJECT: 1, EMBED: 1,
    SVG: 1, MATH: 1,
    // 代码块不参与算色 —— 文字和语法高亮必须保持站点原样。
    //
    // 语法高亮本身就是配色信息，逐元素改色会把关键字的红、字符串的
    // 绿全洗掉。但**背景**要跟随主题（见 applyUserOverrides 里的规则）：
    // 站点普遍给代码块设白底，留一块白在深色页面上很刺眼。
    PRE: 1, CODE: 1, KBD: 1, SAMP: 1,
  };

  var SKIP_SELECTORS = [
    '.katex', '.MathJax', 'mjx-container', '.arithmatex',
    '.mermaid', '.plantuml',
  ];
  var SKIP_SELECTOR_TEXT = SKIP_SELECTORS.join(',');

  function shouldSkip(el) {
    if (!el || el.nodeType !== 1) return true;
    var tag = el.tagName;
    if (SKIP_TAGS[tag]) return true;
    // 代码/公式容器：自身及后代都跳过
    var parent = el;
    var guard = 0;
    while (parent && parent.nodeType === 1 && guard++ < 8) {
      if (SKIP_TAGS[parent.tagName]) return true;
      if (parent.matches && parent.matches(SKIP_SELECTOR_TEXT)) return true;
      // role 或语义标记
      var role = parent.getAttribute && parent.getAttribute('role');
      if (role === 'code' || role === 'math') return true;
      parent = parent.parentElement;
    }
    return false;
  }

  // ===== 占位：第一帧就是深色 =====
  /// 把用户指定的链接色、选中色、图片亮度写成一张全局样式表。
  ///
  /// 这三项和逐元素算色是两条独立通路：
  ///   - 链接色是「用户明确指定」，优先于算色结果；
  ///   - 选中色只能靠 ::selection 伪元素，算色碰不到；
  ///   - 图片亮度必须用 filter，逐元素改背景没有意义。
  function applyUserOverrides() {
    var rules = [];

    // 链接：只覆盖正文里的链接，放过按钮、导航和卡片，
    // 否则站点精心设计的按钮会一片死蓝。
    var link = PRESET.link;
    if (link) {
      rules.push(
        'a[href]:not([class*="btn"]):not([class*="button"])' +
          ':not([role="button"])' +
          '{color:' + link + ' !important}'
      );
    }

    // 选中文本
    var sel = PRESET.selection;
    if (sel) {
      rules.push('::selection{background-color:' + sel + ' !important}');
      rules.push('::-moz-selection{background-color:' + sel + ' !important}');
    }


    // 代码块：只换背景，文字和语法高亮保持站点原样。
    //
    // 高亮是文档的配色信息（关键字红、字符串绿），逐元素算色会洗掉它；
    // 但背景必须跟随主题 —— 站点给代码块设的白底放在深色页面上很刺眼。
    var codeBg = PRESET.codeBackground;
    if (codeBg) {
      rules.push(
        'pre,code,kbd,samp{background-color:' + codeBg + ' !important}'
      );
    }

    // 图片亮度：深底上原图刺眼，这里统一压暗。
    var ib = PRESET.imageBrightness;
    if (typeof ib === 'number' && ib !== 100) {
      var pct = Math.max(0, ib) + '%';
      rules.push('img,video,picture img{filter:brightness(' + pct + ') !important}');
    }

    if (!rules.length) return;
    var style = document.createElement('style');
    style.id = '__pr_user_overrides';
    style.textContent = rules.join('\n');
    var host = document.head || document.documentElement;
    if (host) host.appendChild(style);
  }

  function applyPlaceholder() {
    var bg = THEME.darkSchemeBackgroundColor;
    var css =
      'html,body{background-color:' + bg + ' !important;' +
      'color-scheme:' + (THEME.mode === 1 ? 'dark' : 'light') + ' !important}';
    var style = document.createElement('style');
    style.id = '__pr_dark_placeholder';
    style.textContent = css;
    var host = document.head || document.documentElement;
    if (host) host.appendChild(style);
  }

  // ===== 元素算色 =====
  /// 按用户设定的亮度/对比度调整**文字色**。
  ///
  /// 只作用文字，不作用背景 —— 背景亮度一旦跟着放大，大面积容器
  /// （main/article 的浅色底）会成片撞到 255，整个页面发白，
  /// 看起来像"渲染坏了"。用户要的也只是"文字亮一点"。
  ///
  /// ── 为什么必须在算色之后做 ──
  ///
  /// 引擎的颜色修改算法里根本没有 brightness / contrast 这两个参数
  /// （它们只在 filter 模式下被 createFilterMatrix 用到），所以这两个
  /// 滑块以前是死参数。
  ///
  /// 但调整必须放在算色**之后**：算法的极点映射假设输入是站点原本的
  /// 浅色配色，先把它压成中灰再喂进去，会被映射成更暗的颜色 ——
  /// 实测 h1 从可读的浅灰变成 rgb(29,29,32)，在深底上直接消失。
  function adjustTextColor(color) {
    var b = THEME.brightness;
    var c = THEME.contrast;
    if (b === 100 && c === 100) return color;

    // 算色函数返回的可能是 rgb 字符串而不是 {r,g,b,a} ——
    // 直接按对象取值会得到 undefined，算出 NaN，写进 style 时
    // 浏览器当成无效值整个丢掉，表现为"算色完全不生效"。
    var rgb = color;
    if (typeof color === 'string') {
      rgb = parseColorWithCache(color);
    }
    if (!rgb || typeof rgb.r !== 'number') return color;

    var r = rgb.r, g = rgb.g, bl = rgb.b;

    // 亮度：向白/向黑插值，而不是按倍数乘。
    //
    // 倍数乘会把接近白的中亮文字直接顶到 255 —— 实测亮度调到 112
    // 之后，整页文字全变纯白，层次全丢，看起来像"渲染坏了"。
    // 插值最多只吃掉 30% 的余量，调大调小都还留得住层次。
    if (b !== 100) {
      var t = (b - 100) / 100; // 负数=压暗，正数=提亮
      var k = Math.min(Math.abs(t), 0.6) * 0.5;
      if (t > 0) {
        r = r + (255 - r) * k;
        g = g + (255 - g) * k;
        bl = bl + (255 - bl) * k;
      } else {
        r = r * (1 - k);
        g = g * (1 - k);
        bl = bl * (1 - k);
      }
    }

    // 对比度：缩放「文字与页面底色」的差值，而不是围绕中灰 128 拉伸。
    //
    // 中灰轴心的做法在深色主题下几乎看不出效果 —— 文字本身已经接近
    // 中亮（rgb(153,158,169)），绕 128 拉伸只挪动十几个色阶。
    // 改成以底色为基准放大/缩小差值，效果直接对得上"文字和背景的
    // 反差"，160 时文字明显更亮，20 时明显更暗。
    if (c !== 100) {
      var base = null;
      try {
        base = parseColorWithCache(THEME.darkSchemeBackgroundColor);
      } catch (e) {}
      if (!base || typeof base.r !== 'number') {
        base = { r: 0, g: 0, b: 0 };
      }
      var ct = (c - 100) / 100;
      var cf = 1 + Math.max(-0.85, Math.min(1.2, ct));
      r = base.r + (r - base.r) * cf;
      g = base.g + (g - base.g) * cf;
      bl = base.b + (bl - base.b) * cf;
    }

    return {
      r: Math.max(0, Math.min(255, r)),
      g: Math.max(0, Math.min(255, g)),
      b: Math.max(0, Math.min(255, bl)),
      a: rgb.a,
    };
  }

  /// 是不是需要套用用户链接色的元素。
  ///
  /// 只排除真正的按钮（class 含 btn/button、role=button），其余链接一律上色。
  /// 不要用「有没有背景色」来判断 —— 实测导航栏链接普遍带底色，
  /// 拿这个当排除条件会把整页链接都放过，用户改了半天没反应。
  function isUserLink(el) {
    if (!PRESET.link) return false;
    if (el.tagName !== 'A') return false;
    if (!el.hasAttribute('href')) return false;
    var cls = (el.className && typeof el.className === 'string')
      ? el.className.toLowerCase()
      : '';
    if (cls.indexOf('btn') >= 0 || cls.indexOf('button') >= 0) return false;
    if (el.getAttribute('role') === 'button') return false;
    return true;
  }

  function toCss(color) {
    if (!color) return null;
    if (typeof color === 'string') return color;
    return rgbToString(color);
  }

  function processElement(el) {
    if (processed.has(el)) return;
    processed.add(el);
    try {
      processElementInner(el);
    } catch (e) {
      note(errors, 'outer:' + (e && e.message));
    }
  }

  function processElementInner(el) {
    if (shouldSkip(el)) return;

    var cs;
    try {
      cs = getComputedStyle(el);
    } catch (e) {
      return;
    }
    if (!cs) return;
    if (cs.display === 'none' || cs.visibility === 'hidden') return;

    // 每一段单独兜住：算法在个别颜色格式上失败，不能让整个遍历停掉。
    //
    // ── html / body 的背景必须跳过 ──
    //
    // 占位样式已经给 html,body 设了主题底色（!important）。如果这里
    // 再按"站点的浅色背景"算一遍，读到的 cs.backgroundColor 其实是
    // 占位刷上去的那层颜色 —— 等于把用户选的底色又当输入算一次，
    // 蓝色会被映射成黑色，页面变成"外面蓝、里面黑"。
    // 这一层的背景完全交给占位，这里只处理它们的文字色。
    var isRootContainer =
      el === document.documentElement || el === document.body;
    try {
      if (!isRootContainer) {
        var bgColor = parseColorWithCache(cs.backgroundColor);
        if (bgColor && bgColor.a > 0.02) {
          var newBg = modifyBackgroundColor(bgColor, THEME);
          var bgCss = toCss(newBg);
          if (bgCss) el.style.setProperty('background-color', bgCss, 'important');
        }
      }
    } catch (e) {
      note(errors, 'bg:' + (e && e.message));
    }

    try {
      // 链接色优先于算色结果。
      //
      // 不能只靠注入一张样式表：算色会给每个元素写内联 style，
      // 而内联的 !important 优先级高于样式表的 !important ——
      // 结果就是链接色被默默盖掉，用户在设置里改半天没反应。
      if (isUserLink(el)) {
        el.style.setProperty('color', PRESET.link, 'important');
      } else {
        var rawFg = parseColorWithCache(cs.color);
        if (rawFg && rawFg.a > 0.02) {
          var newFg = adjustTextColor(modifyForegroundColor(rawFg, THEME));
          var fgCss = toCss(newFg);
          if (fgCss) el.style.setProperty('color', fgCss, 'important');
        }
      }
    } catch (e) {
      note(errors, 'fg:' + (e && e.message));
    }

    try {
      var bc = parseColorWithCache(cs.borderTopColor);
      if (bc && bc.a > 0.02 && parseFloat(cs.borderTopWidth) > 0) {
        var newBc = toCss(modifyBorderColor(bc, THEME));
        if (newBc) el.style.setProperty('border-color', newBc, 'important');
      }
    } catch (e) {
      note(errors, 'bd:' + (e && e.message));
    }
  }

  // 错误只记前若干条，避免刷爆内存
  function note(arr, msg) {
    try {
      if (arr && arr.length < 8 && msg) arr.push(msg);
    } catch (e) {}
  }

  // ===== 代码块：只保可读性，不动配色 =====
  //
  // 代码高亮本身就是配色信息，改掉就毁了文档的表达。
  // 但我们的算色会给父元素设 `color`，代码块如果没有自己的 color
  // 就会继承过去 —— 白底浅字，直接看不见。
  //
  // 所以这里只做一件事：按代码块自己的底色，给容器一个能看清的默认文字色。
  // 背景一律不动，语法高亮 span 上的颜色也不会被覆盖。
  function fixCodeBlock(el) {
    var cs;
    try { cs = getComputedStyle(el); } catch (e) { return; }
    var bg = null;
    try { bg = parseColorWithCache(cs.backgroundColor); } catch (e) { return; }
    var dark;
    if (!bg || bg.a < 0.02) {
      // 透明：露出的是页面深色底，用浅字
      dark = false;
    } else {
      var l = 1;
      try { l = getSRGBLightness(rgbToHSL(bg)); } catch (e) { l = 1; }
      // 底色偏亮 → 需要深字
      dark = l > 0.5;
    }
    el.style.setProperty(
      'color',
      dark ? 'rgb(28, 30, 33)' : 'rgb(226, 228, 233)',
      'important'
    );
  }

  var CODE_TAGS = { PRE: 1, CODE: 1, KBD: 1, SAMP: 1 };

  // ===== 批量调度 =====
  function flush() {
    if (flushing) return;
    flushing = true;
    try {
      var count = 0;
      while (pending.length && count < BATCH_SIZE) {
        var el = pending.shift();
        processElement(el);
        count++;
      }
    } finally {
      // 必须无条件复位：否则任何一次异常都会让队列永久卡死，
      // 页面表现为"只有占位背景生效、一个字都没算色"。
      flushing = false;
    }
    if (pending.length) {
      // 用 setTimeout 而不是 requestAnimationFrame。
      //
      // 实测：Android WebView（Flutter PlatformView 内）里 rAF 会因为
      // 页面不可见或合成原因**不触发**，队列堆积的元素永远不处理。
      // 表现是 SPA 站点只改了初始几个元素，正文全是原色。
      setTimeout(flush, 16);
    }
  }

  function enqueue(el) {
    if (!el || el.nodeType !== 1) return;
    if (processed.has(el)) return;
    if (pending.length > MAX_ELEMENTS) return;
    pending.push(el);
  }

  function walk(root) {
    if (!root) return;
    // 根节点本身也要处理：body.querySelectorAll('*') 只返回后代，
    // 不含 body —— 漏掉它会导致整页文字色停留在站点的原色（深底深字）。
    if (root.nodeType === 1) enqueue(root);
    var all;
    try {
      all = root.querySelectorAll('*');
    } catch (e) {
      return;
    }
    var n = Math.min(all.length, MAX_ELEMENTS);
    for (var i = 0; i < n; i++) enqueue(all[i]);
    flush();
  }

  // ===== 动态内容 =====
  function watch() {
    var mo = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var m = mutations[i];
        if (m.type === 'childList') {
          for (var j = 0; j < m.addedNodes.length; j++) {
            var node = m.addedNodes[j];
            if (node.nodeType !== 1) continue;
            enqueue(node);
            var kids = node.querySelectorAll ? node.querySelectorAll('*') : null;
            if (kids) {
              for (var k = 0; k < kids.length && k < 500; k++) enqueue(kids[k]);
            }
          }
        } else if (m.type === 'attributes') {
          // class/style 变化后重新算一次（先移除标记）
          processed.delete(m.target);
          enqueue(m.target);
        }
      }
      // 同上：rAF 在 WebView 里可能不触发。
      if (pending.length) setTimeout(flush, 0);
    });
    mo.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class', 'style'],
    });
    return mo;
  }

  // ===== 启动 =====
  function start() {
    // 重扫接口：注入后若没立刻生效，宿主会调它补算一遍。
    //
    // SPA 站点在注入时 DOM 可能还是空的（实测某站点初始 6 个节点、
    // 2 秒后 210 个）。光靠页面内的 MutationObserver 不可靠 ——
    // 老 WebView 上观察器行为不一致，队列堆了 200 多个元素也不处理。
    // 由 Dart 侧主动催一遍最稳。
    window.__prForceWalk = function () {
      if (!document.body) return 'no-body';
      walk(document.body);
      return 'ok';
    };
    applyPlaceholder();
    applyUserOverrides();
    if (THEME.useFont && THEME.fontFamily) {
      document.documentElement.style.setProperty(
        'font-family',
        '"' + THEME.fontFamily + '"',
        'important'
      );
    }
    document.documentElement.setAttribute('data-pr-dark', '1');
    walk(document.body || document.documentElement);
    watch();
    // 图片等异步加载完成后再补一轮
    addEventListener('load', function () {
      processed = new WeakSet();
      walk(document.body || document.documentElement);
    }, { once: true });

    // 定时补偿：SPA 站点在 DOMContentLoaded 时可能只有几个节点，
    // 后面才陆续渲染。这里在前 6 秒内定期重扫兜底，
    // 之后停止 —— 不能长期占用定时器影响滚动性能。
    var rescans = 0;
    var rescanTimer = setInterval(function () {
      rescans++;
      if (rescans > 12) {
        clearInterval(rescanTimer);
        return;
      }
      walk(document.body || document.documentElement);
    }, 500);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
    // DOM 还没解析完也要先顶住背景
    applyPlaceholder();
    // 兜底：注入发生在 onPageFinished 之后，此时 readyState 有可能
    // 仍报 'loading'（WebView 68 上实测过），那样 DOMContentLoaded
    // 早就触发过了，监听器永远不会被调用 —— 表现就是 preset 有值、
    // 但引擎一步都没跑，连 data-pr-dark 都没设上。
    //
    // 300ms 后再看一眼：还没标记就说明确实错过了，直接 start。
    setTimeout(function () {
      if (document.documentElement.getAttribute('data-pr-dark') !== '1') {
        start();
      }
    }, 300);
  } else {
    start();
  }
})();
