import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'timetable_service.dart';

/// 本地通知。
///
/// 目前只有一件事：上课前提醒。课表抓下来之后，把接下来几天的课都换算成具体的
/// 提醒时间交给系统闹钟排进去，这样不用 App 常驻后台也能准点响。
class NotificationService {
  NotificationService._();

  /// 全局单例。
  static final NotificationService instance = NotificationService._();

  /// 提前多久提醒。
  static const Duration ahead = Duration(minutes: 20);

  /// 往后排几天。排太多系统有条数限制，也没必要。
  static const int daysAhead = 7;

  static const String _enabledKey = 'class_reminder_enabled';

  static const String _channelId = 'class_reminder';
  static const String _channelName = '上课提醒';
  static const String _channelDescription = '上课前提醒你去教室';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _ready = false;
  bool _enabled = true;

  /// 上课提醒开着没。
  bool get enabled => _enabled;

  /// 初始化，App 启动时调一次。
  Future<void> init() async {
    if (_ready) {
      return;
    }
    tzdata.initializeTimeZones();
    // 学校在东八区，直接用这个；拿设备时区要多引一个依赖，暂时不值当
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;

    try {
      final String? raw = await _storage.read(key: _enabledKey);
      if (raw != null && raw.isNotEmpty) {
        _enabled = raw == '1';
      }
    } catch (_) {}
  }

  /// 申请通知权限和精确闹钟权限。两个都得用户点头。
  Future<void> requestPermissions() async {
    await init();
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  /// 上课提醒的开关。打开时会顺手申请权限并重新排期。
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      await _storage.write(key: _enabledKey, value: value ? '1' : '0');
    } catch (_) {}

    if (!value) {
      await cancelAll();
      return;
    }
    await requestPermissions();
    final TimetableData? data = TimetableService.instance.data;
    if (data != null) {
      await scheduleClassReminders(data);
    }
  }

  /// 清掉所有已排的提醒。
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  /// 按课表把接下来几天的提醒排进系统。返回排了多少条。
  Future<int> scheduleClassReminders(TimetableData data) async {
    await init();
    await _plugin.cancelAll();
    if (!_enabled) {
      return 0;
    }

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    final DateTime today = DateTime(now.year, now.month, now.day);
    int id = 1;

    for (int offset = 0; offset <= daysAhead; offset++) {
      final DateTime day = today.add(Duration(days: offset));
      final int week = data.weekOf(day);
      if (week < 1 || (data.weekCount > 0 && week > data.weekCount)) {
        continue;
      }

      for (final CourseArrangement item in data.arrangements) {
        if (item.day != day.weekday || !item.inWeek(week)) {
          continue;
        }
        final String? range = ClassSchedule.rangeOf(
          item.startSection,
          item.endSection,
        );
        if (range == null) {
          continue;
        }
        final List<String> parts = range.split('-');
        if (parts.length != 2) {
          continue;
        }
        final DateTime? begin = _parseTime(day, parts.first);
        if (begin == null) {
          continue;
        }
        final DateTime remindAt = begin.subtract(ahead);
        if (!remindAt.isAfter(now.toLocal())) {
          continue;
        }

        final CourseInfo? course = item.courseIndex < data.courses.length
            ? data.courses[item.courseIndex]
            : null;
        final String name = course == null || course.name.isEmpty
            ? '课程'
            : course.name;
        final List<String> where = <String>[
          if (item.classroom != null) item.classroom!,
          if (item.teacher != null) item.teacher!,
        ];

        await _plugin.zonedSchedule(
          id: id++,
          title: '$name 快上课了',
          body: <String>[
            '${parts.first} 开始，还有 ${ahead.inMinutes} 分钟',
            if (where.isNotEmpty) where.join(' · '),
          ].join('\n'),
          scheduledDate: tz.TZDateTime.from(remindAt, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDescription,
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
    }
    return id - 1;
  }

  /// 把 "8:30" 落到具体某一天上。
  static DateTime? _parseTime(DateTime day, String hhmm) {
    final List<String> parts = hhmm.trim().split(':');
    if (parts.length != 2) {
      return null;
    }
    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    return DateTime(day.year, day.month, day.day, hour, minute);
  }
}
