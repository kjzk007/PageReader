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
    // 这两个不能省：极点（pole）计算会读它们，
    // 缺了就是 undefined，插值直接失败，表现为"文字色完全没变"。
    // 算法自身把空串当作"没有第二极点"。
    secondaryBackgroundColor: '',
    secondaryTextColor: '',
    scrollbarColor: '',
    selectionColor: 'auto',
    styleSystemControls: false,
    lightColorScheme: 'Default',
    darkColorScheme: 'Default',
    immediateModify: false,
  };

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
    try {
      var bgColor = parseColorWithCache(cs.backgroundColor);
      if (bgColor && bgColor.a > 0.02) {
        var newBg = modifyBackgroundColor(bgColor, THEME);
        var bgCss = toCss(newBg);
        if (bgCss) el.style.setProperty('background-color', bgCss, 'important');
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
        var fgColor = parseColorWithCache(cs.color);
        if (fgColor && fgColor.a > 0.02) {
          var newFg = modifyForegroundColor(fgColor, THEME);
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
  var errors = [];
  function note(arr, msg) {
    if (arr.length < 5 && msg) arr.push(msg);
    window.__prDarkErrors = arr;
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
      requestAnimationFrame(flush);
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
      if (pending.length) requestAnimationFrame(flush);
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
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
    // DOM 还没解析完也要先顶住背景
    applyPlaceholder();
  } else {
    start();
  }
})();
