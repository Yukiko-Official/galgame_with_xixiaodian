import 'package:flutter_test/flutter_test.dart';

import 'package:galgame_with_xixiaodian/main.dart';

void main() {
  testWidgets('启动后停在助手页，底部四个入口都在', (WidgetTester tester) async {
    await tester.pumpWidget(const XidianHelperApp());
    await tester.pumpAndSettle();

    // 底部导航的四个入口
    expect(find.text('课表'), findsOneWidget);
    expect(find.text('培养方案'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    // 「助手」会出现两次：顶部标题和底部入口
    expect(find.text('助手'), findsNWidgets(2));

    // 默认显示助手页（看输入框在不在）
    expect(find.text('问点什么…'), findsOneWidget);
  });

  testWidgets('点击底部入口可以切换页面', (WidgetTester tester) async {
    await tester.pumpWidget(const XidianHelperApp());
    await tester.pumpAndSettle();

    // 课表和培养方案页里内嵌了 WebView，测试环境没有平台实现，只测纯 Dart 的页面
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('登录教务系统'), findsOneWidget);
  });
}
