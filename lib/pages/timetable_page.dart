import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/timetable_scripts.dart';
import '../services/timetable_service.dart';
import '../widgets/fetch_progress.dart';
import 'timetable_grid_page.dart';

/// 课表页。
///
/// 抓取走的是页面内的同源请求，所以底下常驻一个 WebView。它只在后台跑脚本，界面上
/// 不给它出镜的机会：抓取的时候盖一层转圈动画，平时盖内容。
class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  InAppWebViewController? _controller;

  static const List<String> _dayNames = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  Future<void> _start() async {
    final InAppWebViewController? controller = _controller;
    if (controller == null) {
      _toast('页面还没准备好，稍等一下再试');
      return;
    }
    final TimetableService service = TimetableService.instance;
    await service.fetch(controller);
    if (!mounted) {
      return;
    }
    final String? error = service.error;
    if (error != null) {
      _toast(error);
      return;
    }
    // 课表到手了，顺手把上课提醒排进系统闹钟
    final TimetableData? data = service.data;
    if (data != null) {
      await NotificationService.instance.scheduleClassReminders(data);
    }
  }

  /// 第一次进来且手上有登录态的话，自动抓一次。
  void _maybeAutoFetch() {
    final TimetableService service = TimetableService.instance;
    if (service.data != null ||
        service.loading ||
        service.autoAttempted ||
        service.error != null) {
      return;
    }
    if (!AuthService.instance.isLoggedIn) {
      return;
    }
    // 等这一帧画完再动手，免得在 build 过程中触发状态更新
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        unawaited(_start());
      }
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// [day] 为 null 时进去看整周，不带高亮。
  void _openGrid(int week, int? day) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            TimetableGridPage(initialWeek: week, focusDay: day),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课表'),
        actions: <Widget>[
          ListenableBuilder(
            listenable: TimetableService.instance,
            builder: (BuildContext context, Widget? child) {
              final TimetableService service = TimetableService.instance;
              return Row(
                children: <Widget>[
                  IconButton(
                    tooltip: '重新获取',
                    onPressed: service.loading ? null : _start,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: TimetableService.instance,
        // WebView 交给 child 缓存，免得状态一变就把它重建一遍
        child: _buildWebView(),
        builder: (BuildContext context, Widget? webView) {
          final TimetableService service = TimetableService.instance;
          return Stack(
            children: <Widget>[
              // 一直在树里待命，但只有抓取时才真的画出来。
              //
              // 不能只靠上面盖一层内容：Android 的 WebView 是个原生 View，页面跳转
              // 做过渡动画时它会短暂浮到 Flutter 内容之上，从日课表点进周课表的那一
              // 瞬就会露出学校的原始页面。Offstage 让它平时不参与绘制。
              Positioned.fill(
                child: Offstage(
                  offstage: !service.loading,
                  child: webView!,
                ),
              ),
              if (service.loading)
                Positioned.fill(
                  child: FetchProgress(status: service.status),
                )
              else
                Positioned.fill(
                  child: ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: _buildContent(service),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(TimetableScripts.appUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        thirdPartyCookiesEnabled: true,
        supportMultipleWindows: true,
        // 和培养方案一个道理：手机 UA 下应用里的接口会报「调用接口异常」
        userAgent: AuthService.desktopUserAgent,
        useWideViewPort: true,
        loadWithOverviewMode: true,
      ),
      onWebViewCreated: (InAppWebViewController controller) {
        _controller = controller;
        _maybeAutoFetch();
      },
      onCreateWindow:
          (InAppWebViewController controller, CreateWindowAction action) async {
            final WebUri? url = action.request.url;
            if (url == null) {
              return false;
            }
            await controller.loadUrl(urlRequest: URLRequest(url: url));
            return false;
          },
    );
  }

  Widget _buildContent(TimetableService service) {
    final TimetableData? data = service.data;
    if (data == null) {
      return _buildEmpty(service);
    }
    return Column(
      children: <Widget>[
        _buildDayHeader(data),
        const Divider(height: 1),
        Expanded(child: _buildTimeline(data)),
      ],
    );
  }

  Widget _buildEmpty(TimetableService service) {
    final bool loggedIn = AuthService.instance.isLoggedIn;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.calendar_month_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text('还没有课表数据', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              service.error ??
                  (loggedIn
                      ? '会复用「设置」里的登录状态，读取本学期的课表。'
                      : '先到「设置」里登录教务系统，才能读取课表。'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: loggedIn && !service.loading ? _start : null,
              icon: const Icon(Icons.download),
              label: const Text('获取课表'),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶上的当天信息，右边是周课表入口。
  Widget _buildDayHeader(TimetableData data) {
    final DateTime now = DateTime.now();
    final int week = data.weekOf(now);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '今天 · ${_dayNames[now.weekday - 1]} ${_formatDate(now)}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '第 $week 周',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _openGrid(week, now.weekday),
            icon: const Icon(Icons.grid_on, size: 18),
            label: const Text('周课表'),
          ),
        ],
      ),
    );
  }

  /// 今天的课，从上到下排成一条时间轴。
  Widget _buildTimeline(TimetableData data) {
    final DateTime now = DateTime.now();
    final int week = data.weekOf(now);
    final List<CourseArrangement> today =
        data
            .arrangementsOfWeek(week)
            .where((CourseArrangement item) => item.day == now.weekday)
            .toList()
          ..sort(
            (CourseArrangement a, CourseArrangement b) =>
                a.startSection.compareTo(b.startSection),
          );

    if (today.isEmpty) {
      return const Center(
        child: Text('今天没课', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 32),
      itemCount: today.length,
      itemBuilder: (BuildContext context, int index) => _buildTimelineItem(
        data,
        today[index],
        week,
        now.weekday,
        isLast: index == today.length - 1,
      ),
    );
  }

  /// 时间轴上的一节课：左边开始时间，中间圆点和竖线，右边课程卡片。
  Widget _buildTimelineItem(
    TimetableData data,
    CourseArrangement item,
    int week,
    int day, {
    required bool isLast,
  }) {
    final CourseInfo? course = item.courseIndex < data.courses.length
        ? data.courses[item.courseIndex]
        : null;
    final MaterialColor color =
        Colors.primaries[item.courseIndex % Colors.primaries.length];
    final String section = item.startSection == item.endSection
        ? '第${item.startSection}节'
        : '第${item.startSection}-${item.endSection}节';
    final String? timeRange = ClassSchedule.rangeOf(
      item.startSection,
      item.endSection,
    );
    final String beginTime = timeRange == null
        ? ''
        : timeRange.split('-').first;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 18, right: 8),
              child: Text(
                beginTime,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color.shade700,
                ),
              ),
            ),
          ),
          Column(
            children: <Widget>[
              const SizedBox(height: 20),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color.shade400,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: Colors.grey.shade300),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: InkWell(
                onTap: () => _openGrid(week, day),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: color.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border(
                      left: BorderSide(color: color.shade400, width: 3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        course == null || course.name.isEmpty
                            ? '（未知课程）'
                            : course.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: color.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        <String>[?timeRange, section].join(' · '),
                        style: TextStyle(fontSize: 12, color: color.shade800),
                      ),
                      if (item.classroom != null || item.teacher != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          <String>[
                            if (item.classroom != null) item.classroom!,
                            if (item.teacher != null) item.teacher!,
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: color.shade800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) => '${date.month}/${date.day}';
}
