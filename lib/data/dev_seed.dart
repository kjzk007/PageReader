import 'package:drift/drift.dart';

import 'db/app_database.dart';

/// 仅调试用:库为空时塞几本书,方便看界面。release 构建不会调用。
Future<void> seedIfEmpty(AppDatabase db) async {
  final existing = await (db.select(db.books)..limit(1)).get();
  if (existing.isNotEmpty) return;

  final now = DateTime.now();
  final groups = [
    ('g-frontend', '前端', 0),
    ('g-backend', '后端', 1),
    ('g-infra', '云原生', 2),
  ];
  for (final (id, name, order) in groups) {
    await db
        .into(db.groups)
        .insert(
          GroupsCompanion.insert(
            id: id,
            name: name,
            sortIndex: Value(order),
            updatedAt: now,
          ),
        );
  }

  final books = <(String, String, String, String, int?, String, int)>[
    (
      'b-mdn',
      'MDN Web Docs',
      'https://developer.mozilla.org/zh-CN/docs/Web/JavaScript',
      'https://developer.mozilla.org/zh-CN/docs/Web/JavaScript',
      null,
      'g-frontend',
      0,
    ),
    (
      'b-vue',
      'Vue 3 文档',
      'https://cn.vuejs.org/guide/introduction.html',
      'https://cn.vuejs.org/guide',
      null,
      'g-frontend',
      1,
    ),
    (
      'b-rust',
      'Rust 程序设计语言',
      'https://doc.rust-lang.org/book/',
      'https://doc.rust-lang.org/book',
      null,
      'g-backend',
      2,
    ),
    (
      'b-python',
      'Python 中文教程',
      'https://docs.python.org/zh-cn/3/tutorial/index.html',
      'https://docs.python.org/zh-cn/3/tutorial',
      null,
      'g-backend',
      3,
    ),
    (
      'b-k8s',
      'Kubernetes 文档',
      'https://kubernetes.io/zh-cn/docs/home/',
      'https://kubernetes.io/zh-cn/docs',
      null,
      'g-infra',
      4,
    ),
    (
      'b-go',
      'Go 官方文档',
      'https://go.dev/doc/',
      'https://go.dev/doc',
      null,
      'g-backend',
      5,
    ),
  ];

  for (final (id, title, entry, scope, color, groupId, order) in books) {
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            id: id,
            title: title,
            entryUrl: entry,
            scopePrefix: scope,
            themeColor: Value(color),
            groupId: Value(groupId),
            sortIndex: Value(order),
            createdAt: now.subtract(Duration(days: order * 3)),
            updatedAt: now.subtract(Duration(hours: order * 5)),
          ),
        );
  }

  final progress = [
    ('b-mdn', 'https://developer.mozilla.org/zh-CN/docs/Web/JavaScript/Guide', 'JavaScript 指南', 3),
    ('b-k8s', 'https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/', 'Pod', 48),
    ('b-rust', 'https://doc.rust-lang.org/book/ch10-02-traits.html', 'Trait', 144),
  ];
  for (final (bookId, url, title, hoursAgo) in progress) {
    await db
        .into(db.progressEntries)
        .insert(
          ProgressEntriesCompanion.insert(
            bookId: bookId,
            url: url,
            pageTitle: Value(title),
            updatedAt: now.subtract(Duration(hours: hoursAgo)),
          ),
        );
  }
}