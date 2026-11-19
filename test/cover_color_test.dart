import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/cover_color.dart';

void main() {
  group('自带底框:原样使用', () {
    test('纯白保持不变', () {
      expect(CoverColor.shelfSafe(0xFFFFFFFF), 0xFFFFFFFF);
    });

    test('深底保持不变', () {
      expect(CoverColor.shelfSafe(0xFF15141A), 0xFF15141A);
    });

    test('不透明化', () {
      // 即使传进来带 alpha,输出也必须不透明。
      expect((CoverColor.shelfSafe(0x80FF0000) >> 24) & 0xFF, 255);
    });
  });

  group('透明图标:按明暗决定方向', () {
    test('黑色图标要被提亮(否则黑压黑看不见)', () {
      final c = CoverColor.forTransparentIcon(0xFF000000);
      expect(
        CoverColor.luminance(c),
        greaterThan(100),
        reason: '黑图标必须有浅底',
      );
    });

    test('深蓝图标要被提亮', () {
      final c = CoverColor.forTransparentIcon(0xFF102040);
      expect(CoverColor.luminance(c), greaterThan(100));
    });

    test('中亮蓝色要被压暗(否则蓝压蓝)', () {
      // Python 的 #5A9FD4 就是这一类
      final c = CoverColor.forTransparentIcon(0xFF5A9FD4);
      expect(
        CoverColor.luminance(c),
        lessThan(90),
        reason: '中亮图标必须有暗底,拉开明度差',
      );
    });

    test('Python 图标:底色与图标主色明度差足够', () {
      final iconLuma = CoverColor.luminance(0xFF5A9FD4);
      final bgLuma = CoverColor.luminance(
        CoverColor.forTransparentIcon(0xFF5A9FD4),
      );
      expect((iconLuma - bgLuma).abs(), greaterThan(60));
    });

    test('已足够暗的颜色保持不变', () {
      // 亮度落在 40..90 区间的颜色作为底色已经够暗,不该再动。
      // 这类是真"深色品牌色"(如某些深靛),压暗没有意义。
      const dark = 0xFF23201F; // 亮度约 33 -> 会提亮
      const mid = 0xFF404040; // 亮度 64 -> 保持
      final midResult = CoverColor.forTransparentIcon(mid);
      expect(
        CoverColor.luminance(midResult),
        closeTo(CoverColor.luminance(mid), 1),
        reason: '40..90 的深色不该被调整',
      );
      // 极深色(亮度 < 40)必须提亮,否则黑图标看不见。
      expect(
        CoverColor.luminance(CoverColor.forTransparentIcon(dark)),
        greaterThan(100),
        reason: '接近黑的图标色必须提亮底色',
      );
    });
  });

  group('域名兜底', () {
    test('同一域名永远同一色', () {
      final a = CoverColor.fallback('https://go.dev/docs');
      final b = CoverColor.fallback('https://go.dev/other');
      expect(a, b);
    });

    test('不同域名大概率不同色', () {
      final a = CoverColor.fallback('https://alpha.dev');
      final b = CoverColor.fallback('https://beta.dev');
      expect(a, isNot(b));
    });

    test('兜底色不是灰(通道差足够)', () {
      for (final host in [
        'go.dev',
        'a.dev',
        'b.dev',
        'c.dev',
        'd.dev',
        'e.dev',
      ]) {
        final c = CoverColor.fallback('https://$host');
        final r = (c >> 16) & 0xFF;
        final g = (c >> 8) & 0xFF;
        final b = c & 0xFF;
        final maxC = [r, g, b].reduce((x, y) => x > y ? x : y);
        final minC = [r, g, b].reduce((x, y) => x < y ? x : y);
        expect(maxC - minC, greaterThan(15), reason: '$host 兜底色不该是灰');
      }
    });

    test('兜底色足够暗,适合深色书架', () {
      for (final host in ['go.dev', 'x.dev', 'y.dev']) {
        final c = CoverColor.fallback('https://$host');
        expect(CoverColor.luminance(c), lessThan(90));
      }
    });

    test('非法输入不抛异常', () {
      expect(CoverColor.fallback(''), isA<int>());
      expect(CoverColor.fallback('not a url'), isA<int>());
    });
  });

  group('旧灰色兜底的识别', () {
    test('中间灰要重算', () {
      expect(CoverColor.looksLikeOldFallbackGray(0xFF8A8A8A), isTrue);
      expect(CoverColor.looksLikeOldFallbackGray(0xFF808080), isTrue);
      expect(CoverColor.looksLikeOldFallbackGray(0xFF8E9A9E), isTrue);
    });

    test('极暗的深底不要重算(MDN 的 #15141a)', () {
      expect(
        CoverColor.looksLikeOldFallbackGray(0xFF15141A),
        isFalse,
        reason: '深底是站点有意设计,重算会白费网络',
      );
    });

    test('纯白不要重算(K8s 的 #ffffff)', () {
      expect(CoverColor.looksLikeOldFallbackGray(0xFFFFFFFF), isFalse);
    });

    test('有彩度的品牌色不要重算', () {
      expect(CoverColor.looksLikeOldFallbackGray(0xFF3776AB), isFalse);
      expect(CoverColor.looksLikeOldFallbackGray(0xFF42B883), isFalse);
    });
  });

  group('亮度计算', () {
    test('黑 0 白 255', () {
      expect(CoverColor.luminance(0xFF000000), closeTo(0, 0.01));
      expect(CoverColor.luminance(0xFFFFFFFF), closeTo(255, 0.01));
    });
  });
}
