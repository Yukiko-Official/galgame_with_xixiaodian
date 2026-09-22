import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_service.dart';
import 'timetable_scripts.dart';

/// 一个大节，也就是连着上的两小节。
class ClassSlot {
  const ClassSlot({
    required this.startSection,
    required this.endSection,
    required this.beginTime,
    required this.endTime,
  });

  final int startSection;
  final int endSection;
  final String beginTime;
  final String endTime;
}

/// 作息时间表。
///
/// 学校偶尔会调课表时间，对不上就改这里。
class ClassSchedule {
  ClassSchedule._();

  static const List<ClassSlot> slots = <ClassSlot>[
    ClassSlot(
      startSection: 1,
      endSection: 2,
      beginTime: '8:30',
      endTime: '10:05',
    ),
    ClassSlot(
      startSection: 3,
      endSection: 4,
      beginTime: '10:25',
      endTime: '12:00',
    ),
    ClassSlot(
      startSection: 5,
      endSection: 6,
      beginTime: '14:00',
      endTime: '15:35',
    ),
    ClassSlot(
      startSection: 7,
      endSection: 8,
      beginTime: '15:55',
      endTime: '17:30',
    ),
    ClassSlot(
      startSection: 9,
      endSection: 10,
      beginTime: '19:00',
      endTime: '20:35',
    ),
  ];

  /// [start] 到 [end] 节的上课时间，比如 `8:30-10:05`；查不到返回 null。
  ///
  /// 跨大节的课（比如 1-4 节）会从第一个大节的开始时间算到最后一个大节的结束。
  static String? rangeOf(int start, int end) {
    ClassSlot? first;
    ClassSlot? last;
    for (final ClassSlot slot in slots) {
      if (start >= slot.startSection && start <= slot.endSection) {
        first = slot;
      }
      if (end >= slot.startSection && end <= slot.endSection) {
        last = slot;
      }
    }
    if (first == null || last == null) {
      return null;
    }
    return '${first.beginTime}-${last.endTime}';
  }
}

/// 一门课的基本信息，同名的多个教学班靠课程号 + 课序号区分。
class CourseInfo {
  const CourseInfo({required this.name, this.code, this.number});

  final String name;

  /// 课程号。
  final String? code;

  /// 课序号，也就是教学班号。
  final String? number;

  bool sameAs(CourseInfo other) =>
      name == other.name && code == other.code && number == other.number;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'code': code,
    'number': number,
  };

  factory CourseInfo.fromJson(Map<String, dynamic> json) => CourseInfo(
    name: '${json['name'] ?? ''}',
    code: json['code'] as String?,
    number: json['number'] as String?,
  );
}

/// 一段排课：某门课在星期几的第几节到第几节、哪些周上。
class CourseArrangement {
  const CourseArrangement({
    required this.courseIndex,
    required this.day,
    required this.startSection,
    required this.endSection,
    required this.weekBits,
    this.classroom,
    this.teacher,
  });

  /// 指向 [TimetableData.courses] 里的下标。
  final int courseIndex;

  /// 星期几，1 是周一。
  final int day;
  final int startSection;
  final int endSection;

  /// 周次位图，第 i 个字符是 `1` 表示第 i+1 周要上课。
  final String weekBits;

  final String? classroom;
  final String? teacher;

  bool inWeek(int week) =>
      week >= 1 && week <= weekBits.length && weekBits[week - 1] == '1';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'courseIndex': courseIndex,
    'day': day,
    'startSection': startSection,
    'endSection': endSection,
    'weekBits': weekBits,
    'classroom': classroom,
    'teacher': teacher,
  };

  factory CourseArrangement.fromJson(Map<String, dynamic> json) =>
      CourseArrangement(
        courseIndex: (json['courseIndex'] as num?)?.toInt() ?? 0,
        day: (json['day'] as num?)?.toInt() ?? 1,
        startSection: (json['startSection'] as num?)?.toInt() ?? 1,
        endSection: (json['endSection'] as num?)?.toInt() ?? 1,
        weekBits: '${json['weekBits'] ?? ''}',
        classroom: json['classroom'] as String?,
        teacher: json['teacher'] as String?,
      );
}

/// 一个学期的完整课表。
class TimetableData {
  const TimetableData({
    required this.semesterCode,
    required this.termStart,
    required this.courses,
    required this.arrangements,
    required this.notArranged,
    required this.weekCount,
  });

