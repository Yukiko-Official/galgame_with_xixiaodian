import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_service.dart';
import 'plan_scripts.dart';

/// 英语分级。
///
/// 培养方案里几套英语模块是并排的（初/中/高各一套），学生只用修其中一套，
/// 按这个选择把另外几套筛掉。
enum EnglishLevel {
  beginner('初级班', <String>['初级', '普通']),
  intermediate('中级班', <String>['中级']),
  advanced('高级班', <String>['高级']);

  const EnglishLevel(this.label, this.keywords);

  /// 选项上显示的名字。
  final String label;

  /// 模块名里出现这些词，就当它是这一档。
  final List<String> keywords;
}

/// 培养方案里的一门课。
class PlanCourse {
  const PlanCourse({
    this.code,
    this.name = '',
    this.credit,
    this.semester,
    this.examType,
    this.category,
    this.direction,
    this.college,
  });

  /// 课程号，页面里挂在带 title 的 span 上。
  final String? code;
  final String name;
  final num? credit;

  /// 开课学期，例如「第3学期」。
  final String? semester;

  /// 考试 / 考查。
  final String? examType;

  /// 必修 / 限选 / 任选 / 选修。
  final String? category;

  /// 专业方向。
  final String? direction;

  /// 开课学院。
  final String? college;

  factory PlanCourse.fromJson(Map<String, dynamic> json) => PlanCourse(
    code: json['code'] as String?,
    name: (json['name'] as String?) ?? '',
    credit: json['credit'] as num?,
    semester: json['semester'] as String?,
    examType: json['examType'] as String?,
    category: json['category'] as String?,
    direction: json['direction'] as String?,
    college: json['college'] as String?,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'code': code,
    'name': name,
    'credit': credit,
    'semester': semester,
    'examType': examType,
    'category': category,
    'direction': direction,
    'college': college,
  };
}

/// 培养方案树上的一个节点，对应一个课程组或模块。
class PlanNode {
  PlanNode({required this.id, required this.name, this.requiredCredit});

  final String id;
  final String name;

  /// 该模块要求的学分，页面上没写就是 null。
  final num? requiredCredit;

  /// 挂在这个节点下的课程，抓取过程中填充。
  List<PlanCourse> courses = <PlanCourse>[];

  final List<PlanNode> children = <PlanNode>[];

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'requiredCredit': requiredCredit,
    'courses': courses.map((PlanCourse c) => c.toJson()).toList(),
    'children': children.map((PlanNode c) => c.toJson()).toList(),
  };

  factory PlanNode.fromJson(Map<String, dynamic> json) {
    final PlanNode node = PlanNode(
      id: '${json['id']}',
      name: (json['name'] as String?) ?? '',
      requiredCredit: json['requiredCredit'] as num?,
    );
    final List<dynamic> courses =
        (json['courses'] as List<dynamic>?) ?? const <dynamic>[];
    node.courses = courses
        .map(
          (dynamic c) => PlanCourse.fromJson(c as Map<String, dynamic>),
        )
        .toList();
    final List<dynamic> children =
        (json['children'] as List<dynamic>?) ?? const <dynamic>[];
    for (final dynamic child in children) {
      node.children.add(PlanNode.fromJson(child as Map<String, dynamic>));
    }
    return node;
  }
}

/// 培养方案的抓取与保存。
///
/// 数据来源是一站式服务大厅里的「个人方案查询」应用，借助 WebView 已有的登录
/// Cookie 直接进去抓，不碰账号密码。
class PlanService extends ChangeNotifier {
  PlanService._();

  /// 全局单例，培养方案在整个 App 内共享一份。
  static final PlanService instance = PlanService._();

  /// 服务大厅首页，登录态就存在这个域下的 Cookie 里。
  static const String hallUrl = 'https://ehall.xidian.edu.cn/';

  /// 培养方案在服务大厅里的应用名。
  static const String appName = '个人方案查询';

  static final RegExp _titleRe = RegExp(r'''title=['"]([^'"]+)['"]''');
  static final RegExp _scoreRe = RegExp(r'要求学分[：:]\s*(\d+(?:\.\d+)?)');
  static final RegExp _spanTextRe = RegExp(r'>([^<]*)</span>');
  static final RegExp _tagRe = RegExp(r'<[^>]+>');

  /// 本地缓存 key 前缀，后面拼账号标识，数据按账号隔离。
  static const String _cachePrefix = 'plan_cache_';

