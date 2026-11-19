// 验证图标抓取:对几个真实文档站,看能不能找到 ≥96px 的图标。
import 'dart:io';

import 'paths.dart';

import 'package:pagereader/core/services/icon_fetcher.dart';

Future<void> main() async {
  const urls = [
    'https://developer.mozilla.org/zh-CN/docs/Web/JavaScript',
    'https://cn.vuejs.org/guide/introduction.html',
    'https://doc.rust-lang.org/book/ch10-02-traits.html',
    'https://kubernetes.io/zh-cn/docs/home/',
    'https://docs.python.org/zh-cn/3/tutorial/index.html',
    'https://go.dev/doc/',
    'https://react.dev/learn',
    'https://www.typescriptlang.org/docs/handbook/intro.html',
  ];

  var found = 0;
  for (final url in urls) {
    final sw = Stopwatch()..start();
    final icon = await IconFetcher.find(url);
    final theme = await IconFetcher.themeColor(url);
    sw.stop();
    final host = Uri.parse(url).host;
    if (icon == null) {
      stdout.writeln('$host: 无图标(${sw.elapsedMilliseconds}ms)→ 首字兜底');
    } else {
      found++;
      final short = icon.url.length > 70
          ? '${icon.url.substring(0, 70)}…'
          : icon.url;
      stdout.writeln(
        '$host: ${icon.size}px  theme=${theme == null ? "-" : theme.toRadixString(16)}  '
        '(${sw.elapsedMilliseconds}ms)  $short',
      );
    }
  }
  stdout.writeln('');
  stdout.writeln('命中 $found/${urls.length}');
}
