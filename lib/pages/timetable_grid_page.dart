import 'package:flutter/material.dart';

import '../services/timetable_service.dart';

/// 左侧节次/时间标签的宽度。
const double _labelWidth = 56;

/// 顶部星期行的高度。
const double _headerHeight = 54;

/// 每一节课在网格里的高度。
const double _sectionHeight = 62;

/// 至少要画到第几节，免得课少的时候网格太扁。
const int _minSection = 10;

/// 周课表网格。
///
/// 左边一列是节次，顶上是一周七天，课程块按它占的节次铺在网格上。
class TimetableGridPage extends StatefulWidget {
  const TimetableGridPage({super.key, required this.initialWeek, this.focusDay});

  final int initialWeek;

  /// 从列表里点进来的话，把那一列高亮一下。
  final int? focusDay;

  @override
  State<TimetableGridPage> createState() => _TimetableGridPageState();
}

class _TimetableGridPageState extends State<TimetableGridPage> {
  late int _week = widget.initialWeek;

  static const List<String> _dayNames = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  @override
  Widget build(BuildContext context) {
    final TimetableData? data = TimetableService.instance.data;
    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('周课表')),
        body: const Center(child: Text('还没有课表数据')),
      );
    }

    final int maxWeek = data.weekCount > 0 ? data.weekCount : 1;
    final int week = _week.clamp(1, maxWeek);
    final int sectionCount = _sectionCount(data);

    return Scaffold(
      appBar: AppBar(
        title: Text('周课表 · 第 $week 周'),
        actions: <Widget>[
          IconButton(
            tooltip: '上一周',
            onPressed: week > 1 ? () => setState(() => _week = week - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: '下一周',
            onPressed: week < maxWeek
                ? () => setState(() => _week = week + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double dayWidth = (constraints.maxWidth - _labelWidth) / 7;
          return Column(
            children: <Widget>[
              _buildHeader(context, data, week, dayWidth),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  child: SizedBox(
                    height: sectionCount * _sectionHeight,
                    child: Stack(
                      children: <Widget>[
                        ..._buildGridLines(sectionCount, dayWidth),
                        ..._buildBlocks(context, data, week, dayWidth),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 网格要画多少节，取课表里最晚的结束节次。
  int _sectionCount(TimetableData data) {
    int maxSection = _minSection;
    for (final CourseArrangement item in data.arrangements) {
      if (item.endSection > maxSection) {
        maxSection = item.endSection;
      }
    }
    return maxSection;
  }

  Widget _buildHeader(
    BuildContext context,
    TimetableData data,
    int week,
    double dayWidth,
  ) {
    final DateTime monday = data.mondayOf(week);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _headerHeight,
      child: Row(
        children: <Widget>[
          const SizedBox(width: _labelWidth),
          for (int day = 1; day <= 7; day++)
            SizedBox(
              width: dayWidth,
              child: Container(
                alignment: Alignment.center,
                decoration: widget.focusDay == day
                    ? BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.5),
                      )
                    : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      _dayNames[day - 1],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _formatDate(monday.add(Duration(days: day - 1))),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 每节课之间的横线、每天之间的竖线，还有左侧的节次和时间。
  List<Widget> _buildGridLines(int sectionCount, double dayWidth) {
    final Color line = Theme.of(context).dividerColor.withValues(alpha: 0.4);
    final List<Widget> children = <Widget>[];

    for (int section = 1; section <= sectionCount; section++) {
      children.add(
        Positioned(
          left: _labelWidth,
          right: 0,
          top: (section - 1) * _sectionHeight,
          child: Divider(height: 1, color: line),
        ),
      );
    }

    // 左边一列按大节显示，节次号下面挂上课时间
    for (final ClassSlot slot in ClassSchedule.slots) {
      if (slot.startSection > sectionCount) {
        continue;
      }
      final int from = slot.startSection;
      final int to = slot.endSection > sectionCount
          ? sectionCount
          : slot.endSection;
      children.add(
        Positioned(
          left: 0,
          width: _labelWidth,
          top: (from - 1) * _sectionHeight,
          height: (to - from + 1) * _sectionHeight,
          child: _buildSectionLabel('$from-$to', slot.beginTime, slot.endTime),
        ),
      );
    }

    // 作息表没覆盖到的节次，只标个号
    final int lastKnown = ClassSchedule.slots.last.endSection;
    for (int section = lastKnown + 1; section <= sectionCount; section++) {
      children.add(
        Positioned(
          left: 0,
          width: _labelWidth,
          top: (section - 1) * _sectionHeight,
          height: _sectionHeight,
          child: _buildSectionLabel('$section', null, null),
        ),
      );
    }

    for (int day = 1; day <= 7; day++) {
      children.add(
        Positioned(
          left: _labelWidth + day * dayWidth,
          top: 0,
          bottom: 0,
          child: VerticalDivider(width: 1, color: line),
        ),
      );
    }

    if (widget.focusDay != null) {
      children.add(
        Positioned(
          left: _labelWidth + (widget.focusDay! - 1) * dayWidth,
          width: dayWidth,
          top: 0,
          bottom: 0,
          child: ColoredBox(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.25),
          ),
        ),
      );
    }

    return children;
  }

  /// 左侧格子里的节次号和上课时间。
  Widget _buildSectionLabel(String section, String? begin, String? end) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            section,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          if (begin != null && end != null) ...<Widget>[
            const SizedBox(height: 2),
            SizedBox(
              width: _labelWidth - 10,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$begin-$end',
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildBlocks(
    BuildContext context,
    TimetableData data,
    int week,
    double dayWidth,
  ) {
    final List<CourseArrangement> items = data.arrangementsOfWeek(week);
    final List<Widget> blocks = <Widget>[];

    for (int day = 1; day <= 7; day++) {
      final List<CourseArrangement> today = items
          .where((CourseArrangement item) => item.day == day)
          .toList()
        ..sort(
          (CourseArrangement a, CourseArrangement b) =>
              a.startSection.compareTo(b.startSection),
        );
      if (today.isEmpty) {
        continue;
      }

      // 同一天里时间重叠的课会平分格子宽度，不重叠的就占满整格
      final List<int> columnOf = _assignColumns(today);
      final int columns = columnOf.isEmpty
          ? 1
          : columnOf.reduce((int a, int b) => a > b ? a : b) + 1;
      final double cellWidth = dayWidth / columns;

      for (int i = 0; i < today.length; i++) {
        final CourseArrangement item = today[i];
        final CourseInfo? course = item.courseIndex < data.courses.length
            ? data.courses[item.courseIndex]
            : null;
        blocks.add(
          Positioned(
            left: _labelWidth + (day - 1) * dayWidth + columnOf[i] * cellWidth,
            top: (item.startSection - 1) * _sectionHeight,
            width: cellWidth - 2,
            height:
                (item.endSection - item.startSection + 1) * _sectionHeight - 2,
            child: _buildCard(context, item, course),
          ),
        );
      }
    }

    return blocks;
  }

  /// 给一天的课分配列号：能塞进已有列就复用，塞不下就新开一列。
  List<int> _assignColumns(List<CourseArrangement> items) {
    final List<int> columnEnds = <int>[];
    final List<int> result = <int>[];
    for (final CourseArrangement item in items) {
      int column = -1;
      for (int i = 0; i < columnEnds.length; i++) {
        if (columnEnds[i] < item.startSection) {
          column = i;
          break;
        }
      }
      if (column < 0) {
        columnEnds.add(item.endSection);
        column = columnEnds.length - 1;
      } else {
        columnEnds[column] = item.endSection;
      }
      result.add(column);
    }
    return result;
  }

  Widget _buildCard(
    BuildContext context,
    CourseArrangement item,
    CourseInfo? course,
  ) {
    final MaterialColor color =
        Colors.primaries[item.courseIndex % Colors.primaries.length];
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final List<String> lines = <String>[
      if (item.classroom != null) item.classroom!,
      if (item.teacher != null) item.teacher!,
    ];

    return Padding(
      padding: const EdgeInsets.all(2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? color.shade900 : color.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.shade300, width: 0.6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                course == null || course.name.isEmpty ? '（未知课程）' : course.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: dark ? color.shade100 : color.shade900,
                ),
              ),
              if (lines.isNotEmpty)
                Expanded(
                  child: Text(
                    lines.join('\n'),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: dark ? color.shade200 : color.shade800,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) => '${date.month}/${date.day}';
}
