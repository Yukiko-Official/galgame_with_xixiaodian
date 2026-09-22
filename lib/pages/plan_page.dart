import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/auth_service.dart';
import '../services/plan_scripts.dart';
import '../services/plan_service.dart';

/// 培养方案页。
///
/// 抓取过程要在真实页面里点来点去，所以底下常驻一个 WebView：平时被内容盖住，
/// 抓的时候露出来，方便看出卡在哪一步。
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  InAppWebViewController? _controller;

  /// 临时把 WebView 露出来，方便手动操作看看到底卡在哪。
  bool _showWeb = false;

  Future<void> _start() async {
    final InAppWebViewController? controller = _controller;
    if (controller == null) {
      _toast('页面还没准备好，稍等一下再试');
      return;
    }
    final PlanService service = PlanService.instance;
    await service.fetch(controller);
    if (!mounted) {
      return;
    }
    final String? error = service.error;
    if (error != null) {
      _toast(error);
    }
  }

  /// 刚登录完切进来的话，自动开始抓取；已经有数据就只切页，不重抓。
  void _maybeAutoFetch() {
    if (!PlanService.instance.autoFetchRequested) {
      return;
    }
    PlanService.instance.consumeAutoFetchRequest();
    if (PlanService.instance.tree != null) {
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

  /// 诊断用：把当前页面结构写进日志，方便定位选择器。
  Future<void> _dumpPage() async {
    final InAppWebViewController? controller = _controller;
    if (controller == null) {
      return;
    }
    final Object? dump = await controller.evaluateJavascript(
      source: PlanScripts.probeSearch(PlanService.appName),
    );
    debugPrint('[培养方案] 当前页面结构: $dump');
    if (mounted) {
      _toast('页面结构已写进日志');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('培养方案'),
        actions: <Widget>[
          IconButton(
            tooltip: _showWeb ? '隐藏网页' : '显示网页（可手动操作）',
            onPressed: () => setState(() => _showWeb = !_showWeb),
            icon: Icon(_showWeb ? Icons.visibility_off : Icons.visibility),
          ),
          IconButton(
            tooltip: '把当前页面结构写进日志',
            onPressed: _dumpPage,
            icon: const Icon(Icons.bug_report_outlined),
          ),
          ListenableBuilder(
            listenable: PlanService.instance,
            builder: (BuildContext context, Widget? child) {
              final PlanService service = PlanService.instance;
              if (service.tree == null) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: '重新获取',
                onPressed: service.loading ? null : _start,
                icon: const Icon(Icons.refresh),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: PlanService.instance,
        // WebView 交给 child 缓存，不然每次勾选 / 折叠都要把它重建一遍
        child: _buildWebView(),
        builder: (BuildContext context, Widget? webView) {
          final PlanService service = PlanService.instance;
          return Stack(
            children: <Widget>[
              // 一直在最底下待命，抓取时才露出来
              Positioned.fill(child: webView!),
              if (!service.loading && !_showWeb)
                Positioned.fill(
                  child: ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: _buildContent(service),
                  ),
                ),
              if (service.loading) _buildProgress(service),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(PlanService.hallUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        thirdPartyCookiesEnabled: true,
        // 「进入应用」是开新窗口跳转的，得允许，否则点不动
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
        // 伪装成桌面浏览器，不然应用里会报「调用接口异常」
        userAgent: AuthService.desktopUserAgent,
        useWideViewPort: true,
        loadWithOverviewMode: true,
      ),
      onWebViewCreated: (InAppWebViewController controller) {
        _controller = controller;
        _maybeAutoFetch();
      },
      onUpdateVisitedHistory:
          (InAppWebViewController controller, WebUri? url, bool? isReload) {
            debugPrint('[培养方案] WebView 地址: $url');
          },
      onCreateWindow:
          (InAppWebViewController controller, CreateWindowAction action) async {
            debugPrint('[培养方案] 新窗口请求: ${action.request.url}');
            // 新窗口的地址直接塞回当前 WebView，省得再维护第二个 WebView
            final WebUri? url = action.request.url;
            if (url == null) {
              return false;
            }
            await controller.loadUrl(urlRequest: URLRequest(url: url));
            return false;
          },
    );
  }

  Widget _buildContent(PlanService service) {
    final PlanNode? tree = service.tree;
    if (tree == null) {
      return _buildEmpty(service);
    }
    // 摊平成一行行的数据，交给 builder 按需建组件——方案几百门课，
    // 一次性全建出来在低端机上会卡
    final List<_PlanRow> rows = <_PlanRow>[];
    _flattenRows(service, tree, 1, rows);
    return Column(
      children: <Widget>[
        _buildSummary(service),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: rows.length,
            itemBuilder: (BuildContext context, int index) {
              final _PlanRow row = rows[index];
              return switch (row) {
                _HeadingRow() => _buildHeading(row.node, row.depth),
                _CourseRow() => _buildCourseRow(
                  row.node,
                  row.course,
                  row.depth,
                ),
              };
            },
          ),
        ),
      ],
    );
  }

  /// 顶上的修课进度、英语分级，右边是全部收起 / 展开。
  Widget _buildSummary(PlanService service) {
    final (num done, num total) = service.creditProgress;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '已修 ${_formatCredit(done)} / ${_formatCredit(total)} 学分',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: total > 0
                            ? (done / total).clamp(0, 1).toDouble()
                            : 0,
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: service.hasCollapsed
                    ? service.expandAll
                    : service.collapseAll,
                icon: Icon(
                  service.hasCollapsed
                      ? Icons.unfold_more
                      : Icons.unfold_less,
                  size: 18,
                ),
                label: Text(service.hasCollapsed ? '全部展开' : '全部收起'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: <Widget>[
              const Text(
                '英语分级',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<EnglishLevel>(
                  segments: <ButtonSegment<EnglishLevel>>[
                    for (final EnglishLevel level in EnglishLevel.values)
                      ButtonSegment<EnglishLevel>(
                        value: level,
                        label: Text(level.label),
                      ),
                  ],
                  selected: <EnglishLevel>{service.englishLevel},
                  onSelectionChanged: (Set<EnglishLevel> selection) =>
                      service.setEnglishLevel(selection.first),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 学分可能是小数，整数就不带小数点。
  static String _formatCredit(num value) =>
      value == value.truncateToDouble() ? '${value.toInt()}' : '$value';

  Widget _buildEmpty(PlanService service) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.school_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('还没有获取培养方案', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              service.error ?? '会复用「设置」里的登录状态，从一站式服务大厅读取你的个人培养方案。',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: service.loading ? null : _start,
              icon: const Icon(Icons.download),
              label: const Text('获取培养方案'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(PlanService service) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    service.status.isEmpty ? '正在获取…' : service.status,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 把节点摊成「标题 + 自己的课程 + 子节点」，顺序和 Markdown 里一样。
  void _flattenRows(
    PlanService service,
    PlanNode node,
    int depth,
    List<_PlanRow> out,
  ) {
    // 没选中的那几档英语模块直接不显示
    if (service.isNodeFilteredOut(node)) {
      return;
    }
    out.add(_HeadingRow(node, depth));
    if (service.isCollapsed(node.id)) {
      return;
    }
    for (final PlanCourse course in node.courses) {
      out.add(_CourseRow(node, course, depth));
    }
    for (final PlanNode child in node.children) {
      _flattenRows(service, child, depth + 1, out);
    }
  }

  /// 模块标题，层级越深字号越小，对应 Markdown 的 # / ## / ###。
  ///
  /// 有子模块的话前面挂个箭头，点一下就能收起来。
  Widget _buildHeading(PlanNode node, int depth) {
    final PlanService service = PlanService.instance;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool collapsible = node.children.isNotEmpty;
    final bool collapsed = collapsible && service.isCollapsed(node.id);
    final double size = switch (depth) {
      1 => 22,
      2 => 17,
      3 => 15,
      _ => 14,
    };

    return InkWell(
      onTap: collapsible ? () => service.toggleCollapsed(node.id) : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.only(top: depth == 1 ? 8 : 22, bottom: 6),
        child: Row(
          children: <Widget>[
            if (collapsible)
              Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 20,
                color: Colors.grey,
              )
            else
              const SizedBox(width: 20),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                node.name.isEmpty ? '（未命名模块）' : node.name,
                style: TextStyle(
                  fontSize: size,
                  fontWeight: depth <= 2 ? FontWeight.w700 : FontWeight.w600,
                  color: depth == 1 ? scheme.primary : null,
                ),
              ),
            ),
            if (node.requiredCredit != null)
              Text(
                '${node.requiredCredit} 学分',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  /// 一门课，前面就是 Markdown 里那个能点的 `- [ ]`。
  Widget _buildCourseRow(PlanNode node, PlanCourse course, int depth) {
    final PlanService service = PlanService.instance;
    final String key = PlanService.courseKey(node.name, course);
    final bool checked = service.isChecked(key);
    final List<String> meta = <String>[
      if (course.code != null) course.code!,
      if (course.credit != null) '${course.credit} 学分',
      if (course.semester != null) course.semester!,
      if (course.category != null) course.category!,
      if (course.examType != null) course.examType!,
      if (course.college != null) course.college!,
    ];

    return InkWell(
      onTap: () => service.toggleChecked(key),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.only(left: 4 + depth * 10.0, top: 3, bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: checked,
                onChanged: (bool? value) => service.toggleChecked(key),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    course.name.isEmpty ? '（未命名课程）' : course.name,
                    style: TextStyle(
                      fontSize: 15,
                      decoration: checked ? TextDecoration.lineThrough : null,
                      color: checked ? Colors.grey : null,
                    ),
                  ),
                  if (meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        meta.join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 培养方案列表里的一行。
sealed class _PlanRow {
  const _PlanRow();
}

/// 模块标题那一行。
class _HeadingRow extends _PlanRow {
  const _HeadingRow(this.node, this.depth);

  final PlanNode node;
  final int depth;
}

/// 一门课那一行。
class _CourseRow extends _PlanRow {
  const _CourseRow(this.node, this.course, this.depth);

  final PlanNode node;
  final PlanCourse course;
  final int depth;
}