  /// 勾选状态的 key 前缀。
  static const String _checkedPrefix = 'plan_checked_';

  /// 等级这类设置的 key 前缀。
  static const String _settingsPrefix = 'plan_settings_';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  PlanNode? _tree;
  bool _loading = false;
  String _status = '';
  String? _error;
  bool _autoFetchRequested = false;

  /// 当前数据所属的账号标识（学号，拿不到就用会话指纹）。
  String? _ownerKey;

  /// 已经勾上的课程，key 见 [courseKey]。
  final Set<String> _checked = <String>{};

  /// 收起来的模块，存的是节点 id。
  final Set<String> _collapsed = <String>{};

  /// 选中的英语分级。
  EnglishLevel _englishLevel = EnglishLevel.beginner;

  PlanNode? get tree => _tree;
  bool get loading => _loading;

  /// 当前进行到哪一步，用来显示进度。
  String get status => _status;
  String? get error => _error;

  /// 有人在等「登录完就自动抓一次」，界面看到这个就切到培养方案页。
  bool get autoFetchRequested => _autoFetchRequested;

  /// 登录成功后调用，界面会跳到培养方案页并自动开始抓取。
  void requestAutoFetch() {
    _autoFetchRequested = true;
    notifyListeners();
  }

  /// 取走这个请求，只生效一次。
  void consumeAutoFetchRequest() {
    _autoFetchRequested = false;
  }

  /// 登录成功（或 App 启动时恢复登录态）后调用。
  ///
  /// 数据和账号绑定：换了账号就清掉内存里的旧数据，再尝试恢复该账号上次
  /// 抓到的培养方案；还是同一个账号且数据都在就不动。
  Future<void> onLoginSuccess() async {
    final String? owner = _resolveOwner();
    if (owner == null) {
      return;
    }
    if (_ownerKey == owner && _tree != null) {
      return;
    }
    _ownerKey = owner;
    _tree = null;
    _error = null;
    _status = '';
    notifyListeners();

    await _loadChecked(owner);
    await _loadSettings(owner);
    final PlanNode? cached = await _loadCache(owner);
    if (cached != null && _ownerKey == owner) {
      _tree = cached;
      collapseToTopLevel();
      notifyListeners();
    }
  }

