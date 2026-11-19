import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/url_normalizer.dart';

void main() {
  group('normalize', () {
    test('去掉 fragment', () {
      expect(
        UrlNormalizer.normalize('https://a.dev/docs/x#section-3'),
        'https://a.dev/docs/x',
      );
    });

    test('去掉跟踪参数,保留业务参数', () {
      expect(
        UrlNormalizer.normalize('https://a.dev/p?utm_source=x&page=2&ref=home'),
        'https://a.dev/p?page=2',
      );
    });

    test('query 排序后稳定', () {
      expect(
        UrlNormalizer.normalize('https://a.dev/p?b=2&a=1'),
        UrlNormalizer.normalize('https://a.dev/p?a=1&b=2'),
      );
    });

    test('尾斜杠归一,根路径保留', () {
      expect(
        UrlNormalizer.normalize('https://a.dev/docs/'),
        'https://a.dev/docs',
      );
      expect(UrlNormalizer.normalize('https://a.dev/'), 'https://a.dev');
    });

    test('路径大小写保留', () {
      expect(
        UrlNormalizer.normalize('https://a.dev/Docs/X'),
        'https://a.dev/Docs/X',
      );
    });

    test('host 小写', () {
      expect(
        UrlNormalizer.normalize('https://A.Dev/Docs'),
        'https://a.dev/Docs',
      );
    });

    test('省略协议时补 https', () {
      expect(
        UrlNormalizer.normalize('a.dev/docs'),
        'https://a.dev/docs',
      );
    });
  });

  group('scopePrefixOf', () {
    test('输入是具体页面时取所在目录', () {
      expect(
        UrlNormalizer.scopePrefixOf(
          'https://doc.rust-lang.org/book/ch01-00-getting-started.html',
        ),
        'https://doc.rust-lang.org/book',
      );
    });

    test('输入是目录时保留自身', () {
      expect(
        UrlNormalizer.scopePrefixOf('https://kubernetes.io/zh-cn/docs/home/'),
        'https://kubernetes.io/zh-cn/docs/home',
      );
    });

    test('中英文路径是不同的书', () {
      final zh = UrlNormalizer.scopePrefixOf('https://k8s.io/zh-cn/docs/');
      final en = UrlNormalizer.scopePrefixOf('https://k8s.io/en/docs/');
      expect(zh == en, isFalse);
    });

    test('书判定用前缀匹配', () {
      final scope = UrlNormalizer.scopePrefixOf('https://k8s.io/zh-cn/docs/');
      expect(
        UrlNormalizer.normalize('https://k8s.io/zh-cn/docs/concepts/pods/')
            .startsWith(scope),
        isTrue,
      );
    });
  });
}