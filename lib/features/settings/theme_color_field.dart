import 'package:flutter/material.dart';

/// 紧凑取色字段：一行「标签 + 色块 + 十六进制值」。
///
/// ── 为什么不直接把取色器铺在页面上 ──
///
/// 色相条 + 二维面板占掉 200 多像素，四个维度叠起来就变成一堵墙。
/// 成熟的做法（VS Code、Figma、浏览器 DevTools）都是：
/// 平时只显示一个色块，点开才弹出取色面板。
///
/// 所以这里是「触发块」，真正的取色在 [ThemeColorPickerDialog] 里。
class ThemeColorField extends StatelessWidget {
  const ThemeColorField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String label;

  /// #RRGGBB
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;

  static Color colorOf(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length != 6) return const Color(0xFF14161A);
    return Color(0xFF000000 | (int.tryParse(h, radix: 16) ?? 0x14161A));
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDialog<String>(
          context: context,
          builder: (_) => ThemeColorPickerDialog(
            label: label,
            initial: value,
          ),
        );
        if (picked != null && picked != value) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1E22),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF2C3038)),
        ),
        // 竖排：三列并排时横排会挤成一团，标签和色块上下叠才看得清。
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE3E5E8),
                fontSize: 12,
                fontFamily: 'Microsoft YaHei',
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 22,
                  height: 20,
                  decoration: BoxDecoration(
                    color: colorOf(value),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: const Color(0xFF4A5058),
                      width: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8A9099),
                      fontSize: 10.5,
                      fontFamily: 'Consolas',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹出式取色器。
class ThemeColorPickerDialog extends StatefulWidget {
  const ThemeColorPickerDialog({
    super.key,
    required this.label,
    required this.initial,
  });

  final String label;
  final String initial;

  @override
  State<ThemeColorPickerDialog> createState() => _ThemeColorPickerDialogState();
}

class _ThemeColorPickerDialogState extends State<ThemeColorPickerDialog> {
  late HSVColor _hsv;
  late TextEditingController _hex;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _hsv = _parse(widget.initial);
    _hex = TextEditingController(text: _toHex(_hsv));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static HSVColor _parse(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length != 6) return const HSVColor.fromAHSV(1, 220, 0.1, 0.1);
    return HSVColor.fromColor(
      Color(0xFF000000 | (int.tryParse(h, radix: 16) ?? 0x14161a)),
    );
  }

  static String _toHex(HSVColor hsv) {
    final c = hsv.toColor();
    String two(double v) =>
        (v * 255).round().toRadixString(16).padLeft(2, '0');
    return '#${two(c.r)}${two(c.g)}${two(c.b)}';
  }

  void _sync() {
    final hex = _toHex(_hsv);
    _syncing = true;
    _hex.text = hex;
    _syncing = false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1E22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF3A3F47)),
      ),
      title: Row(
        children: [
          Text(
            widget.label,
            style: const TextStyle(
              color: Color(0xFFE3E5E8),
              fontSize: 14,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
          const Spacer(),
          Container(
            width: 44,
            height: 28,
            decoration: BoxDecoration(
              color: _hsv.toColor(),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF4A5058)),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 色相条
            SizedBox(
              height: 24,
              child: LayoutBuilder(
                builder: (ctx, box) => GestureDetector(
                  onTapDown: (d) => _setHue(d.localPosition.dx / box.maxWidth),
                  onHorizontalDragUpdate: (d) =>
                      _setHue(d.localPosition.dx / box.maxWidth),
                  child: CustomPaint(
                    painter: _HuePainter(_hsv.hue),
                    size: Size(box.maxWidth, 24),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 饱和度 / 明度
            SizedBox(
              height: 160,
              child: LayoutBuilder(
                builder: (ctx, box) {
                  void pick(Offset p) {
                    final s = (p.dx / box.maxWidth).clamp(0.0, 1.0);
                    final v = 1 - (p.dy / box.maxHeight).clamp(0.0, 1.0);
                    setState(() {
                      _hsv = _hsv.withSaturation(s).withValue(v);
                      _sync();
                    });
                  }

                  return GestureDetector(
                    onTapDown: (d) => pick(d.localPosition),
                    onPanUpdate: (d) => pick(d.localPosition),
                    child: CustomPaint(
                      painter: _SvPainter(_hsv),
                      size: Size(box.maxWidth, 160),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hex,
              style: const TextStyle(
                color: Color(0xFFE3E5E8),
                fontSize: 13,
                fontFamily: 'Consolas',
              ),
              decoration: const InputDecoration(
                isDense: true,
                prefixText: '',
                hintText: '#RRGGBB',
                hintStyle: TextStyle(color: Color(0xFF6B7280)),
              ),
              onChanged: (v) {
                if (_syncing) return;
                final t = v.trim();
                if (t.length != 7 || !t.startsWith('#')) return;
                final parsed = int.tryParse(t.substring(1), radix: 16);
                if (parsed == null) return;
                setState(() {
                  _hsv = HSVColor.fromColor(Color(0xFF000000 | parsed));
                });
              },
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
          onPressed: () => Navigator.of(context).pop(_toHex(_hsv)),
          child: const Text(
            '确定',
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

  void _setHue(double ratio) {
    setState(() {
      _hsv = _hsv.withHue(ratio.clamp(0.0, 1.0) * 360);
      _sync();
    });
  }
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue);
  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final colors = <Color>[
      for (var i = 0; i <= 6; i++)
        HSVColor.fromAHSV(1, (i * 60).toDouble() % 360, 1, 1).toColor(),
    ];
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..shader = LinearGradient(colors: colors).createShader(rect),
    );
    final x = (hue / 360) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 2, 0, 4, size.height),
        const Radius.circular(1),
      ),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}

class _SvPainter extends CustomPainter {
  _SvPainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final base = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, base],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(rect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.transparent, Colors.black],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );
    final x = hsv.saturation * size.width;
    final y = (1 - hsv.value) * size.height;
    canvas.drawCircle(Offset(x, y), 7, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(x, y),
      7,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SvPainter old) =>
      old.hsv.hue != hsv.hue ||
      old.hsv.saturation != hsv.saturation ||
      old.hsv.value != hsv.value;
}