  /// 退出登录时调用：清掉内存数据。
  ///
  /// 本地缓存按账号保留，重新登录同一账号可以直接恢复，不用重新抓。
  void onLogout() {
    _ownerKey = null;
    _tree = null;
    _error = null;
    _status = '';
    _autoFetchRequested = false;
    _checked.clear();
    _collapsed.clear();
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

  Future<void> _saveCache(String owner, PlanNode tree) async {
    try {
      await _storage.write(
        key: '$_cachePrefix$owner',
        value: jsonEncode(tree.toJson()),
      );
    } catch (_) {
      // 缓存写失败不影响功能，下次重抓就是了
    }
  }

  Future<PlanNode?> _loadCache(String owner) async {
    try {
      final String? raw = await _storage.read(key: '$_cachePrefix$owner');
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PlanNode.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// 课程在勾选表里的稳定标识。
  static String courseKey(String nodeName, PlanCourse course) =>
      '${course.code ?? ''}|${course.name}|$nodeName';

  /// 这门课勾上了没。
  bool isChecked(String key) => _checked.contains(key);

  /// 这个模块收起来了没。
  bool isCollapsed(String nodeId) => _collapsed.contains(nodeId);

  /// 有没有模块是收着的，用来决定按钮写「全部展开」还是「全部收起」。
  bool get hasCollapsed => _collapsed.isNotEmpty;

  /// 收起 / 展开一个模块。
  void toggleCollapsed(String nodeId) {
    if (!_collapsed.remove(nodeId)) {
      _collapsed.add(nodeId);
    }
    notifyListeners();
  }

  /// 把所有带子模块的节点都收起来。
  void collapseAll() {
    void walk(PlanNode node) {
      if (node.children.isNotEmpty) {
        _collapsed.add(node.id);
      }
      for (final PlanNode child in node.children) {
        walk(child);
      }
    }

    final PlanNode? tree = _tree;
    if (tree != null) {
      walk(tree);
    }
    notifyListeners();
  }

  /// 默认把子模块都收起来，只留顶层那一层。
  ///
  /// 根节点（培养方案标题）不跟着收——收了整页就剩一行字。
  void collapseToTopLevel() {
    _collapsed.clear();
    final PlanNode? tree = _tree;
    if (tree == null) {
      return;
    }
    for (final PlanNode child in tree.children) {
      _collapseBranch(child);
    }
  }

  void _collapseBranch(PlanNode node) {
    if (node.children.isEmpty) {
      return;
    }
    _collapsed.add(node.id);
    for (final PlanNode child in node.children) {
      _collapseBranch(child);
    }
  }

  /// 全部展开。
  void expandAll() {
    if (_collapsed.isEmpty) {
      return;
    }
    _collapsed.clear();
    notifyListeners();
  }

  /// 修课进度：(已勾选的学分, 总学分)。
  ///
  /// 分母优先用培养方案自己标的那个数字（比如「智能科学与技术 157」里的 157）。
  /// 方案里有些模块是并列几个选项的（思政那类），照课程一门门累加会偏大。
  (num, num) get creditProgress {
    num checked = 0;
    num total = 0;

    void walk(PlanNode node) {
      // 被英语分级筛掉的模块不算进分母
      if (isNodeFilteredOut(node)) {
        return;
      }
      for (final PlanCourse course in node.courses) {
        final num credit = course.credit ?? 0;
        total += credit;
        if (isChecked(courseKey(node.name, course))) {
          checked += credit;
        }
      }
      for (final PlanNode child in node.children) {
        walk(child);
      }
    }

    final PlanNode? tree = _tree;
    if (tree != null) {
      walk(tree);
      final num? declared = tree.requiredCredit;
      if (declared != null && declared > 0) {
        total = declared;
      }
    }
    return (checked, total);
  }

  /// 当前选的英语分级。
  EnglishLevel get englishLevel => _englishLevel;

  /// 换一档英语分级，选择会按账号存起来。
  void setEnglishLevel(EnglishLevel level) {
    if (_englishLevel == level) {
      return;
    }
    _englishLevel = level;
    notifyListeners();
    unawaited(_saveSettings());
  }

  /// 这个模块是不是被英语分级筛掉了。
  ///
  /// 只认名字里写明档次的模块（「高级英语」「大学英语（普通）」这类）；
  /// 认不出来的留着，选修类的也留着——选修课三个班是同一套。
  bool isNodeFilteredOut(PlanNode node) {
    final String name = node.name;
    if (!name.contains('英语')) {
      return false;
    }
    // 选修部分是共用的，不跟着分档走
    if (name.contains('选修')) {
      return false;
    }
    final EnglishLevel? owner = _levelOfName(name);
    if (owner == null) {
      return false;
    }
    return owner != _englishLevel;
  }

  /// 名字里写着哪一档，认不出就返回 null。
  static EnglishLevel? _levelOfName(String name) {
    for (final EnglishLevel level in EnglishLevel.values) {
      for (final String keyword in level.keywords) {
        if (name.contains(keyword)) {
          return level;
        }
      }
    }
    return null;
  }

  Future<void> _saveSettings() async {
    final String? owner = _ownerKey ?? _resolveOwner();
    if (owner == null) {
      return;
    }
    try {
      await _storage.write(
        key: '$_settingsPrefix$owner',
        value: _englishLevel.name,
      );
    } catch (_) {}
  }

  Future<void> _loadSettings(String owner) async {
    _englishLevel = EnglishLevel.beginner;
    try {
      final String? raw = await _storage.read(key: '$_settingsPrefix$owner');
      if (raw == null || raw.isEmpty) {
        return;
      }
      for (final EnglishLevel level in EnglishLevel.values) {
        if (level.name == raw) {
          _englishLevel = level;
          break;
        }
      }
    } catch (_) {}
  }

  /// 勾上 / 取消勾选一门课，状态按账号存本地。
  Future<void> toggleChecked(String key) async {
    if (!_checked.remove(key)) {
      _checked.add(key);
    }
    notifyListeners();

    final String? owner = _ownerKey ?? _resolveOwner();
    if (owner == null) {
      return;
    }
    try {
      await _storage.write(
        key: '$_checkedPrefix$owner',
        value: jsonEncode(_checked.toList()),
      );
    } catch (_) {
      // 存不下就算了，不影响这次勾选
    }
  }

  Future<void> _loadChecked(String owner) async {
    _checked.clear();
    try {
      final String? raw = await _storage.read(key: '$_checkedPrefix$owner');
      if (raw == null || raw.isEmpty) {
        return;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final dynamic item in decoded) {
          _checked.add('$item');
        }
      }
    } catch (_) {}
  }

  /// 把培养方案写成 Markdown，课程是 `- [ ]` 那种可以打勾的列表。
  String toMarkdown() {
    final PlanNode? tree = _tree;
    if (tree == null) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    _writeMarkdownNode(buffer, tree, 1);
    return buffer.toString();
  }

  void _writeMarkdownNode(StringBuffer buffer, PlanNode node, int depth) {
    if (isNodeFilteredOut(node)) {
      return;
    }
    final String hashes = '#' * (depth > 6 ? 6 : depth);
    final String credit = node.requiredCredit == null
        ? ''
        : '（要求 ${node.requiredCredit} 学分）';
    buffer.writeln('$hashes ${node.name}$credit');
    buffer.writeln();

    for (final PlanCourse course in node.courses) {
      final String box = isChecked(courseKey(node.name, course)) ? 'x' : ' ';
      buffer.writeln('- [$box] ${course.name}${_courseTail(course)}');
    }
    if (node.courses.isNotEmpty) {
      buffer.writeln();
    }
    for (final PlanNode child in node.children) {
      _writeMarkdownNode(buffer, child, depth + 1);
    }
  }

  /// 课程后面跟的那串备注。
  static String _courseTail(PlanCourse course) {
    final List<String> parts = <String>[
      if (course.credit != null) '${course.credit} 学分',
      if (course.semester != null) course.semester!,
      if (course.category != null) course.category!,
      if (course.examType != null) course.examType!,
      if (course.college != null) course.college!,
    ];
    return parts.isEmpty ? '' : ' — ${parts.join(' · ')}';
  }

  /// 清掉本地缓存的数据，下次进页面重新抓。
  ///
  /// 勾选记录不动——那是自己一条条标出来的，不算缓存。
  Future<void> clearCache() async {
    _tree = null;
    _error = null;
    _status = '';
    _autoFetchRequested = false;
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
    _loading = true;
    _error = null;
    _tree = null;
    notifyListeners();

    try {
      _setStatus('正在打开培养方案…');
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(PlanScripts.appUrl)),
      );

      // 进来还不是培养方案页面，得再点一下那张方案卡片才出思维导图
      _setStatus('打开培养方案…');
      final bool cardReady = await _waitForPlanCard(controller);
      if (!cardReady) {
        final Object? pageDump = await controller.evaluateJavascript(
          source: PlanScripts.probeSearch(appName),
        );
        debugPrint('[培养方案] 没看到卡片，页面结构: $pageDump');
        throw StateError('进入应用后没看到培养方案卡片');
      }
      await controller.evaluateJavascript(
        source: PlanScripts.clickPlanCard,
      );

      _setStatus('等待培养方案加载…');
      final bool ready = await _waitFor(
        controller,
        PlanScripts.hasMindNode,
        timeout: const Duration(seconds: 60),
      );
      if (!ready) {
        throw StateError('培养方案页面没能加载出来');
      }
      await Future<void>.delayed(const Duration(seconds: 1));

      _setStatus('解析培养方案结构…');
      final Object? raw = await controller.evaluateJavascript(
        source: PlanScripts.exportTree,
      );
      final PlanNode root = _parseTree(raw);

      await _collectCourses(controller, root);

      _tree = root;
      // 内容太多，进来先只显示顶层模块
      collapseToTopLevel();

      // 抓完按账号落一份缓存，重启或重新登录后不用再抓一遍
      final String? owner = _ownerKey ?? _resolveOwner();
      if (owner != null) {
        _ownerKey = owner;
        await _saveCache(owner, root);
      }
    } catch (e) {
      _error = e is StateError ? e.message : '$e';
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

  /// 反复执行 [script]，直到它返回 true 或者超时。
  ///
  /// 页面跳转期间 JS 上下文可能还没准备好，执行报错算正常，跳过继续等。
  Future<bool> _waitFor(
    InAppWebViewController controller,
    String script, {
    required Duration timeout,
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await controller.evaluateJavascript(source: script) == true) {
          return true;
        }
      } catch (_) {}
      await Future<void>.delayed(interval);
    }
    return false;
  }

