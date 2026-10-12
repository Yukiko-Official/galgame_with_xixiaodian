import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:galgame_with_xixiaodian/widgets/f7d_loading.dart';

void main() {
  testWidgets('加载动画能循环绘制，不抛异常', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: F7dLoading()))),
    );

    // 跨过「张开」和「收回」两段，顺便让整体转过一个 90° 循环
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.byType(F7dLoading), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 卸掉，免得 repeat() 起的 ticker 留到测试结束
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
