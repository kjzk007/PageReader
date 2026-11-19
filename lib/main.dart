import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/ports/ports.dart';
import 'core/services/icon_fetcher.dart';
import 'core/services/icon_palette.dart';
import 'core/services/progress_recorder.dart';
import 'core/services/settings.dart';
import 'core/services/shelf_service.dart';
import 'data/db/app_database.dart';
import 'core/domain/cover_color.dart';
import 'core/domain/models.dart';
import 'data/dev_seed.dart';
import 'data/sqlite_library_store.dart';
import 'engine/desktop/browser_locator.dart';
import 'engine/desktop/cdp_engine.dart';
import 'engine/android/webview_engine.dart';
import 'features/bookshelf/bookshelf_page.dart';
import 'features/shell/quit_guard.dart';
import 'features/shell/single_instance.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final libraryStoreProvider = Provider<LibraryStore>(
  (ref) => SqliteLibraryStore(ref.watch(databaseProvider)),
);

/// 浏览器与引擎只在桌面端存在。找不到浏览器时引擎为 null,
/// 解析数据目录。
///
/// 支持 `PAGEREADER_DATA_DIR` 覆盖,供验收脚本在隔离沙箱里跑 ——
/// 验收绝不能碰用户真实的书架数据。
///
/// 之前验收脚本直接删 %APPDATA% 下的库,把用户手动加的书全清空了,
/// 这是开发工具污染产品数据,必须隔离。
Future<Directory> resolveDataDir() async {
  final override = _envValue('PAGEREADER_DATA_DIR');
  if (override != null) {
    final dir = Directory(override);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
  return getApplicationSupportDirectory();
}

/// 阅读引擎:按平台分派。
///
///   桌面 → CdpEngine,驱动外部 Edge/Chrome
///   Android → WebViewEngine,内嵌 WebView(渲染在应用进程内)
///
/// 两者实现同一个 WebEngine 接口,书架与记录器无需知道区别。
final engineProvider = FutureProvider<WebEngine?>((ref) async {
  // Android:内嵌 WebView,不需要找外部浏览器。
  if (Platform.isAndroid) {
    final engine = WebViewEngine();
    ref.onDispose(engine.shutdown);
    return engine;
  }

  // 桌面:必须有 Chromium 内核的浏览器。
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return null;
  }
  final browser = BrowserLocator.find();
  if (browser == null) return null;

  final support = await resolveDataDir();
  final profile = Directory(p.join(support.path, 'browser-profile'));

  // 关于插件:不支持。
  //
  // 试过三条路,没有一条能同时满足"插件可用 + 进度正常":
  //
  //  1. 独立 profile + --load-extension
  //     插件能跑、登录态能搬,但插件认为自己「首次安装」——
  //     每次启动都弹欢迎页(多出一个窗口)。要消除它得往
  //     Secure Preferences 写 30+ 字段的安装记录,而 Edge 启动时会
  //     重写这个文件,我写的记录被丢掉(实测两次)。
  //
  //  2. 直接用用户的日常 profile
  //     插件原生可用、无欢迎页。但 Edge 对指向真实 User Data 的
  //     --user-data-dir **不写 DevToolsActivePort**(实测等 30 秒没有),
  //     这是安全策略:防止已登录数据被自动化工具读取。
  //     没有端口 = 完全没有进度记录。
  //
  //  3. 自写 Edge 扩展做进度采集
  //     技术上可行,但要用户额外安装扩展并维护,工作量远超收益。
  //
  // 进度记录是这个产品的根本,插件是附加能力。
  // 既然不能两全,选择保住进度 —— 不加载任何插件。

  final engine = CdpEngine(browserPath: browser, profileDir: profile);
  ref.onDispose(engine.shutdown);
  return engine;
});

