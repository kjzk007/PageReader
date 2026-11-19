/// 位置上报脚本:让页面主动把"我在哪"推给 Dart 侧。
///
/// 为什么用事件驱动而不是定时轮询:
///   * 静止时零开销(不滚动就永远不上报)
///   * 关窗口那一刻能拿到精确位置(pagehide 里 DOM 还在)
///   * 断电/强杀也能覆盖到最后一刻,因为滚动后 800ms 就落库了
///
/// 依赖 `Runtime.addBinding` 注册的 `window.__prReport`。
/// 没注册时静默跳过,不会因为缺函数报错。
const String positionReportScript = r'''
(function () {
  if (window.__prReporting) return 'already';
  window.__prReporting = true;

  function snapshot(why) {
    try {
      var se = document.scrollingElement || document.documentElement;
      var max = se ? (se.scrollHeight - se.clientHeight) : 0;
      var y = window.scrollY || (se ? se.scrollTop : 0);
      var anchor = null;
      if (window.__pr && typeof window.__pr.collect === 'function') {
        var c = window.__pr.collect();
        anchor = c ? c.anchor : null;
      }
      return {
        why: why,
        y: y,
        ratio: max > 0 ? y / max : 0,
        href: location.href,
        title: document.title,
        anchor: anchor
      };
    } catch (e) {
      return null;
    }
  }

  function report(why) {
    try {
      if (typeof window.__prReport !== 'function') return;
      var s = snapshot(why);
      if (!s) return;
      window.__prReport(JSON.stringify(s));
    } catch (e) {}
  }

  // 滚动:防抖 800ms。连续滑动只报最后一次,避免写库过频。
  //
  // 必须同时挂在 window 和 document 上:
  //   * 大多数页面滚动会冒泡到 window;
  //   * 但用 `document.scrollingElement.scrollTop = y` 直接设值、
  //     或某些容器的 scroll 不冒泡时,只有 document 上的监听能收到。
  // 实测:只挂 window 时,验收脚本用 scrollTop 赋值滚动会完全没反应
  // (日志里只有一条 y=0 的初始上报)。
  var timer = null;
  function scheduleReport() {
    if (timer) clearTimeout(timer);
    timer = setTimeout(function () {
      timer = null;
      report('scroll');
    }, 800);
  }
  window.addEventListener('scroll', scheduleReport, {
    passive: true, capture: true
  });
  document.addEventListener('scroll', scheduleReport, {
    passive: true, capture: true
  });

  // SPA 路由:文档站切章节常常只改 history 不重新加载。
  ['pushState', 'replaceState'].forEach(function (k) {
    var orig = history[k];
    if (!orig) return;
    history[k] = function () {
      var r = orig.apply(this, arguments);
      setTimeout(function () { report('route'); }, 120);
      return r;
    };
  });
  window.addEventListener('popstate', function () { report('popstate'); });
  window.addEventListener('hashchange', function () { report('hashchange'); });

  // 关闭与切后台:这是"关窗口时记录位置"的关键。
  window.addEventListener('pagehide', function () { report('pagehide'); }, true);
  window.addEventListener('beforeunload', function () { report('beforeunload'); }, true);
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'hidden') report('hidden');
  }, true);

  return 'installed';
})();
''';

