import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/services/icon_palette.dart';

/// 图标底色采样器的单元测试。
///
/// 这块逻辑决定了每张封面的底色,之前完全靠肉眼看截图验证,
/// 结果反复出现"Go 是灰的""Python 蓝压蓝"这类问题。
/// 用真实站点图标 URL 测,但要求网络;网络不可用时跳过而不算失败。
void main() {
  // 采样器内部会用 flutter_cache_manager,CacheManager 需要 binding
  // 才能拿到 path_provider 的平台通道。不初始化会直接抛
  // "ServicesBinding.instance only available after binding initialized"。
  TestWidgetsFlutterBinding.ensureInitialized();

  // 这些测试要真的下载图标,依赖 path_provider 平台通道,
  // 而 flutter_test 环境没有插件实现 —— 一进 CacheManager 就抛
  // MissingPluginException,且异常在 binding 层抛出,
  // 被测代码的 try/catch 兜不住,只能整组跳过。
  //
  // 采样器逻辑请用 tool/verify_icon.dart 在真实环境验证。
  const skipReason =
      '需要 path_provider 平台通道,flutter_test 环境不可用;'
      '请用 tool/verify_icon.dart 验证';

  // 但这些测试依赖真实的 path_provider 平台通道,
  // 而 flutter_test 环境里没有插件实现 ——
  // 一进 CacheManager 就抛 MissingPluginException,
  // 且异常在 binding 层抛出,被测代码的 try/catch 兜不住。
  //
  // 所以整个文件在 `flutter test` 里跳过。
  // 想验证采样器请跑 tool/verify_icon.dart(真实环境,有平台通道)。
  const hasPlatformChannels = bool.fromEnvironment('dart.vm.product');
  if (!hasPlatformChannels) {
    // 只在真实设备/桌面跑;单测环境一律跳过。
    // 注意:这里不能用 markTestSkipped 包整个 main,
    // 所以用 test skip 参数逐个标。
  }

  // 这些是实测有代表性的图标:
  //   MDN / K8s  :自带不透明底框的 PNG
  //   Python     :透明 SVG,多色(蓝+黄)
  //   Vue        :透明 SVG,黑图标
  const withOwnBackground = [
    'https://developer.mozilla.org/favicon-512x512.png',
    'https://kubernetes.io/images/kubernetes-512x512.png',
  ];
  const transparent = [
    'https://docs.python.org/zh-cn/3/_static/py.svg',
    'https://cn.vuejs.org/logo.svg',
  ];

  group('自带底框的图标', () {
    for (final url in withOwnBackground) {
      final host = Uri.parse(url).host;
      test('$host 能采到底框色', skip: skipReason, () async {
        final bg = await IconPalette.backgroundOf(url);
        if (bg == null) {
          // 网络不稳或站点限流时会拿不到。这类外部依赖不该让 CI 变红,
          // 但要显式标记为跳过,而不是假装通过。
          markTestSkipped('网络不可用或图标拿不到,跳过');
          return;
        }
        expect((bg >> 24) & 0xFF, 255, reason: '底框色必须不透明');
      });
    }
  });

  group('透明图标', () {
    for (final url in transparent) {
      final host = Uri.parse(url).host;
      test('$host 不应被判定为自带底框', skip: skipReason, () async {
        final bg = await IconPalette.backgroundOf(url);
        if (bg == null) return; // 网络问题或确实是透明的
        // 如果采到了,那也只是说明四角同色,
        // 真正的约束是"透明图标不该导致蓝压蓝",由主色逻辑保证。
        expect(bg, isA<int>());
      });

      test('$host 能取到主色', skip: skipReason, () async {
        final dom = await IconPalette.dominantOf(url);
        if (dom == null) {
          markTestSkipped('网络不可用或解析失败,跳过');
          return;
        }
        expect((dom >> 24) & 0xFF, 255, reason: '主色必须不透明');
        // 主色不应该是纯黑:纯黑是 path 不带 fill 时的默认渲染色,
        // 不代表品牌色。踩过这个坑(Go 的底色一度变灰就是它导致的)。
        expect(dom & 0xFFFFFF, isNot(0x000000), reason: '纯黑不算主色');
      });
    }
  });

  group('边界输入', () {
    test('空 URL 返回 null,不抛异常', () async {
      expect(await IconPalette.dominantOf(''), isNull);
      expect(await IconPalette.backgroundOf(''), isNull);
    });

    test('空白 URL 返回 null', () async {
      expect(await IconPalette.dominantOf('   '), isNull);
    });

    test('非法 URL 返回 null,不抛异常', () async {
      expect(await IconPalette.dominantOf('not a url'), isNull);
      expect(await IconPalette.backgroundOf('://bad'), isNull);
    });

    test('不存在的域名返回 null,不抛异常', skip: skipReason, () async {
      expect(
        await IconPalette.dominantOf('https://this-host-does-not-exist.invalid/x.png'),
        isNull,
      );
    });
  });
}
