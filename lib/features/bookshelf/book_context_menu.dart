import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/models.dart';
import '../../core/domain/theme_preset.dart';
import '../../core/services/settings.dart';
import '../settings/theme_settings_page.dart';

/// 书架右键菜单。
///
/// ── 为什么不用 showMenu ──
///
/// 书香右键里有一项「主题设置」，点开后要在旁边列出所有主题。
/// showMenu 弹出的是一层独立的模态菜单，再开一层会把第一层关掉 ——
/// 用户刚点的那个位置瞬间消失，接着在旁边冒出新菜单，很割裂。
///
/// 所以这里自己搭 Overlay：主菜单和子菜单都是同一个浮层里的两个区块，
/// 展开子菜单时主菜单原样留着。
class BookContextMenu extends StatefulWidget {
  const BookContextMenu({
    super.key,
    required this.book,
    required this.position,
    required this.onPick,
  });

  final Book book;
  final Offset position;

  /// 选中项。'preset:' 开头表示选了主题；null 表示点空白取消。
  final void Function(String? action) onPick;

  @override
  State<BookContextMenu> createState() => _BookContextMenuState();
}

class _BookContextMenuState extends State<BookContextMenu> {
  bool _showPresets = false;
  bool _presetsLeft = false;

  static const double _menuWidth = 176;
  static const double _submenuWidth = 200;
  static const double _itemHeight = 38;

  @override
  Widget build(BuildContext context) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final size = overlay.size;
    final book = widget.book;
    // Overlay 的 builder 里拿不到 ConsumerState 的 ref（不在同一棵树上），
    // 所以直接取容器。测试环境没有 ProviderScope 时退回内置预设。
    List<ThemePreset> presets;
    try {
      presets = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(themePresetsProvider);
    } catch (_) {
      presets = const [ThemePreset.builtinDark];
    }

    // 位置收敛：菜单不能跑出屏幕。
    final left = widget.position.dx
        .clamp(4.0, (size.width - _menuWidth - 4).clamp(4.0, size.width));
    final top = widget.position.dy
        .clamp(4.0, (size.height - 320).clamp(4.0, size.height));

    // 子菜单默认在右侧；右侧放不下就翻到左边。
    _presetsLeft = left + _menuWidth + _submenuWidth + 8 > size.width;
    final subLeft = _presetsLeft
        ? (left - _submenuWidth - 4).clamp(4.0, size.width)
        : left + _menuWidth + 4;
    final presetCount = presets.length + 1;
    final subHeight = presetCount * _itemHeight + 8;
    final subTop = (top + 4 * _itemHeight - 4)
        .clamp(4.0, (size.height - subHeight - 4).clamp(4.0, size.height));

    return Stack(
      children: [
        // 点空白处关闭。opaque 吞掉点击，避免穿透到书架卡片。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onPick(null),
            onSecondaryTap: () => widget.onPick(null),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: _MenuPanel(
            width: _menuWidth,
            children: [
              _Item(
                label: '打开',
                onTap: () => widget.onPick('open'),
                onEnter: () => _setPresets(false),
              ),
              _Item(
                label: '改名',
                onTap: () => widget.onPick('rename'),
                onEnter: () => _setPresets(false),
              ),
              _Item(
                label: '改范围',
                onTap: () => widget.onPick('scope'),
                onEnter: () => _setPresets(false),
              ),
              _Item(
                label: '移动到分类',
                onTap: () => widget.onPick('move'),
                onEnter: () => _setPresets(false),
              ),
              // 主题设置：点它或悬停它都会展开右侧列表，主菜单不关。
              _Item(
                label: '主题设置',
                trailing: const Icon(
                  Icons.chevron_right,
                  size: 15,
                  color: Color(0xFF8A9099),
                ),
                highlight: _showPresets,
                onTap: () {
                  _setPresets(!_showPresets);
                },
                onEnter: () => _setPresets(true),
              ),
              _Item(
                label: '复制地址',
                onTap: () => widget.onPick('copy'),
                onEnter: () => _setPresets(false),
              ),
              const _Divider(),
              _Item(
                label: '从书架移除',
                danger: true,
                onTap: () => widget.onPick('delete'),
                onEnter: () => _setPresets(false),
              ),
            ],
          ),
        ),
        if (_showPresets)
          Positioned(
            left: subLeft,
            top: subTop,
            child: _MenuPanel(
              width: _submenuWidth,
              children: [
                _Item(
                  label: '默认',
                  swatch: null,
                  selected: book.presetId == null,
                  onTap: () => widget.onPick('preset:$kDefaultPresetId'),
                ),
                const _Divider(),
                for (final p in presets)
                  _Item(
                    label: p.name,
                    swatch: Color(p.backgroundArgb),
                    selected: book.presetId == p.id,
                    onTap: () => widget.onPick('preset:${p.id}'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  void _setPresets(bool v) {
    if (_showPresets != v) setState(() => _showPresets = v);
  }
}

class _MenuPanel extends StatelessWidget {
  const _MenuPanel({required this.width, required this.children});

  final double width;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1E22),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF3A3F47), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _Item extends StatefulWidget {
  const _Item({
    required this.label,
    this.onTap,
    this.onEnter,
    this.trailing,
    this.swatch,
    this.selected = false,
    this.highlight = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onEnter;
  final Widget? trailing;
  final Color? swatch;
  final bool selected;
  final bool highlight;
  final bool danger;

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.highlight || _hovered;
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onEnter?.call();
      },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: active ? const Color(0xFF2A2E35) : Colors.transparent,
          child: Row(
            children: [
              if (widget.swatch != null) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: widget.swatch,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: const Color(0xFF3A3F47)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.danger
                        ? const Color(0xFFFF6B6B)
                        : const Color(0xFFE3E5E8),
                    fontSize: 13,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
              ),
              if (widget.selected)
                const Icon(Icons.check, size: 15, color: Color(0xFF5AC8FA)),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: const Color(0xFF2C3038),
    );
  }
}