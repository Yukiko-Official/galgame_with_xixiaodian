import 'package:flutter/material.dart';

/// 抓取数据时的全屏等待动画。
///
/// 课表和培养方案都是「在后台的 WebView 里跑脚本把数据抓下来」，过程中不该让学校的
/// 原始页面露出来，所以盖一层背景色加转圈，下面顺带说明进行到哪一步。
class FetchProgress extends StatelessWidget {
  const FetchProgress({super.key, required this.status});

  /// 当前进行到哪一步；空的话显示一句兜底的。
  final String status;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                status.isEmpty ? '正在获取…' : status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
