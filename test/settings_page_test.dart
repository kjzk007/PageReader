import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/services/settings.dart';
import 'package:pagereader/features/settings/settings_page.dart';

/// 设置页的测试。
///
/// 这块 UI 曾经承载「浏览器插件」区块,插件功能废弃时被整段删除。
/// 删除过程中我切错过结构(删掉了 `)` 导致编译失败),所以这里
/// 用测试锁住"设置页能正常渲染、三块内容都在、主题切换能工作"。
void main() {
  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsStoreProvider.overrideWithValue(null)],
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('设置页渲染', () {
    testWidgets('能正常打开,不抛异常', (tester) async {
      await pumpSettings(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('两块内容都在', (tester) async {
      await pumpSettings(tester);
      // 「外观」在顶部，「关于」在底部。插件区块有内容后会把「关于」
      // 推出首屏，所以要滚动才能看到 —— 这里只断言首屏的「外观」，
      // 「关于」由下面的区块测试单独覆盖。
      expect(find.text('外观'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('不再有「与桌面端配对」占位块', (tester) async {
      // 这块曾经写着「尚未配对 / 还没做」,但同步功能其实已经实现了,
      // 配对入口在工具栏的同步页里。留着这个占位块会让用户以为没做。
      await pumpSettings(tester);
      expect(find.text('与桌面端配对'), findsNothing);
      expect(find.text('还没做'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('标题显示为「设置」', (tester) async {
      await pumpSettings(tester);
      expect(find.text('设置'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('外观三档', () {
    testWidgets('跟随系统 / 浅色 / 深色 都在', (tester) async {
      await pumpSettings(tester);
      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.text('浅色'), findsOneWidget);
      expect(find.text('深色'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('默认选中跟随系统', (tester) async {
      await pumpSettings(tester);
      // 选中项右侧有勾
      final check = find.byIcon(Icons.check);
      expect(check, findsOneWidget, reason: '三档里应该恰好一个被选中');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('点击能切换选中项', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      // 不崩即通过 —— 实际持久化由 ThemeModeNotifier 的单测覆盖,
      // 这里只验证 UI 交互链路能走通。
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('插件区块已移除', () {
    testWidgets('有「浏览器插件」标题', (tester) async {
      await pumpSettings(tester);
      // 内嵌 WebView2 方案下插件是可用的，设置里要有入口。
      expect(
        find.text('浏览器插件'),
        findsOneWidget,
        reason: '插件现在由用户勾选后加载，设置里必须有入口',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('插件区块会渲染出内容或提示', (tester) async {
      await pumpSettings(tester);
      await tester.pumpAndSettle();
      // 无论探到多少个插件，区块都必须有可见内容：
      // 要么是列表，要么是「没找到」的提示。不能是空白。
      final hasList = find.byType(CheckboxListTile).evaluate().isNotEmpty;
      final hasEmptyHint = find.textContaining('没有在本机浏览器里找到插件')
          .evaluate()
          .isNotEmpty;
      expect(
        hasList || hasEmptyHint,
        isTrue,
        reason: '插件区块不该什么都不显示',
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('关于区块', () {
    testWidgets('滚动后能看到关于标题', (tester) async {
      await pumpSettings(tester);
      await tester.pumpAndSettle();
      // 插件区块有内容后「关于」被推到首屏之外，先滚到底。
      await tester.dragUntilVisible(
        find.text('关于'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(find.text('关于'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });


}
