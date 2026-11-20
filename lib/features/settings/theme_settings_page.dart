import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/theme_preset.dart';
import '../../core/services/settings.dart';
import 'theme_color_picker.dart';

/// 代表「默认」的哨兵值 —— 不做任何注入，网页原样。
const kDefaultPresetId = '__default__';

/// 主题设置页。
///
/// 设置主页只留一行入口，点进来才是这份列表 ——
/// 把一堆预设和滑块摊在设置主页上会显得疏于管理。
class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(themePresetsProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF15171B),
        foregroundColor: const Color(0xFFE3E5E8),
        elevation: 0,
        title: const Text(
          '主题设置',
          style: TextStyle(fontSize: 15, fontFamily: 'Microsoft YaHei'),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final created = await ref
                  .read(themePresetsProvider.notifier)
                  .create('新主题');
              if (!context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ThemePresetEditPage(presetId: created.id),
                ),
              );
            },
            icon: const Icon(Icons.add, size: 16, color: Color(0xFF5AC8FA)),
            label: const Text(
              '新建',
              style: TextStyle(
                color: Color(0xFF5AC8FA),
                fontSize: 13,
                fontFamily: 'Microsoft YaHei',
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _Row(
            title: '默认',
            subtitle: '网页原样，不做任何注入',
            color: null,
          ),
          const SizedBox(height: 8),
          for (final p in presets)
            _Row(
              title: p.name,
              subtitle: '${p.background} · ${p.text}'
                  '${p.builtin ? ' · 内置' : ''}',
              color: Color(p.backgroundArgb),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ThemePresetEditPage(presetId: p.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1E22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2C3038)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color ?? const Color(0xFF2C3038),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF3A3F47)),
                ),
                child: color == null
                    ? const Icon(Icons.block, size: 16, color: Color(0xFF6B7280))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFE3E5E8),
                        fontSize: 13,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF8A9099),
                        fontSize: 11.5,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Color(0xFF6B7280),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个预设的参数页。取色器选任意颜色，不是固定色板。
class ThemePresetEditPage extends ConsumerStatefulWidget {
  const ThemePresetEditPage({super.key, required this.presetId});

  final String presetId;

  @override
  ConsumerState<ThemePresetEditPage> createState() =>
      _ThemePresetEditPageState();
}

class _ThemePresetEditPageState extends ConsumerState<ThemePresetEditPage> {
  late TextEditingController _name;
  String _background = '#14161a';
  String _text = '#d8dade';
  double _brightness = 100;
  double _contrast = 100;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _loadOnce(ThemePreset? p) {
    if (_loaded || p == null) return;
    _loaded = true;
    _name.text = p.name;
    _background = p.background;
    _text = p.text;
    _brightness = p.brightness;
    _contrast = p.contrast;
  }

  @override
  Widget build(BuildContext context) {
    final preset = ref
        .watch(themePresetsProvider)
        .where((p) => p.id == widget.presetId)
        .firstOrNull;
    if (preset == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0E0F12),
        appBar: AppBar(
          backgroundColor: const Color(0xFF15171B),
          foregroundColor: const Color(0xFFE3E5E8),
          title: const Text('主题已删除'),
        ),
        body: const SizedBox.shrink(),
      );
    }
    _loadOnce(preset);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF15171B),
        foregroundColor: const Color(0xFFE3E5E8),
        elevation: 0,
        title: Text(
          preset.name,
          style: const TextStyle(fontSize: 15, fontFamily: 'Microsoft YaHei'),
        ),
        actions: [
          if (!preset.builtin)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () async {
                await ref
                    .read(themePresetsProvider.notifier)
                    .remove(preset.id);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          TextButton(
            onPressed: () async {
              await ref
                  .read(themePresetsProvider.notifier)
                  .upsert(
                    preset.copyWith(
                      name: _name.text.trim().isEmpty
                          ? preset.name
                          : _name.text.trim(),
                      background: _background,
                      text: _text,
                      brightness: _brightness,
                      contrast: _contrast,
                    ),
                  );
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text(
              '保存',
              style: TextStyle(
                color: Color(0xFF5AC8FA),
                fontSize: 13,
                fontFamily: 'Microsoft YaHei',
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          const _Label('名称'),
          TextField(
            controller: _name,
            style: const TextStyle(
              color: Color(0xFFE3E5E8),
              fontSize: 13,
              fontFamily: 'Microsoft YaHei',
            ),
            decoration: const InputDecoration(isDense: true),
          ),
          const SizedBox(height: 20),
          const _Label('预览'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(_argb(_background)),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF3A3F47)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '阅读正文示例',
                  style: TextStyle(
                    color: Color(_argb(_text)),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '这一段用来判断配色是否适合长时间阅读。'
                  '亮度调高会让页面整体发灰，对比度调高会让文字更硬。',
                  style: TextStyle(
                    color: Color(_argb(_text)).withValues(alpha: 0.9),
                    fontSize: 13,
                    height: 1.6,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ThemeColorPicker(
            title: '页面底色',
            initial: _background,
            onChanged: (v) => setState(() => _background = v),
          ),
          const SizedBox(height: 20),
          ThemeColorPicker(
            title: '正文颜色',
            initial: _text,
            onChanged: (v) => setState(() => _text = v),
          ),
          const SizedBox(height: 20),
          _Slider(
            label: '亮度',
            value: _brightness,
            onChanged: (v) => setState(() => _brightness = v),
          ),
          _Slider(
            label: '对比度',
            value: _contrast,
            onChanged: (v) => setState(() => _contrast = v),
          ),
          const SizedBox(height: 10),
          Text(
            _isDark(_background)
                ? '底色偏暗：引擎会把浅色页面往深算。'
                : '底色偏亮：引擎会把深色页面往浅算。',
            style: const TextStyle(
              color: Color(0xFF8A9099),
              fontSize: 11.5,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
        ],
      ),
    );
  }

  static int _argb(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length != 6) return 0xFF14161A;
    return 0xFF000000 | (int.tryParse(h, radix: 16) ?? 0x14161A);
  }

  static bool _isDark(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length != 6) return true;
    final r = int.tryParse(h.substring(0, 2), radix: 16) ?? 0;
    final g = int.tryParse(h.substring(2, 4), radix: 16) ?? 0;
    final b = int.tryParse(h.substring(4, 6), radix: 16) ?? 0;
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 < 0.5;
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF8A9099),
          fontSize: 11.5,
          fontFamily: 'Microsoft YaHei',
        ),
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8A9099),
                fontSize: 11.5,
                fontFamily: 'Microsoft YaHei',
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(30, 160),
              min: 30,
              max: 160,
              divisions: 130,
              activeColor: const Color(0xFF5AC8FA),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              value.round().toString(),
              style: const TextStyle(
                color: Color(0xFF8A9099),
                fontSize: 11.5,
                fontFamily: 'Microsoft YaHei',
              ),
            ),
          ),
        ],
      ),
    );
  }
}