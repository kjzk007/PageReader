import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/anchor_script.dart';

void main() {
  test('anchor script 不包含未转义的模板占位', () {
    expect(anchorBootstrapScript.contains(r'${'), isFalse,
        reason: 'bootstrap 脚本里不该有 Dart 插值占位');
    expect(positionReportScript.contains(r'${'), isFalse,
        reason: '上报脚本里不该有 Dart 插值占位');
  });

  test('anchor script 定义了 __pr.collect 与 __pr.restore', () {
    expect(anchorBootstrapScript.contains('window.__pr ='), isTrue);
    expect(anchorBootstrapScript.contains('collect: collect'), isTrue);
    expect(anchorBootstrapScript.contains('restore: restore'), isTrue);
  });

  test('上报脚本在缺 __prReport 时静默跳过', () {
    expect(
      positionReportScript.contains("typeof window.__prReport !== 'function'"),
      isTrue,
    );
  });

  test('两个脚本都能被 JS 引擎解析（括号配平）', () {
    for (final s in [anchorBootstrapScript, positionReportScript]) {
      final open = '{'.allMatches(s).length;
      final close = '}'.allMatches(s).length;
      expect(open, close, reason: '花括号必须配平');
    }
  });
}
