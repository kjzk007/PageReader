import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/theme_preset.dart';
import '../../core/services/settings.dart';

/// 预设列表里代表「默认」的哨兵值 —— 不注入任何样式。
const kDefaultPresetId = '__default__';

/// 设置 → 主题设置（列表页）。
///
/// 这里只显示所有预设的摘要，点进去才是具体参数。
/// 不把滑块和取色器直接铺在设置页 —— 那会让设置页看起来像堆杂物。
class ThemePresetSection extends ConsumerWidget {
  const ThemePresetSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(themePresetsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Tile(
          title: '默认',
          subtitle: '不注入任何样式，网页原样',
          previewBg: null,
          onTap: null,
        ),
        for (final p in presets)
          _Tile(
            title: p.name,
            subtitle:
                '背景 ${p.background} · 文字 ${p.text}'
                '${p.builtin ? ' · 内置' : ''}',
            previewBg: Color(p.backgroundArgb),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _PresetDetailPage(presetId: p.id),
              ),
            ),
          ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () async {
            final created = await ref
                .read(themePresetsProvider.notifier)
                .create('新主题');
            if (!context.mounted) return;
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _PresetDetailPage(presetId: created.id),
              ),
            );
          },
          icon: const Icon(Icons.add, size: 16, color: Color(0xFF5AC8FA)),
          label: const Text(
            '新建主题',
            style: TextStyle(
              color: Color(0xFF5AC8FA),
              fontSize: 13,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.subtitle,
    required this.previewBg,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color? previewBg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1E22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2C3038)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: previewBg ?? const Color(0xFF2C3038),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF3A3F47)),
                ),
                child: previewBg == null
                    ? const Icon(
                        Icons.block,
                        size: 16,
                        color: Color(0xFF6B7280),
                      )
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

/// 单个预设的参数页。点列表项才进来。
class _PresetDetailPage extends ConsumerStatefulWidget {
  const _PresetDetailPage({required this.presetId});

  final String presetId;

  @override
  ConsumerState<_PresetDetailPage> createState() => _PresetDetailPageState();
}

class _PresetDetailPageState extends ConsumerState<_PresetDetailPage> {
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
        padding: const EdgeInsets.all(16),
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
          // 预览在最上面：改参数时不用滚动就能看到效果。
          const _Label('预览'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(
                0xFF000000 |
                    (int.tryParse(_background.replaceAll('#', ''), radix: 16) ??
                        0x14161a),
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF3A3F47)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '阅读正文示例',
                  style: TextStyle(
                    color: Color(
                      0xFF000000 |
                          (int.tryParse(
                                _text.replaceAll('#', ''),
                                radix: 16,
                              ) ??
                              0xd8dade),
                    ),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '这一段用来判断配色是否适合长时间阅读。亮度调高会让页面整体发灰，'
                  '对比度调高会让文字更硬。',
                  style: TextStyle(
                    color: Color(
                      0xFF000000 |
                          (int.tryParse(
                                _text.replaceAll('#', ''),
                                radix: 16,
                              ) ??
                              0xd8dade),
                    ).withValues(alpha: 0.9),
                    fontSize: 13,
                    height: 1.6,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _Label('页面底色'),
          _Swatches(
            colors: const [
              ('#14161a', '深灰'),
              ('#1a1b1e', '中灰'),
              ('#0f1013', '近黑'),
              ('#1e2024', '暖灰'),
              ('#141a16', '墨绿'),
              ('#1a1410', '暖棕'),
              ('#f7f8fa', '浅白'),
              ('#faf6ef', '米黄'),
            ],
            current: _background,
            onPick: (v) => setState(() => _background = v),
          ),
          const SizedBox(height: 16),
          const _Label('正文颜色'),
          _Swatches(
            colors: const [
              ('#d8dade', '浅灰'),
              ('#e8e6e3', '米白'),
              ('#c8ccd4', '中灰'),
              ('#a8b0bc', '暗灰'),
              ('#2c3038', '深灰'),
              ('#1a1b1e', '近黑'),
            ],
            current: _text,
            onPick: (v) => setState(() => _text = v),
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
          const SizedBox(height: 12),
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

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.colors,
    required this.current,
    required this.onPick,
  });

  final List<(String, String)> colors;
  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (hex, label) in colors)
          Tooltip(
            message: label,
            child: GestureDetector(
              onTap: () => onPick(hex),
              child: Container(
                width: 44,
                height: 34,
                decoration: BoxDecoration(
                  color: Color(
                    0xFF000000 |
                        (int.tryParse(hex.replaceAll('#', ''), radix: 16) ?? 0),
                  ),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: hex.toLowerCase() == current.toLowerCase()
                        ? const Color(0xFF5AC8FA)
                        : const Color(0xFF3A3F47),
                    width: hex.toLowerCase() == current.toLowerCase() ? 2 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
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