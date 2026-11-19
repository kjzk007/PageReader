import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/anchor_script.dart';

/// inChrome 的判定逻辑测试。
///
/// 这是踩过真实 bug 的地方:MDN 的正文容器叫
/// `layout__header reference-layout__header`,旧逻辑把它当页头,
/// 导致整本书永远不记进度。
///
/// 直接用正则表达式复刻 JS 侧的规则来验证,
/// 保证 Dart 测试和注入脚本行为一致。
void main() {
  /// 复刻 clsLooksChrome:BEM 里只检查 block 部分。
  bool clsLooksChrome(String cls) {
    final tokens = cls.toLowerCase().split(RegExp(r'\s+'));
    final re = RegExp(
      r'(^|[-_])(sidebar|toc|menu|menubar|nav|navbar|navigation|navigator|breadcrumb|toolbar|header|footer|masthead)([-_]|$)',
    );
    for (final t in tokens) {
      if (t.isEmpty) continue;
      final block = t.split('__').first;
      if (re.hasMatch(block)) return true;
    }
    return false;
  }

  group('BEM 布局容器不该被当成页头', () {
    test('layout__header 是布局块,不是页头', () {
      expect(
        clsLooksChrome('layout__header reference-layout__header'),
        isFalse,
        reason: '这是 MDN 的正文容器,排除它会导致永远不记进度',
      );
    });

    test('site-header__inner 是真页头', () {
      expect(clsLooksChrome('site-header__inner'), isTrue);
    });

    test('page-header 是真页头', () {
      expect(clsLooksChrome('page-header'), isTrue);
    });

    test('reference-layout__header 同样是布局块', () {
      expect(clsLooksChrome('reference-layout__header'), isFalse);
    });
  });

  group('侧栏与目录仍要被识别', () {
    test('left-sidebar__content 是侧栏内容', () {
      expect(clsLooksChrome('left-sidebar__content'), isTrue);
    });

    test('sidebar 单独出现', () {
      expect(clsLooksChrome('sidebar'), isTrue);
    });

    test('reference-toc 是目录', () {
      expect(clsLooksChrome('reference-toc'), isTrue);
    });

    test('menu', () {
      expect(clsLooksChrome('nav menu'), isTrue);
    });
  });

  group('不能误伤普通内容类名', () {
    test('content', () {
      expect(clsLooksChrome('content'), isFalse);
    });

    test('markdown-body', () {
      expect(clsLooksChrome('markdown-body'), isFalse);
    });

    test('article', () {
      expect(clsLooksChrome('article'), isFalse);
    });

    test('navigation 作为 block 要被识别(是真导航)', () {
      expect(clsLooksChrome('navigation'), isTrue);
    });

    test('navbar', () {
      expect(clsLooksChrome('navbar'), isTrue);
    });
  });

  group('注入脚本包含修复后的逻辑', () {
    test('脚本里有 clsLooksChrome', () {
      expect(
        anchorBootstrapScript.contains('clsLooksChrome'),
        isTrue,
        reason: '修复必须真的进了注入脚本,否则部署后无效',
      );
    });

    test('脚本里处理了 BEM 的 __ 分隔', () {
      expect(
        anchorBootstrapScript.contains("split('__')"),
        isTrue,
      );
    });

    test('脚本里有正文区兜底检查', () {
      expect(
        anchorBootstrapScript.contains('inMain'),
        isTrue,
        reason: '元素若在 main/article/#content 里,任何"像页头"的判断都是误判',
      );
    });

    test('注入脚本能被 node 解析(语法正确)', () async {
      // 这条是血泪教训:之前用脚本批量改注释,把 \r\n 当字面量
      // 写进了 JS 注释里,产生了 v: 这种碎片,
      // 整个 bundle 语法错误 —— 注入静默失败,__pr 根本不存在,
      // 表现就是"所有站点都不记进度"。
      // 单测测不到 JS 语法,只能借 node --check。
      final bundle =
          '\n';
      final f = File(
        '/pr_bundle_check.js',
      );
      f.writeAsStringSync(bundle);
      final r = await Process.run('node', ['--check', f.path]);
      expect(
        r.exitCode,
        0,
        reason: '注入脚本语法错误:',
      );
      f.deleteSync();
    }, skip: !Platform.isWindows && !Platform.isLinux);

    test('兜底用 closest 而非 querySelector', () {
      // MDN 结构是 MAIN.layout__content > DIV.layout__header > H1,
      // main 是祖先不是后代。用 querySelector 往下找永远找不到。
      expect(
        anchorBootstrapScript.contains('el.closest'),
        isTrue,
        reason: '必须往祖先方向查 main',
      );
    });
  });
}