/// 注入到页面的锚点脚本。在文档脚本执行前注入,所以能抢在框架水合之前挂好观察器。
///
/// 对外只暴露两个函数:
///   `__pr.collect()`  → 采集当前位置
///   `__pr.restore(a)` → 按锚点恢复,失败自动三级降级
///
/// 约定:所有滚动都用 `behavior: 'instant'`,避免恢复时出现动画导致的二次跳动。
const String anchorBootstrapScript = r'''
(function () {
  if (window.__pr) return;

  var BLOCK = 'p,h1,h2,h3,h4,h5,h6,li,pre,blockquote,table,figure';
  var restoring = false;

  function scrollable(node) {
    var s = getComputedStyle(node);
    if (!/(auto|scroll|overlay)/.test(s.overflowY)) return false;
    return node.scrollHeight > node.clientHeight + 4;
  }

  function findScroller() {
    var se = document.scrollingElement || document.documentElement;
    if (se && se.scrollHeight > se.clientHeight + 4) return se;

    // 注意:不能"找到第一个可滚容器就用"。
    // 文档站常有侧边栏目录,它自己也是可滚容器,而且比正文更容易先被扫到;
    // 一旦选错,后续所有比例都基于侧边栏算,永远是 0。
    // 正确做法:选可见面积最大的那个。
    var best = null;
    var bestArea = 0;
    var list = document.querySelectorAll('main, article, section, div, aside, nav');
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      if (!scrollable(el)) continue;
      var r = el.getBoundingClientRect();
      if (r.width < 120 || r.height < 120) continue;
      var area = r.width * r.height;
      if (area > bestArea) {
        best = el;
        bestArea = area;
      }
    }
    return best;
  }

  function cssPath(el) {
    var parts = [];
    var node = el;
    while (node && node.nodeType === 1 && node !== document.documentElement) {
      var idx = 1, sib = node;
      while ((sib = sib.previousElementSibling)) {
        if (sib.tagName === node.tagName) idx++;
      }
      parts.unshift(node.tagName.toLowerCase() + ':nth-of-type(' + idx + ')');
      node = node.parentElement;
    }
    return parts.join(' > ');
  }

  function textOf(el) {
    return (el.innerText || '').replace(/\s+/g, ' ').trim();
  }

  // 判断元素是否在导航/侧边栏里。
  // 文档站的目录树本身就是一堆 li/p,而且往往先于正文出现在 DOM 里;
  // 如果不排除,锚点会记在"第 11 章"这种目录项上,恢复时页面纹丝不动。
  // 判断元素是否在"页面框架"(导航/侧栏/页头页脚)里。
  //
  // 踩过的坑:MDN 的正文包在
  //   <div class="layout__header reference-layout__header">
  // 里。旧版用 /header/ 直接匹配 class 字符串,把这个**布局容器**
  // 当成了页头,于是 main 里 24 个正文段落全被排除、
  // pickAnchor 拿不到候选、锚点永远是 null ——
  // 表现就是"MDN 这本书从来不记进度"。
  //
  // BEM 命名(block__element)里,__ 后面的是元素名,
  // 只代表"某块里的一个部件",不代表这块本身是页头:
  //   layout__header        → block=layout    不是页头
  //   site-header__inner    → block=site-header 是页头
  // 所以只检查 block 部分。
  function clsLooksChrome(cls) {
    var tokens = cls.split(/\s+/);
    for (var i = 0; i < tokens.length; i++) {
      var t = tokens[i];
      if (!t) continue;
      var block = t.split('__')[0];
      // nav 这一族要显式列全:navbar / navigation 都是导航,
      // 只写 nav 会漏掉它们。
      // 但必须保留分隔符边界,否则 navy、navigate-btn 会被误伤。
      if (/(^|[-_])(sidebar|toc|menu|menubar|nav|navbar|navigation|navigator|breadcrumb|toolbar|header|footer|masthead)([-_]|$)/.test(block)) {
        return true;
      }
    }
    return false;
  }

  function inChrome(el) {
    var node = el;
    while (node && node !== document.body) {
      var tag = node.tagName;
      var role = node.getAttribute && node.getAttribute('role');
      var looksChrome =
        tag === 'NAV' || tag === 'ASIDE' || tag === 'HEADER' || tag === 'FOOTER' ||
        role === 'navigation' || role === 'banner' || role === 'complementary';

      if (!looksChrome) {
        var cls = (node.className || '').toString().toLowerCase();
        if (cls && clsLooksChrome(cls)) looksChrome = true;
        var id = (node.id || '').toString().toLowerCase();
        if (id && /(sidebar|toc|menu|nav|breadcrumb)/.test(id)) looksChrome = true;
      }

      if (looksChrome) {
        // Fallback: an element inside <main>/[role=main]/#content is body
        // text, so the "looks like chrome" guess above was a false positive.
        //
        // Two things matter here, both learned the hard way:
        //
        // 1) Judge by `node` (the level we are currently walking up from),
        //    not `el` (the original block). Sites like hello-algo nest the
        //    sidebar inside <main>:
        //       main
        //         +-- nav
        //               +-- ul > li   <- table of contents entry
        //    `el.closest("main")` always finds main, so EVERY chrome guess
        //    gets cancelled and the anchor lands on a TOC item such as
        //    "\u5e8f". Restoring then scrolls to the top of the chapter -- the
        //    "chapter is right, exact position is lost" symptom.
        //
        // 2) A node that IS a semantic chrome tag (NAV/ASIDE/role=navigation)
        //    is chrome no matter where it sits, so return immediately.
        var nodeIsSemanticChrome =
          tag === 'NAV' || tag === 'ASIDE' ||
          role === 'navigation' || role === 'complementary';
        if (nodeIsSemanticChrome) {
          return true;
        }
        var inMain = node.closest
          ? node.closest('main,[role="main"],article,#content,.markdown-body,.content')
          : null;
        if (!inMain) return true;
      }

      node = node.parentElement;
    }
    return false;
  }

  function pickAnchor() {
    var vh = window.innerHeight || 0;
    var blocks = document.querySelectorAll(BLOCK);
    var chosen = null;
    var fallback = null;
    for (var i = 0; i < blocks.length; i++) {
      var el = blocks[i];
      if (inChrome(el)) continue;
      var r = el.getBoundingClientRect();
      if (r.height <= 0 || r.bottom <= 0 || r.top >= vh) continue;
      // Skip elements with no text.
      //
      // An empty <p> is usually a spacer or a container the framework filled
      // later. Picking one produces an anchor with textFingerprint="",
      // which leaves only docRatio as a fallback -- so if the CSS path ever
      // breaks, the restore silently degrades to "roughly the right place".
      // Observed on hello-algo: p:nth-of-type(6) matched an empty spacer.
      if (!textOf(el)) continue;
      var visible = Math.min(r.bottom, vh) - Math.max(r.top, 0);
      if (visible > r.height * 0.5) {
        chosen = el;
        break;
      }
      if (!fallback) fallback = el;
    }
    if (!chosen) chosen = fallback;
    if (!chosen) return null;

    var rect = chosen.getBoundingClientRect();
    var scroller = findScroller();
    var total = 0, top = 0;
    if (scroller && scroller !== document.scrollingElement && scroller !== document.documentElement) {
      total = scroller.scrollHeight - scroller.clientHeight;
      top = scroller.scrollTop;
    } else {
      var se = document.scrollingElement || document.documentElement;
      total = se.scrollHeight - se.clientHeight;
      top = window.scrollY || se.scrollTop || 0;
    }

    // 页面不足一屏时没有"位置"可言:此时不记锚点。
    // 否则会存一个 docRatio=0 的无用锚点,每次打开都白跑一遍恢复逻辑,
    // 而且在 CSS 路径失效后还会把用户拉回页首。
    if (total <= 8) return null;

    var ratio = top / total;
    var text = textOf(chosen);

    return {
      cssPath: cssPath(chosen),
      textFingerprint: text.slice(0, 40),
      textLength: text.length,
      offsetPx: rect.top,
      docRatio: Math.max(0, Math.min(1, ratio))
    };
  }

  function collect() {
    return {
      url: location.href,
      title: document.title,
      hash: location.hash,
      ready: document.readyState,
      anchor: pickAnchor()
    };
  }

  function scrollToEl(el, offset) {
    var scroller = findScroller();
    if (scroller && scroller !== document.scrollingElement && scroller !== document.documentElement) {
      var t1 = el.getBoundingClientRect().top + scroller.scrollTop - (offset || 0);
      scroller.scrollTo({ top: t1, behavior: 'instant' });
      return;
    }
    var t2 = el.getBoundingClientRect().top + (window.scrollY || 0) - (offset || 0);
    window.scrollTo({ top: t2, behavior: 'instant' });
  }

  function findByText(fp) {
    if (!fp) return null;
    var blocks = document.querySelectorAll(BLOCK);
    var best = null, bestScore = 0;
    for (var i = 0; i < blocks.length; i++) {
      var t = textOf(blocks[i]);
      if (!t) continue;
      var score = 0;
      if (t.indexOf(fp) === 0) score = 2;
      else if (t.indexOf(fp) >= 0) score = 1;
      if (score > bestScore) { best = blocks[i]; bestScore = score; }
    }
    return best;
  }

  function cancelOnUserInput() {
    if (!restoring) return;
    restoring = false;
    window.removeEventListener('wheel', cancelOnUserInput, true);
    window.removeEventListener('touchstart', cancelOnUserInput, true);
  }

  function restore(anchor) {
    if (!anchor) return 'no-anchor';
    restoring = true;
    window.addEventListener('wheel', cancelOnUserInput, true);
    window.addEventListener('touchstart', cancelOnUserInput, true);

    var attempts = 0;
    function attempt() {
      if (!restoring) return 'cancelled';
      var el = null;
      try {
        el = anchor.cssPath ? document.querySelector(anchor.cssPath) : null;
      } catch (e) { el = null; }
      if (el && anchor.textFingerprint && textOf(el).indexOf(anchor.textFingerprint) !== 0) {
        el = null;
      }
      if (!el) el = findByText(anchor.textFingerprint);
      if (el) {
        scrollToEl(el, anchor.offsetPx || 0);
        restoring = false;
        return 'hit';
      }
      var scroller = findScroller() || document.scrollingElement;
      if (scroller && anchor.docRatio) {
        var top = anchor.docRatio * (scroller.scrollHeight - scroller.clientHeight);
        if (scroller === document.scrollingElement) window.scrollTo({ top: top, behavior: 'instant' });
        else scroller.scrollTo({ top: top, behavior: 'instant' });
      }
      return 'pending';
    }

    var result = attempt();
    if (result === 'hit') return result;

    var observer = new MutationObserver(function () { attempt(); });
    observer.observe(document.documentElement, { childList: true, subtree: true });
    var timer = setInterval(function () {
      attempts++;
      var r = attempt();
      if (r === 'hit' || r === 'cancelled' || attempts > 10) {
        clearInterval(timer);
        observer.disconnect();
      }
    }, 200);
    return 'scheduled';
  }

  window.__pr = { collect: collect, restore: restore };
})();
''';