/// 启动后补齐缺失的封面图标。
///
/// 图标只在"加书"时抓,种子数据和老记录都没有 iconUrl,
/// 书架上就永远是字母块。这里在后台补一次,补到就更新,
/// 失败保持原样 —— 不阻塞启动,也不打扰用户。
/// 书架重载信号:后台补图完成后 +1,书架据此刷新。
final shelfReloadProvider = Provider<ValueNotifier<int>>((ref) {
  final notifier = ValueNotifier<int>(0);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// 启动后给缺底色的书补一次封面底色。
///
/// 两类图标必须用两套规则(实测得出,别合并):
///
///   1. **自带不透明底框**的图标(K8s 纯白底、MDN/react 深色底):
///      直接把那块底色当卡片底色。图标边框与卡片同色,
///      边界消失,整张卡片就像封面。
///
///   2. **透明图标**(大多数 SVG、带 alpha 的 PNG):
///      用主色的深色版,把明度差拉开。
///      反面案例:Python 图标是蓝+黄,若用主色当底会蓝压蓝,
///      图标完全看不清 —— 这是用户实测指出的问题。
final themeColorBackfillProvider = FutureProvider<void>((ref) async {
  final store = ref.watch(libraryStoreProvider);
  final reload = ref.watch(shelfReloadProvider);
  var changed = false;
  final books = await store.loadBooks();
  for (final b in books) {
    // 跳过"已经有合适配色"的书。
    //
    // 注意不能只判断 null:早期版本给采不到颜色的站兜底成了灰色 #8a8a8a,
    // 那些旧值会一直留着,永远是难看的灰。
    // 把"接近灰"的旧值当成需要重算。
    if (b.themeColor != null && !CoverColor.looksLikeOldFallbackGray(b.themeColor!)) {
      continue;
    }
    try {
      // 已经有 iconUrl 就直接用它 —— 不再重新抓页面。
      //
      // 踩过的坑:回填时无条件调 IconFetcher.find(),而它要联网抓 HTML。
      // 网络稍差或站点限流就返回 null,整个回填被跳过,
      // 表现为"图标有、底色是黑的"。图标 URL 早就存在库里,不该重抓。
      String? iconUrl = b.iconUrl;
      if (iconUrl == null || iconUrl.isEmpty) {
        final found = await IconFetcher.find(b.entryUrl);
        iconUrl = found?.url;
        final url = found?.url;
        if (url != null) {
          try {
            await DefaultCacheManager().downloadFile(url);
          } catch (_) {}
        }
      }

      int? color;
      if (iconUrl != null && iconUrl.isNotEmpty) {
        // 先看有没有自带底框。
        final bg = await IconPalette.backgroundOf(iconUrl);
        if (bg != null) {
          // 自带底框:直接用它,让图标和卡片融为一体。
          color = CoverColor.shelfSafe(bg);
        } else {
          // 透明图标:用主色的深色版,保证图标看得清。
          final dom = await IconPalette.dominantOf(iconUrl);
          color = dom == null ? null : CoverColor.forTransparentIcon(dom);
        }
      }      // 都没有才退站点声明的 theme-color。
      color ??= await IconFetcher.themeColor(b.entryUrl);
      // 还是拿不到:用域名生成一个稳定的颜色,而不是灰色。
      //
      // 灰色是所有兜底里最难看的 —— 它看起来像"没设置"而不是"一个设计"。
      // 用域名做哈希映射到一组挑好的深色,同一本书永远同一色,不刺眼。
      color ??= CoverColor.fallback(b.entryUrl);

      await store.upsertBook(
        Book(
          id: b.id,
          title: b.title,
          entryUrl: b.entryUrl,
          scopePrefix: b.scopePrefix,
          iconUrl: iconUrl,
          themeColor: color,
          groupId: b.groupId,
          sortIndex: b.sortIndex,
          createdAt: b.createdAt,
          updatedAt: DateTime.now(),
        ),
      );
      changed = true;
    } catch (_) {
      // 单本失败不影响其它。
    }
  }
  if (changed) reload.value++;
});

/// 启动后把书架里所有书的范围登记到引擎。
///
/// 作用:上次应用被杀时浏览器可能还开着,那些窗口现在没人管。
/// 引擎需要知道"哪个 URL 前缀属于哪本书"才能把窗口认领回来,
/// 否则孤儿窗口的进度上报会因为映射不到书而被丢弃。
final adoptProvider = FutureProvider<void>((ref) async {
  final engine = await ref.watch(engineProvider.future);
  if (engine is! CdpEngine) return;
  final store = ref.watch(libraryStoreProvider);
  final books = await store.loadBooks();
  for (final b in books) {
    engine.registerScope(b.id, b.scopePrefix);
  }
  try {
    await engine.adoptOrphanWindows();
  } catch (_) {
    // 没有遗留窗口是常态,认领失败不该影响启动。
  }
});


final recorderProvider = FutureProvider<ProgressRecorder?>((ref) async {
  final engine = await ref.watch(engineProvider.future);
  if (engine == null) return null;
  final recorder = ProgressRecorder(
    engine: engine,
    store: ref.watch(libraryStoreProvider),
  )..start();
  ref.onDispose(recorder.dispose);
  return recorder;
});

final shelfServiceProvider = FutureProvider<ShelfService?>((ref) async {
  final engine = await ref.watch(engineProvider.future);
  if (engine == null) return null;
  return ShelfService(store: ref.watch(libraryStoreProvider), engine: engine);
});

/// 应用启动就把记录器建好并订阅导航流。
///
/// 之前的 bug:recorderProvider 定义了但全项目没人 watch,
/// 于是 ProgressRecorder 从未启动,导航事件没人接收,进度一条都没写进库。
final progressRecorderInstanceProvider =
    FutureProvider<ProgressRecorder?>((ref) async {
      final recorder = await ref.watch(recorderProvider.future);
      recorder?.start();
      return recorder;
    });

/// 启动前的一次性准备:调试构建下,空库塞几本示例书。
final bootstrapProvider = FutureProvider<void>((ref) async {
  if (kDebugMode) {
    await seedIfEmpty(ref.watch(databaseProvider));
  }
});

void main() async {
  _dumpArgs();
  // window_manager 内部会 setMethodCallHandler,必须在 binding 初始化之后,
  // 否则启动就抛 "Cannot set the method call handler before the binary
  // messenger has been initialized"。
  WidgetsFlutterBinding.ensureInitialized();

  // 单实例:第二个进程直接退出,避免两个进程同时写同一个 SQLite。
  // 锁必须在任何数据库操作之前拿到。
  Directory? supportDir;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    supportDir = await resolveDataDir();
    if (!SingleInstance.acquire(supportDir)) {
      // 已有实例在跑:把它激活到前台,然后自己退出。
      try {
        await windowManager.ensureInitialized();
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
      exit(0);
    }
  }

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(900, 600),
      center: true,
      title: 'PageReader',
      backgroundColor: Color(0xFF0E0F12),
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  // 设置要在第一帧之前加载:否则会先按默认主题画一帧再跳到用户的选择,
  // 视觉上闪一下。
  final settings = await SettingsStore.open();

  // 启动时把已保存的主题下发给 Android 的 uiMode,
  // 保证 WebView 从第一页开始就用正确的深浅配色。


  runApp(
    ProviderScope(
      overrides: [settingsStoreProvider.overrideWithValue(settings)],
      child: const PageReaderApp(),
    ),
  );
}

class PageReaderApp extends ConsumerWidget {
  const PageReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 主题模式由设置页决定,三档:跟随系统 / 浅色 / 深色。
    //
    // 这个值同时影响两件事:
    //   1. app 自己的配色(下面的 themeMode)
    //   2. WebView 报告给站点的 prefers-color-scheme
    //      —— 见 android 端 setThemeMode 的说明
    final mode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'PageReader',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      darkTheme: _buildTheme(Brightness.dark),
      theme: _buildTheme(Brightness.light),
      home: const _Boot(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF0E0F12)
          : const Color(0xFFF7F8FA),
      colorScheme: dark
          ? const ColorScheme.dark(
              primary: Color(0xFF5AC8FA),
              surface: Color(0xFF15171B),
            )
          : const ColorScheme.light(
              primary: Color(0xFF0A84C8),
              surface: Color(0xFFFFFFFF),
            ),
      // 显式指定中文字体。
      //
      // 不指定时 Flutter 会走默认回退链,中文字形可能落到一个
      // 宽度偏大的字体上 —— 这是"复制地址"被截断的直接原因:
      // 4 个中文字符在 112px 的菜单项里放不下。
      // 统一成微软雅黑,Windows 上一定存在,宽度也更紧凑。
      fontFamily: 'Microsoft YaHei',
      fontFamilyFallback: const ['Microsoft YaHei', 'SimHei', 'sans-serif'],
      useMaterial3: true,
    );
  }
}

