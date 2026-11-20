
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/settings.dart';
import 'theme_settings_page.dart';
import 'extension_section.dart';

/// 设置页。
///
/// 目前只有"外观"和"同步"两块入口。同步功能还没实现,
/// 但先把入口占位放出来 —— 用户能看见"以后会有"，
/// 比让他猜这个 app 有没有同步要好。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0F12),
        elevation: 0,
        title: const Text(
          '设置',
          style: TextStyle(
            color: Color(0xFFF2F3F5),
            fontSize: 18,
            fontFamily: 'Microsoft YaHei',
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF9AA0A6)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _sectionTitle('外观'),
          _ThemeModeSelector(
            value: themeMode,
            onChanged: (m) async {
              await ref.read(themeModeProvider.notifier).set(m);
              // 切主题会重建 Activity(改 uiMode 才能让网页跟着变),
              // 页面栈会被清空 —— 所以主动回到书架,避免用户看到
              // 一个"设置页突然消失"的错觉。
              if (context.mounted) {
                Navigator.of(context).maybePop();
              }
            },
          ),
          const SizedBox(height: 8),
          const _Hint(
            '这个设置只影响 PageReader 自己的界面（书架、设置、阅读页外壳）。'
            '网页显示成什么颜色由站点自己决定。',
          ),
          const SizedBox(height: 28),
          _sectionTitle('主题设置'),
          _ThemeEntry(),
          const SizedBox(height: 28),
          _sectionTitle('浏览器插件'),
          const ExtensionSection(),
          _sectionTitle('关于'),
          const _About(),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF6E747C),
          fontSize: 12,
          fontFamily: 'Microsoft YaHei',
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// 深浅色三选一。
///
/// 为什么给三档而不是一个开关:
/// 用户可能希望"app 永远深色"但系统是浅色 —— 阅读器深色更护眼，
/// 这与系统偏好是两件独立的事。所以必须能显式覆盖。
class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({required this.value, required this.onChanged});

  final ThemeMode value;
  final void Function(ThemeMode) onChanged;

  @override
  Widget build(BuildContext context) {
    const options = <(ThemeMode, String, IconData)>[
      (ThemeMode.system, '跟随系统', Icons.brightness_auto_outlined),
      (ThemeMode.light, '浅色', Icons.light_mode_outlined),
      (ThemeMode.dark, '深色', Icons.dark_mode_outlined),
    ];

    return Column(
      children: [
        for (final (mode, label, icon) in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: value == mode
                  ? const Color(0xFF1E2A32)
                  : const Color(0xFF191B1F),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onChanged(mode),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: value == mode
                            ? const Color(0xFF5AC8FA)
                            : const Color(0xFF7C8188),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: value == mode
                                ? const Color(0xFFE3E5E8)
                                : const Color(0xFF9AA0A6),
                            fontSize: 14,
                            fontFamily: 'Microsoft YaHei',
                          ),
                        ),
                      ),
                      if (value == mode)
                        const Icon(
                          Icons.check,
                          size: 18,
                          color: Color(0xFF5AC8FA),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 浏览器插件管理。
///
/// 设计要点:
///   * 总开关默认关 —— 挂插件会拖慢启动,有些还会弹标签页。
/// 与桌面端配对的占位说明。
class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF191B1F),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 40,
              height: 40,
              // 图标缺失不该让关于页崩掉。
              errorBuilder: (_, _, _) => const SizedBox(
                width: 40,
                height: 40,
                child: ColoredBox(color: Color(0xFF262A30)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PageReader',
                  style: TextStyle(
                    color: Color(0xFFE3E5E8),
                    fontSize: 14,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '把网页当书读。进度记在本地，换设备也能接上。',
                  style: TextStyle(
                    color: Color(0xFF5F656C),
                    fontSize: 11,
                    fontFamily: 'Microsoft YaHei',
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF5F656C),
          fontSize: 11,
          fontFamily: 'Microsoft YaHei',
          height: 1.6,
        ),
      ),
    );
  }
}

/// 设置主页上的「主题设置」入口。
///
/// 只显示当前有几套不是默认的主题，点进去才是列表。
class _ThemeEntry extends ConsumerWidget {
  const _ThemeEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(themePresetsProvider);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1E22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2C3038)),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ThemeSettingsPage()),
        ),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.palette_outlined,
                  size: 18, color: Color(0xFF8A9099)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '主题设置',
                      style: TextStyle(
                        color: Color(0xFFE3E5E8),
                        fontSize: 13,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      presets.isEmpty
                          ? '还没有自定义主题'
                          : '${presets.length} 套主题',
                      style: const TextStyle(
                        color: Color(0xFF8A9099),
                        fontSize: 11.5,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFF6B7280)),
            ],
          ),
        ),
      ),
    );
  }
}
