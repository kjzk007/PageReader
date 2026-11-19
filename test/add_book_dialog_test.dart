import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/features/bookshelf/add_book_dialog.dart';

/// 加书对话框的交互测试。
///
/// 这里最容易出的是"范围前缀推导错了" ——
/// 用户粘一个具体章节页,书却把整站吞进来,或者反过来。
void main() {
  Future<AddBookResult?> openAndSubmit(
    WidgetTester tester,
    String url, {
    String title = '',
    List<(String, String)> groups = const [],
  }) async {
    AddBookResult? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              captured = await showDialog<AddBookResult>(
                context: context,
                builder: (_) => AddBookDialog(groups: groups),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '地址').first,
      url,
    );
    await tester.pumpAndSettle();

    if (title.isNotEmpty) {
      await tester.enterText(
        find.widgetWithText(TextField, '书名(可留空)'),
        title,
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('加入书架'));
    await tester.pumpAndSettle();
    return captured;
  }

  testWidgets('粘具体章节页时,范围取所在目录', (tester) async {
    final r = await openAndSubmit(
      tester,
      'https://doc.rust-lang.org/book/ch10-02-traits.html',
    );
    expect(r, isNotNull);
    expect(
      r!.scope,
      'https://doc.rust-lang.org/book',
      reason: '输入章节页时,范围应推到它所在目录',
    );
  });

  testWidgets('粘目录页时,范围就是它自己', (tester) async {
    final r = await openAndSubmit(
      tester,
      'https://kubernetes.io/zh-cn/docs',
    );
    expect(r, isNotNull);
    expect(r!.scope, 'https://kubernetes.io/zh-cn/docs');
  });

  testWidgets('主题名能带出去', (tester) async {
    final r = await openAndSubmit(
      tester,
      'https://example.com/docs',
      title: '我的书',
    );
    expect(r?.title, '我的书');
  });

  testWidgets('非法地址被拦下,不返回结果', (tester) async {
    final r = await openAndSubmit(tester, 'not-a-url');
    expect(r, isNull, reason: '没有协议头的地址应被拒绝');
  });

  testWidgets('只有协议没有域名也被拦下', (tester) async {
    final r = await openAndSubmit(tester, 'https://');
    expect(r, isNull);
  });

  testWidgets('能选分组', (tester) async {
    final r = await openAndSubmit(
      tester,
      'https://example.com/docs',
      groups: [('g1', '前端'), ('g2', '后端')],
    );
    expect(r, isNotNull);

    // 再开一次并选分组
    AddBookResult? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked = await showDialog<AddBookResult>(
                context: context,
                builder: (_) => AddBookDialog(
                  groups: const [('g1', '前端'), ('g2', '后端')],
                ),
              );
            },
            child: const Text('open2'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open2'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '地址').first,
      'https://example.com/docs',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('后端'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入书架'));
    await tester.pumpAndSettle();

    expect(picked?.groupId, 'g2');
  });

  testWidgets('取消不返回结果', (tester) async {
    AddBookResult? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              captured = await showDialog<AddBookResult>(
                context: context,
                builder: (_) => const AddBookDialog(groups: []),
              );
            },
            child: const Text('open3'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(captured, isNull);
  });
}