class _Boot extends ConsumerWidget {
  const _Boot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(bootstrapProvider);
    return ready.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0E0F12),
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (error, _) => Scaffold(
        backgroundColor: const Color(0xFF0E0F12),
        body: Center(
          child: Text(
            '启动失败:$error',
            style: const TextStyle(color: Color(0xFFE3E5E8)),
          ),
        ),
      ),
      data: (_) => const _ShelfHost(),
    );
  }
}

class _ShelfHost extends ConsumerWidget {
  const _ShelfHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 关键:watch 一下,记录器才会真正被创建并开始监听导航流。
    final recorder = ref.watch(progressRecorderInstanceProvider).value;
    // 同时预热浏览器:书架一出现就开始在后台拉起来,点击时无缝衔接。
    ref.watch(adoptProvider);
    ref.watch(themeColorBackfillProvider);

    return QuitGuard(
      onFlush: () async {
        // 退出前把每本开着的书都采一次并落库。
        final engine = ref.read(engineProvider).value;
        final store = ref.read(libraryStoreProvider);
        if (engine is CdpEngine) {
          final snapshots = await engine.flushAll();
          for (final s in snapshots) {
            await store.saveProgress(s);
          }
        }
      },
      child: BookshelfPage(
        store: ref.watch(libraryStoreProvider),
        engine: ref.watch(engineProvider).value,
        recorder: recorder,
        autoOpenBookId: _envValue('PAGEREADER_OPEN'),
        autoCloseMs: int.tryParse(_envValue('PAGEREADER_CLOSE_AFTER') ?? ''),
        reloadSignal: ref.watch(shelfReloadProvider),
      ),
    );
  }
}

/// 读验收用的参数。
///
/// 不能用命令行:Windows 上 `Platform.executableArguments` 恒为空,
/// Flutter 的 C++ 外壳把参数消费掉了,没转发给 Dart(实测确认)。
/// 改用环境变量:`PAGEREADER_OPEN=<bookId>`、`PAGEREADER_CLOSE_AFTER=<ms>`。
String? _envValue(String key) {
  final v = Platform.environment[key];
  if (v == null || v.trim().isEmpty) return null;
  return v.trim();
}

/// 调试用:把验收相关环境变量打到 stdout,方便排查"参数没传到"。
void _dumpArgs() {
  if (!kDebugMode) return;
  // ignore: avoid_print
  print(
    'verify env: OPEN=${_envValue('PAGEREADER_OPEN')} '
    'CLOSE_AFTER=${_envValue('PAGEREADER_CLOSE_AFTER')}',
  );
}