  /// 等「培养方案卡片」出现。
  ///
  /// 比 [_waitFor] 多做一件事：这一跳在首次加载（WebView 里还没缓存）时容易失败，
  /// 页面会停在 Chromium 的错误页上再也不动，干等到超时也没用——真机日志里就见过
  /// 页面变成 `chrome-error://chromewebdata/` 之后一直卡着。所以这里顺便盯着错误页，
  /// 遇到就重新加载一次（最多两次），而不是傻等。
  Future<bool> _waitForPlanCard(InAppWebViewController controller) async {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 60));
    int reloads = 0;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final Object? hit = await controller.evaluateJavascript(
          source: PlanScripts.hasPlanCard,
        );
        if (hit == true) {
          return true;
        }
        final String current = (await controller.getUrl())?.toString() ?? '';
        final bool stuck =
            current.startsWith('chrome-error://') || current == 'about:blank';
        if (stuck && reloads < 2) {
          reloads++;
          debugPrint('[培养方案] 页面停在「$current」，重新加载一次');
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri(PlanScripts.appUrl)),
          );
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// 逐层遍历整棵树，把每个节点下的课程抓下来。
  Future<void> _collectCourses(
    InAppWebViewController controller,
    PlanNode root,
  ) async {
    final List<PlanNode> pending = <PlanNode>[root];
    while (pending.isNotEmpty) {
      final PlanNode node = pending.removeAt(0);
      _setStatus('读取「${node.name}」的课程…');
      node.courses = await _fetchCourses(controller, node.id);
      pending.addAll(node.children);
    }
  }

  /// 选中 [nodeId] 对应的节点，然后读它下面的课程。
  Future<List<PlanCourse>> _fetchCourses(
    InAppWebViewController controller,
    String nodeId,
  ) async {
    try {
      await controller.evaluateJavascript(
        source: PlanScripts.selectNode(nodeId),
      );
    } catch (_) {
      return <PlanCourse>[];
    }

    // 侧边栏刷新是异步的，轮询到「结果稳定」为止：
    // 读到了课程，或者侧边栏里的行都属于这个节点（说明它确实没有课）。
    final DateTime deadline = DateTime.now().add(
      const Duration(milliseconds: 1500),
    );
    while (DateTime.now().isBefore(deadline)) {
      final Map<String, dynamic>? result = await _readCourses(controller, nodeId);
      if (result != null) {
        final List<dynamic> kzhs = (result['kzhs'] as List<dynamic>?) ?? const [];
        final List<dynamic> rows = (result['rows'] as List<dynamic>?) ?? const [];
        final bool settled =
            kzhs.isNotEmpty && kzhs.every((dynamic kzh) => kzh == nodeId);
        if (rows.isNotEmpty || settled) {
          return rows
              .map(
                (dynamic row) =>
                    PlanCourse.fromJson(row as Map<String, dynamic>),
              )
              .toList();
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return <PlanCourse>[];
  }

  Future<Map<String, dynamic>?> _readCourses(
    InAppWebViewController controller,
    String nodeId,
  ) async {
    try {
      final Object? raw = await controller.evaluateJavascript(
        source: PlanScripts.readCourses(nodeId),
      );
      final Object? decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  PlanNode _parseTree(Object? raw) {
    final Object? decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map || decoded['ok'] != true) {
      throw StateError('没能从页面里读出培养方案结构');
    }
    return _nodeFromJson(decoded['data'] as Map<String, dynamic>);
  }

  PlanNode _nodeFromJson(Map<String, dynamic> json) {
    final (String name, num? credit) = _parseTopic(json['topic'] as String?);
    final PlanNode node = PlanNode(
      id: '${json['id']}',
      name: name,
      requiredCredit: credit,
    );
    final List<dynamic> children =
        (json['children'] as List<dynamic>?) ?? const <dynamic>[];
    for (final dynamic child in children) {
      node.children.add(_nodeFromJson(child as Map<String, dynamic>));
    }
    return node;
  }

  /// 把节点的 HTML 标题拆成「名称 + 要求学分」。
  (String, num?) _parseTopic(String? topic) {
    if (topic == null || topic.isEmpty) {
      return ('', null);
    }
    final RegExpMatch? title = _titleRe.firstMatch(topic);
    if (title == null) {
      final RegExpMatch? span = _spanTextRe.firstMatch(topic);
      if (span == null) {
        return (topic.replaceAll(_tagRe, '').trim(), null);
      }
      return (span.group(1)!.trim(), _creditOf(topic));
    }
    return (title.group(1)!.trim(), _creditOf(topic));
  }

  num? _creditOf(String topic) {
    final RegExpMatch? match = _scoreRe.firstMatch(topic);
    if (match == null) {
      return null;
    }
    final double value = double.parse(match.group(1)!);
    return value == value.truncateToDouble() ? value.toInt() : value;
  }
}
