import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/theme_preset.dart';
import '../../core/services/settings.dart';
import 'theme_color_field.dart';

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

/// 单个预设的参数页。
///
/// 布局顺序：预览在最上（改任何参数都立刻能看到），
/// 然后颜色四项、亮度三项。
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
  String _link = '#5ac8fa';
  String _selection = '#2f6f8f';
  String _secondaryBackground = '#1a1d23';
  String _secondaryText = '#a8b0bc';
  double _brightness = 100;
  double _contrast = 100;
  double _imageBrightness = 100;
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
    _link = p.link;
    _selection = p.selection;
    _secondaryBackground = p.secondaryBackground;
    _secondaryText = p.secondaryText;
    _brightness = p.brightness;
    _contrast = p.contrast;
    _imageBrightness = p.imageBrightness;
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
                      link: _link,
                      selection: _selection,
                      secondaryBackground: _secondaryBackground,
                      secondaryText: _secondaryText,
                      brightness: _brightness,
                      contrast: _contrast,
                      imageBrightness: _imageBrightness,
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
          ThemePreviewCard(
            background: _background,
            text: _text,
            link: _link,
            selection: _selection,
            secondaryBackground: _secondaryBackground,
            secondaryText: _secondaryText,
            brightness: _brightness,
            contrast: _contrast,
            imageBrightness: _imageBrightness,
          ),
          const SizedBox(height: 20),
          const _SectionLabel('名称'),
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
          const _SectionLabel('颜色'),
              // 两行 × 三列：一列一行会把六个选择器拉成一条长竖条。
              Row(
                children: [
                  Expanded(
                    child: ThemeColorField(
                      label: '背景色',
                      value: _background,
                      onChanged: (v) => setState(() => _background = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ThemeColorField(
                      label: '文字色',
                      value: _text,
                      onChanged: (v) => setState(() => _text = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ThemeColorField(
                      label: '链接色',
                      value: _link,
                      onChanged: (v) => setState(() => _link = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ThemeColorField(
                      label: '次级背景',
                      value: _secondaryBackground,
                      onChanged: (v) => setState(() => _secondaryBackground = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ThemeColorField(
                      label: '次级文字',
                      value: _secondaryText,
                      onChanged: (v) => setState(() => _secondaryText = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ThemeColorField(
                      label: '选中色',
                      value: _selection,
                      onChanged: (v) => setState(() => _selection = v),
                    ),
                  ),
                ],
              ),
          _Slider(
            label: '文字亮度',
            value: _brightness,
            onChanged: (v) => setState(() => _brightness = v),
          ),
          _Slider(
            label: '文字对比度',
            value: _contrast,
            onChanged: (v) => setState(() => _contrast = v),
          ),
          _Slider(
            label: '图片亮度',
            value: _imageBrightness,
            onChanged: (v) => setState(() => _imageBrightness = v),
          ),
          const SizedBox(height: 8),
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

/// 预览卡片：把「标题 / 正文 / 链接 / 选中 / 引用 / 列表 / 图片」摆出来。
///
/// 每一项都对应一个可调维度 —— 改哪个参数都能在这里看出差别，
/// 否则用户调完不知道有没有生效。
class ThemePreviewCard extends StatelessWidget {
  const ThemePreviewCard({
    super.key,
    required this.background,
    required this.text,
    required this.link,
    required this.selection,
    required this.secondaryBackground,
    required this.secondaryText,
    required this.brightness,
    required this.contrast,
    required this.imageBrightness,
  });

  final String background;
  final String text;
  final String link;
  final String selection;
  final String secondaryBackground;
  final String secondaryText;
  final double brightness;
  final double contrast;
  final double imageBrightness;

  /// 与引擎 adjustTextColor 完全一致的实现。
  ///
  /// 亮度：向白/向黑插值，最多吃掉 30% 余量；
  /// 对比度：以页面底色为基准缩放差值。
  /// 两者都用插值而不是乘法，避免把接近白的中亮文字顶成纯白。
  static Color _adjustTextColor(
    Color fg,
    Color bg,
    double brightness,
    double contrast,
  ) {
    var r = fg.r * 255;
    var g = fg.g * 255;
    var b = fg.b * 255;
    final br = bg.r * 255;
    final bgc = bg.g * 255;
    final bb = bg.b * 255;

    if (brightness != 100) {
      final t = (brightness - 100) / 100;
      final k = t.abs().clamp(0.0, 0.6) * 0.5;
      if (t > 0) {
        r = r + (255 - r) * k;
        g = g + (255 - g) * k;
        b = b + (255 - b) * k;
      } else {
        r *= (1 - k);
        g *= (1 - k);
        b *= (1 - k);
      }
    }

    if (contrast != 100) {
      final ct = (contrast - 100) / 100;
      final cf = 1 + ct.clamp(-0.85, 1.2);
      r = br + (r - br) * cf;
      g = bgc + (g - bgc) * cf;
      b = bb + (b - bb) * cf;
    }

    return Color.fromARGB(
      255,
      r.clamp(0, 255).round(),
      g.clamp(0, 255).round(),
      b.clamp(0, 255).round(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = ThemeColorField.colorOf(background);
    final fg = ThemeColorField.colorOf(text);
    // 必须和引擎的 adjustTextColor 用同一套算法，否则预览和实际对不上 ——
    // 用户在这里看不出变化，调到页面上才发现完全不同。
    final fgFinal = _adjustTextColor(fg, bg, brightness, contrast);
    final subBg = ThemeColorField.colorOf(secondaryBackground);
    final subText = _adjustTextColor(
      ThemeColorField.colorOf(secondaryText),
      bg,
      brightness,
      contrast,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3F47)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第一章　阅读的姿势',
            style: TextStyle(
              color: fgFinal,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '长时间阅读时，页面底色和文字色的对比决定眼睛的舒适度。'
            '这一行用来判断正文是否清晰。',
            style: TextStyle(
              color: fgFinal,
              fontSize: 13,
              height: 1.7,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
          const SizedBox(height: 8),
          // 链接：单独上色，方便判断是否和正文拉开
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '参考：',
                  style: TextStyle(
                    color: fgFinal,
                    fontSize: 13,
                    height: 1.7,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
                TextSpan(
                  text: '相关章节的说明',
                  style: TextStyle(
                    color: ThemeColorField.colorOf(link),
                    fontSize: 13,
                    height: 1.7,
                    decoration: TextDecoration.underline,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
                TextSpan(
                  text: '，点开可以跳转。',
                  style: TextStyle(
                    color: fgFinal,
                    fontSize: 13,
                    height: 1.7,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 选中效果：用一段套了背景色的文字模拟
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            color: ThemeColorField.colorOf(selection),
            child: Text(
              '这一段模拟被鼠标选中的样子',
              style: TextStyle(
                color: fgFinal,
                fontSize: 13,
                fontFamily: 'Microsoft YaHei',
              ),
            ),
          ),
          const SizedBox(height: 14),
          // 引用块：左侧竖线 + 略降透明度的正文
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: subBg,
              border: Border(
                left: BorderSide(
                  color: fgFinal.withValues(alpha: 0.35),
                  width: 3,
                ),
              ),
            ),
            child: Text(
              '引用块：这一段用「次级文字」色 —— 说明、页脚、注释都是这个颜色。',
              style: TextStyle(
                color: subText,
                fontSize: 13,
                height: 1.6,
                fontFamily: 'Microsoft YaHei',
              ),
            ),
          ),
            const SizedBox(height: 12),
            // 卡片 + 表格头：都用「次级背景」，这是站点上出现最多的两块
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: subBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '表头 A',
                          style: TextStyle(
                            color: subText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Microsoft YaHei',
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '表头 B',
                          style: TextStyle(
                            color: subText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Microsoft YaHei',
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Container(
                      height: 1,
                      color: fgFinal.withValues(alpha: 0.2),
                    ),
                  ),
                  Text(
                    '卡片正文：这一块就是「次级背景」色，表格头、侧栏、提示框都用它。',
                    style: TextStyle(
                      color: fgFinal,
                      fontSize: 13,
                      height: 1.6,
                      fontFamily: 'Microsoft YaHei',
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          // 列表：每项前面一个小圆点，看正文色和缩进
          for (final item in ['列表第一项', '列表第二项'])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: fgFinal,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        color: fgFinal,
                        fontSize: 13,
                        height: 1.6,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          // 图片：用一个渐变块模拟照片，亮度滑块直接作用在它上面
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Opacity(
              opacity: (imageBrightness / 100).clamp(0.0, 1.0),
              child: Container(
                height: 90,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF4A6FA5),
                      const Color(0xFF9C5BD1),
                      const Color(0xFFD98A5B),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    '图片亮度 ${imageBrightness.round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFamily: 'Microsoft YaHei',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
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
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 84,
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
              value: value.clamp(20, 160),
              min: 20,
              max: 160,
              divisions: 140,
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
