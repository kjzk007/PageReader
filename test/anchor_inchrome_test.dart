import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/anchor_script.dart';

/// 锚点采集脚本的关键约束测试。
///
/// 这些是真人实测踩出来的坑，用断言锁住，避免以后改脚本时又退回去。
void main() {
  group('inChrome：页框识别', () {
    test('以 node 而非 el 做 main 兜底', () {
      // 回归测试：hello-algo 把侧边栏嵌在 <main> 里，
      // 用 el.closest('main') 会让每一层判定都被否掉，
      // 锚点落到目录项 "序" 上，恢复时回到章首。
      expect(
        anchorBootstrapScript.contains('node.closest'),
        isTrue,
        reason: '必须用 node 判断是否在 main 里，不能用 el',
      );
      // 只看实际代码行，注释里提到 el.closest 是正常的（说明历史原因）。
      final codeLines = anchorBootstrapScript
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'));
      expect(
        codeLines.any((l) => l.contains('el.closest')),
        isFalse,
        reason: 'el.closest 会误判嵌套在 main 里的侧边栏',
      );
    });

    test('语义页框标签直接判为页框', () {
      expect(
        anchorBootstrapScript.contains('nodeIsSemanticChrome'),
        isTrue,
        reason: 'NAV/ASIDE/role=navigation 无论在哪都算页框',
      );
    });
  });

  group('锚点采集', () {
    test('页面不足一屏时不记锚点', () {
      expect(
        anchorBootstrapScript.contains('if (total <= 8) return null;'),
        isTrue,
        reason: '不该存 docRatio=0 的无用锚点',
      );
    });

    test('跳过没有文本的元素', () {
      // 空 <p> 通常是分隔符或框架后填的容器。选中它会产生
      // textFingerprint="" 的锚点，只剩 docRatio 能兜底，
      // CSS 路径一失效就退化成"大概在附近"。
      expect(
        anchorBootstrapScript.contains('if (!textOf(el)) continue;'),
        isTrue,
        reason: '空文本元素不该成为锚点',
      );
    });

    test('offsetPx 记的是元素相对视口的位移', () {
      expect(anchorBootstrapScript.contains('offsetPx: rect.top'), isTrue);
    });
  });

  group('锚点恢复', () {
    test('对外暴露 __pr.restore', () {
      expect(
        anchorBootstrapScript.contains('window.__pr = {'),
        isTrue,
      );
      expect(anchorBootstrapScript.contains('restore: restore'), isTrue);
    });

    test('恢复时按 cssPath 命中，失败再退化到文本匹配', () {
      expect(
        anchorBootstrapScript.contains('anchor.cssPath ? document.querySelector'),
        isTrue,
      );
      expect(anchorBootstrapScript.contains('findByText'), isTrue);
    });

    test('恢复被用户滚动打断时停止', () {
      expect(anchorBootstrapScript.contains('cancelOnUserInput'), isTrue);
    });
  });
}