  /// 学期代码，形如 `2025-2026-1`。
  final String semesterCode;

  /// 第一周的周一。
  final DateTime termStart;

  final List<CourseInfo> courses;
  final List<CourseArrangement> arrangements;

  /// 没排进课表的课，单独列出来。
  final List<CourseInfo> notArranged;

  /// 学期总周数。
  final int weekCount;

  bool get isEmpty => arrangements.isEmpty && notArranged.isEmpty;

  /// [date] 落在第几周，超出范围会夹到 [1, weekCount]。
  int weekOf(DateTime date) {
    final int days = date.difference(termStart).inDays;
    if (days < 0) {
      return 1;
    }
    final int week = days ~/ 7 + 1;
    if (weekCount > 0 && week > weekCount) {
      return weekCount;
    }
    return week;
  }

  /// [week] 这一周的周一。
  DateTime mondayOf(int week) =>
      termStart.add(Duration(days: (week - 1) * 7));

  /// 某一周实际要上的课。
  List<CourseArrangement> arrangementsOfWeek(int week) =>
      arrangements.where((CourseArrangement a) => a.inWeek(week)).toList();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'semesterCode': semesterCode,
    'termStart': termStart.toIso8601String(),
    'courses': courses.map((CourseInfo c) => c.toJson()).toList(),
    'arrangements': arrangements
        .map((CourseArrangement a) => a.toJson())
        .toList(),
    'notArranged': notArranged.map((CourseInfo c) => c.toJson()).toList(),
    'weekCount': weekCount,
  };

  factory TimetableData.fromJson(Map<String, dynamic> json) {
    final List<dynamic> courses =
        (json['courses'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> arrangements =
        (json['arrangements'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> notArranged =
        (json['notArranged'] as List<dynamic>?) ?? const <dynamic>[];
    return TimetableData(
      semesterCode: '${json['semesterCode'] ?? ''}',
      termStart:
          DateTime.tryParse('${json['termStart'] ?? ''}') ?? DateTime.now(),
      courses: courses
          .map((dynamic c) => CourseInfo.fromJson(c as Map<String, dynamic>))
          .toList(),
      arrangements: arrangements
          .map(
            (dynamic a) =>
                CourseArrangement.fromJson(a as Map<String, dynamic>),
          )
          .toList(),
      notArranged: notArranged
          .map((dynamic c) => CourseInfo.fromJson(c as Map<String, dynamic>))
          .toList(),
      weekCount: (json['weekCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 课表的抓取与保存。
///
/// 数据来自一站式服务大厅里的课表应用，走的是 WebView 页面内的同源请求，
/// 直接复用登录时拿到的 Cookie。
class TimetableService extends ChangeNotifier {
  TimetableService._();

  /// 全局单例，课表在整个 App 内共享一份。
  static final TimetableService instance = TimetableService._();

  /// 本地缓存 key 前缀，后面拼账号标识，数据按账号隔离。
  static const String _cachePrefix = 'timetable_cache_';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  TimetableData? _data;
  bool _loading = false;
  String _status = '';
  String? _error;
  bool _autoAttempted = false;
  String? _ownerKey;

  TimetableData? get data => _data;
  bool get loading => _loading;

  /// 当前进行到哪一步，用来显示进度。
  String get status => _status;
  String? get error => _error;

  /// 已经自动尝试过一次了，避免每次切回课表页都重抓。
  bool get autoAttempted => _autoAttempted;

  /// 登录成功（或 App 启动时恢复登录态）后调用，数据和账号绑定。
  Future<void> onLoginSuccess() async {
    final String? owner = _resolveOwner();
    if (owner == null) {
      return;
    }
    if (_ownerKey == owner && _data != null) {
      return;
    }
    _ownerKey = owner;
    _data = null;
    _error = null;
    _status = '';
    _autoAttempted = false;
    notifyListeners();

    final TimetableData? cached = await _loadCache(owner);
    if (cached != null && _ownerKey == owner) {
      _data = cached;
      notifyListeners();
    }
  }

  /// 退出登录时调用：清掉内存数据，本地缓存按账号留着。
  void onLogout() {
    _ownerKey = null;
    _data = null;
    _error = null;
    _status = '';
    _autoAttempted = false;
    notifyListeners();
  }

  /// 当前应该归属的账号标识。
  String? _resolveOwner() {
    final AuthService auth = AuthService.instance;
    final String? account = auth.account;
    if (account != null && account.isNotEmpty) {
      return account;
    }
    final String? session = auth.sessionKey;
    return session == null ? null : 'sess_$session';
  }

  Future<void> _saveCache(String owner, TimetableData data) async {
    try {
      await _storage.write(
        key: '$_cachePrefix$owner',
        value: jsonEncode(data.toJson()),
      );
    } catch (_) {
      // 缓存写失败不影响功能，下次重抓就是了
    }
  }

  Future<TimetableData?> _loadCache(String owner) async {
    try {
      final String? raw = await _storage.read(key: '$_cachePrefix$owner');
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return TimetableData.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// 清掉本地缓存的数据，下次进页面重新抓。
  Future<void> clearCache() async {
    _data = null;
    _error = null;
    _status = '';
    _autoAttempted = false;
    notifyListeners();
    try {
      final Map<String, String> all = await _storage.readAll();
      for (final String key in all.keys.toList()) {
        if (key.startsWith(_cachePrefix)) {
          await _storage.delete(key: key);
        }
      }
    } catch (_) {}
  }

  /// 在 [controller] 里完整走一遍抓取流程。
  Future<void> fetch(InAppWebViewController controller) async {
    if (_loading) {
      return;
    }
    _loading = true;
    _error = null;
    _autoAttempted = true;
    notifyListeners();

    try {
      final String? account = AuthService.instance.account;
      if (account == null || account.isEmpty) {
        throw StateError(
          '还没拿到学号。请到「设置」里先退出登录，再重新登录一次——'
          '之前那次登录被旧 Cookie 直接放行了，没经过登录页，学号就没记下来。',
        );
      }

      _setStatus('正在打开课表应用…');
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(TimetableScripts.appUrl)),
      );

      _setStatus('检查登录状态…');
      if (!await _waitForPageReady(controller)) {
        throw StateError('打不开课表应用，可能是登录已过期，请重新登录');
      }

      _setStatus('读取当前学期…');
      final String semester = await _pollString(
        controller,
        TimetableScripts.currentSemester,
      );
      if (semester.isEmpty) {
        final Object? why = await controller.evaluateJavascript(
          source: TimetableScripts.probeSemester,
        );
        debugPrint('[课表] 学期接口探测: $why');
        throw StateError('没读到当前学期信息');
      }
      debugPrint('[课表] 当前学期: $semester');

      _setStatus('读取学期开始日期…');
      final String rawTermStart = await _pollString(
        controller,
        TimetableScripts.termStart(semester),
      );
      debugPrint('[课表] 开学日: $rawTermStart');

      _setStatus('正在读取课表…');
      final Map<String, dynamic>? table = await _requestJson(
        controller,
        TimetableScripts.classTable(semester, account),
      );
      if (table == null) {
        throw StateError('课表接口没有响应');
      }
      debugPrint(
        '[课表] xskcb 响应: ok=${table['ok']} error=${table['error']}',
      );
      if (table['ok'] != true) {
        if (table['unpublished'] == true) {
          // 学期还没排完课，给个空课表就行，不算出错
          _data = TimetableData(
            semesterCode: semester,
            termStart: _parseDate(rawTermStart) ?? DateTime.now(),
            courses: const <CourseInfo>[],
            arrangements: const <CourseArrangement>[],
            notArranged: const <CourseInfo>[],
            weekCount: 0,
          );
          return;
        }
        throw StateError('${table['error'] ?? '课表获取失败'}');
      }

      _setStatus('读取未排课课程…');
      final Map<String, dynamic>? extras = await _requestJson(
        controller,
        TimetableScripts.notArranged(semester, account),
      );

      _setStatus('整理课表…');
      final List<dynamic> rawRows =
          (table['rows'] as List<dynamic>?) ?? const <dynamic>[];
      debugPrint('[课表] 拿到 ${rawRows.length} 条排课');
      if (rawRows.isNotEmpty) {
        debugPrint('[课表] 首条字段: ${rawRows.first}');
      }
      final TimetableData built = _build(
        semester,
        rawTermStart,
        rawRows,
        (extras?['rows'] as List<dynamic>?) ?? const <dynamic>[],
      );
      _data = built;

      final String? owner = _ownerKey ?? _resolveOwner();
      if (owner != null) {
        _ownerKey = owner;
        await _saveCache(owner, built);
      }
    } catch (e) {
      _error = e is StateError ? e.message : '$e';
      debugPrint('[课表] 抓取失败: $_error');
    } finally {
      _loading = false;
      _status = '';
      notifyListeners();
    }
  }

  void _setStatus(String text) {
    _status = text;
    notifyListeners();
  }

  /// 等页面跳转结束。被弹回统一身份认证页说明登录态没了。
  Future<bool> _waitForPageReady(
    InAppWebViewController controller, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final WebUri? url = await controller.getUrl();
        if (url != null && url.host.contains('ids.xidian.edu.cn')) {
          return false;
        }
        if (url != null && url.host.endsWith('xidian.edu.cn')) {
          final Object? ready = await controller.evaluateJavascript(
            source: 'document.readyState',
          );
          if (ready == 'complete') {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            return true;
          }
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  /// 反复执行 [script]，直到它返回非空字符串或者超时。
  ///
  /// 页面刚跳转完时 JS 上下文可能还没准备好，报错算正常，跳过继续等。
  Future<String> _pollString(
    InAppWebViewController controller,
    String script, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final Object? result = await controller.evaluateJavascript(
          source: script,
        );
        if (result is String && result.isNotEmpty) {
          return result;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return '';
  }

  /// 执行一个返回 JSON 字符串的脚本。
  Future<Map<String, dynamic>?> _requestJson(
    InAppWebViewController controller,
    String script, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final String raw = await _pollString(controller, script, timeout: timeout);
    if (raw.isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  /// 把接口返回的行整理成课表数据。
  TimetableData _build(
    String semesterCode,
    String rawTermStart,
    List<dynamic> rows,
    List<dynamic> notArrangedRows,
  ) {
    final List<CourseInfo> courses = <CourseInfo>[];
    final List<CourseArrangement> arrangements = <CourseArrangement>[];
    int weekCount = 0;

    for (final dynamic raw in rows) {
      if (raw is! Map) {
        continue;
      }
      final Map<String, dynamic> row = Map<String, dynamic>.from(raw);
      final CourseInfo info = CourseInfo(
        name: '${row['KCM'] ?? ''}',
        code: _text(row['KCH']),
        number: _text(row['KXH']),
      );
      int index = courses.indexWhere((CourseInfo c) => c.sameAs(info));
      if (index < 0) {
        courses.add(info);
        index = courses.length - 1;
      }

      final String weekBits = '${row['SKZC'] ?? ''}';
      if (weekBits.length > weekCount) {
        weekCount = weekBits.length;
      }
      arrangements.add(
        CourseArrangement(
          courseIndex: index,
          day: _toInt(row['SKXQ'], 1),
          startSection: _toInt(row['KSJC'], 1),
          endSection: _toInt(row['JSJC'], 1),
          weekBits: weekBits,
          classroom: _text(row['JASMC']),
          teacher: _text(row['SKJS']),
        ),
      );
    }

    final List<CourseInfo> notOnTable = <CourseInfo>[];
    for (final dynamic raw in notArrangedRows) {
      if (raw is! Map) {
        continue;
      }
      final Map<String, dynamic> row = Map<String, dynamic>.from(raw);
      notOnTable.add(
        CourseInfo(
          name: '${row['KCM'] ?? ''}',
          code: _text(row['KCH']),
          number: _text(row['KXH']),
        ),
      );
    }

    return TimetableData(
      semesterCode: semesterCode,
      termStart: _parseDate(rawTermStart) ?? DateTime.now(),
      courses: courses,
      arrangements: arrangements,
      notArranged: notOnTable,
      weekCount: weekCount,
    );
  }

  static DateTime? _parseDate(String text) {
    if (text.isEmpty) {
      return null;
    }
    final DateTime? parsed = DateTime.tryParse(text.replaceFirst(' ', 'T'));
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static int _toInt(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('${value ?? ''}') ?? fallback;
  }

  static String? _text(Object? value) {
    if (value == null) {
      return null;
    }
    final String text = '$value'.trim();
    return text.isEmpty ? null : text;
  }
}
