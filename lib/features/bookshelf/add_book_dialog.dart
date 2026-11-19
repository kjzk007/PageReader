import 'package:flutter/material.dart';

/// 加书对话框:粘贴 URL,推导 scope,选分组。
///
/// 返回 null 表示取消;否则返回用户确认的信息。
class AddBookDialog extends StatefulWidget {
  const AddBookDialog({super.key, required this.groups});

  final List<(String id, String name)> groups;

  @override
  State<AddBookDialog> createState() => _AddBookDialogState();
}

class AddBookResult {
  const AddBookResult({
    required this.url,
    required this.title,
    required this.scope,
    this.groupId,
  });

  final String url;
  final String title;

  /// 用户可编辑的范围前缀。默认按"输入的是页面就取目录"推导。
  final String scope;

  final String? groupId;
}

class _AddBookDialogState extends State<AddBookDialog> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  final _scope = TextEditingController();
  String? _groupId;
  String? _error;
  bool _scopeEdited = false;

  @override
  void initState() {
    super.initState();
    _url.addListener(_onUrlChanged);
    _scope.addListener(() {
      if (_scope.text != _derivedScope()) _scopeEdited = true;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    _scope.dispose();
    super.dispose();
  }

  String _derivedScope() {
    final raw = _url.text.trim();
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) return '';
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return '${uri.scheme}://${uri.host}';
    final last = segs.last;
    final looksFile = last.contains('.') && !last.startsWith('.');
    final kept = looksFile ? segs.sublist(0, segs.length - 1) : segs;
    if (kept.isEmpty) return '${uri.scheme}://${uri.host}';
    return Uri(scheme: uri.scheme, host: uri.host, pathSegments: kept)
        .toString();
  }

  void _onUrlChanged() {
    final derived = _derivedScope();
    if (!_scopeEdited) {
      _scope.text = derived;
    }
    // 标题留空则由上层从页面抓。
    setState(() {
      _error = _url.text.trim().isEmpty ? null : _validate();
    });
  }

  String? _validate() {
    final raw = _url.text.trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '需要一个完整地址,比如 https://example.com/docs';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return '只支持 http 和 https';
    }
    return null;
  }

  void _submit() {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final raw = _url.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '先粘贴一个地址');
      return;
    }
    Navigator.of(context).pop(
      AddBookResult(
        url: raw,
        title: _title.text.trim(),
        scope: _scope.text.trim().isEmpty ? _derivedScope() : _scope.text.trim(),
        groupId: _groupId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF191B1F),
      title: const Text(
        '加一本书',
        style: TextStyle(color: Color(0xFFF2F3F5), fontSize: 18),
      ),
      // 内容必须可滚动。
      //
      // 踩过的坑:原来直接放 Column,手机上弹出键盘后可用高度骤减,
      // 底部溢出 20px(黄黑条纹警告),"加入书架"按钮被顶出屏幕。
      // 换成 SingleChildScrollView 后,内容超出时可以滚动,
      // 用户的当前输入框也能 scrollIntoView 到可见区。
      content: SingleChildScrollView(
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _url,
              autofocus: true,
              style: const TextStyle(color: Color(0xFFE3E5E8), fontSize: 14),
              decoration: const InputDecoration(
                labelText: '地址',
                hintText: 'https://example.com/docs/intro',
                labelStyle: TextStyle(color: Color(0xFF7C8188), fontSize: 12),
                hintStyle: TextStyle(color: Color(0xFF4A4F56)),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _scope,
              style: const TextStyle(
                color: Color(0xFF9AA0A6),
                fontSize: 13,
                fontFamily: 'Consolas',
              ),
              decoration: const InputDecoration(
                labelText: '这本书的范围',
                helperText: '这个前缀下的页面都算同一本书,进度共享',
                helperStyle: TextStyle(color: Color(0xFF5F656C), fontSize: 11),
                labelStyle: TextStyle(color: Color(0xFF7C8188), fontSize: 12),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              style: const TextStyle(color: Color(0xFFE3E5E8), fontSize: 14),
              decoration: const InputDecoration(
                labelText: '书名(可留空)',
                labelStyle: TextStyle(color: Color(0xFF7C8188), fontSize: 12),
                helperText: '留空则使用域名和路径',
                helperStyle: TextStyle(color: Color(0xFF5F656C), fontSize: 11),
              ),
            ),
            if (widget.groups.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                '放进分组',
                style: TextStyle(color: Color(0xFF7C8188), fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('不分组', null),
                  for (final g in widget.groups) _chip(g.$2, g.$1),
                ],
              ),
            ],
          ],
        ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: Color(0xFF7C8188), fontSize: 13),
          ),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF5AC8FA),
            foregroundColor: const Color(0xFF0E0F12),
          ),
          child: const Text('加入书架'),
        ),
      ],
    );
  }

  Widget _chip(String label, String? id) {
    final selected = _groupId == id;
    return GestureDetector(
      onTap: () => setState(() => _groupId = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2A2D33) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF5AC8FA) : const Color(0xFF2A2D33),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected
                ? const Color(0xFF5AC8FA)
                : const Color(0xFF9AA0A6),
          ),
        ),
      ),
    );
  }
}
