import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/dark_preset.dart';
import '../../core/services/settings.dart';

/// 设置里的「深色注入」区块。
///
/// ── 这是什么 ──
///
/// 程序自己实现的深色注入：把网页里的浅色逐元素算成同色系的深色，
/// 不依赖任何浏览器插件。用户在这里调好一套参数（预设），
/// 然后在书架上右键某本书选用哪一套。
///
/// 不选就是「默认」——一个字都不注入，网页原样。
class DarkPresetSection extends ConsumerWidget {
  const DarkPresetSection({super.key});

  static const _labelStyle = TextStyle(
    color: Color(0xFFE3E5E8),
    fontSize: 13,
    fontFamily: 'Microsoft YaHei',
  );
  static const _hintStyle = TextStyle(
    color: Color(0xFF8A9099),
    fontSize: 11.5,
    fontFamily: 'Microsoft YaHei',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(darkPresetsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '给某本书套一套深色样式（右键书 → 深色注入）。不选则为默认，网页原样。',
            style: _hintStyle,
          ),
        ),
        for (final p in presets)
          _PresetTile(key: ValueKey(p.id), preset: p),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () async {
            final created = await ref
                .read(darkPresetsProvider.notifier)
                .create('新预设');
            if (context.mounted) {
              await showDialog<void>(
                context: context,
                builder: (_) => _PresetEditor(preset: created),
              );
            }
          },
          icon: const Icon(Icons.add, size: 16, color: Color(0xFF5AC8FA)),
          label: const Text(
            '新建预设',
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

class _PresetTile extends ConsumerWidget {
  const _PresetTile({super.key, required this.preset});

  final DarkPreset preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1E22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2C3038)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _parseHex(preset.background),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF3A3F47)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preset.name, style: DarkPresetSection._labelStyle),
                Text(
                  '亮度 ${preset.brightness.round()} · 对比度 '
                  '${preset.contrast.round()}'
                  '${preset.builtin ? ' · 内置' : ''}',
                  style: DarkPresetSection._hintStyle,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _PresetEditor(preset: preset),
            ),
            child: const Text(
              '调整',
              style: TextStyle(
                color: Color(0xFF5AC8FA),
                fontSize: 12,
                fontFamily: 'Microsoft YaHei',
              ),
            ),
          ),
          if (!preset.builtin)
            IconButton(
              iconSize: 16,
              icon: const Icon(Icons.delete_outline, color: Color(0xFF8A9099)),
              onPressed: () async {
                await ref.read(darkPresetsProvider.notifier).remove(preset.id);
              },
            ),
        ],
      ),
    );
  }

  static Color _parseHex(String hex) {
    final h = hex.replaceAll('#', '');
    final v = int.tryParse(h, radix: 16) ?? 0x14161a;
    return Color(0xFF000000 | v);
  }
}

/// 单个预设的参数编辑。
///
/// 只暴露真正影响阅读的几个：底色、文字色、亮度、对比度。
/// 灰度/棕褐这类"滤镜感"的项不放出来 —— 深色阅读不需要变色温。
class _PresetEditor extends ConsumerStatefulWidget {
  const _PresetEditor({required this.preset});

  final DarkPreset preset;

  @override
  ConsumerState<_PresetEditor> createState() => _PresetEditorState();
}

class _PresetEditorState extends ConsumerState<_PresetEditor> {
  late TextEditingController _name;
  late String _background;
  late String _text;
  late double _brightness;
  late double _contrast;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.preset.name);
    _background = widget.preset.background;
    _text = widget.preset.text;
    _brightness = widget.preset.brightness;
    _contrast = widget.preset.contrast;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1E22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF3A3F47)),
      ),
      title: Text('深色预设', style: DarkPresetSection._labelStyle),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              style: DarkPresetSection._labelStyle,
              decoration: const InputDecoration(
                labelText: '名称',
                labelStyle: DarkPresetSection._hintStyle,
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            _slider('亮度', _brightness, 30, 160, (v) {
              setState(() => _brightness = v);
            }),
            _slider('对比度', _contrast, 30, 160, (v) {
              setState(() => _contrast = v);
            }),
            const SizedBox(height: 6),
            Text('页面底色 $_background', style: DarkPresetSection._hintStyle),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final c in const [
                  '#14161a',
                  '#1a1b1e',
                  '#0f1013',
                  '#1e2024',
                  '#141a16',
                ])
                  _swatch(c, _background, (v) {
                    setState(() => _background = v);
                  }),
              ],
            ),
            const SizedBox(height: 10),
            Text('正文颜色 $_text', style: DarkPresetSection._hintStyle),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final c in const [
                  '#d8dade',
                  '#e8e6e3',
                  '#c8ccd4',
                  '#b8bec8',
                ])
                  _swatch(c, _text, (v) {
                    setState(() => _text = v);
                  }),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Color(
                  0xFF000000 |
                      (int.tryParse(_background.replaceAll('#', ''),
                              radix: 16) ??
                          0x14161a),
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '预览：这一段文字会按此配色显示。',
                style: TextStyle(
                  color: Color(
                    0xFF000000 |
                        (int.tryParse(_text.replaceAll('#', ''), radix: 16) ??
                            0xd8dade),
                  ),
                  fontSize: 13,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: Color(0xFF8A9099), fontSize: 13),
          ),
        ),
        TextButton(
          onPressed: () async {
            await ref
                .read(darkPresetsProvider.notifier)
                .upsert(
                  widget.preset.copyWith(
                    name: _name.text.trim().isEmpty
                        ? widget.preset.name
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
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: DarkPresetSection._hintStyle),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            activeColor: const Color(0xFF5AC8FA),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.round().toString(),
            style: DarkPresetSection._hintStyle,
          ),
        ),
      ],
    );
  }

  Widget _swatch(String color, String current, ValueChanged<String> onPick) {
    final isCurrent = color.toLowerCase() == current.toLowerCase();
    return GestureDetector(
      onTap: () => onPick(color),
      child: Container(
        width: 30,
        height: 24,
        decoration: BoxDecoration(
          color: Color(
            0xFF000000 | (int.tryParse(color.replaceAll('#', ''), radix: 16) ?? 0),
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isCurrent ? const Color(0xFF5AC8FA) : const Color(0xFF3A3F47),
            width: isCurrent ? 2 : 1,
          ),
        ),
      ),
    );
  }
}