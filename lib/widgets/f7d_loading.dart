import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 《永远的七日之都》那款加载框动画。
///
/// 移植自 https://github.com/Yukiko-Official/F7D_Loading 的纯前端版本：一个白底方框，
/// 四条黑边加两条会伸缩的覆盖条，尺寸被一条正弦曲线牵着在「张开」和「收回」之间来回，
/// 每半周期整体顺时针转 45°，2.4 秒走完一个循环。
class F7dLoading extends StatefulWidget {
  const F7dLoading({
    super.key,
    this.size = 200,
    this.foreground = Colors.black,
    this.background = Colors.white,
  });

  /// 动画主体的边长，原版是 200。
  final double size;

  /// 几何块的颜色，原版是纯黑。
  final Color foreground;

  /// 框内的底色，原版是纯白。
  final Color background;

  @override
  State<F7dLoading> createState() => _F7dLoadingState();
}

class _F7dLoadingState extends State<F7dLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 主体整体在转，得留出对角线的余量，不然四个角会被裁掉
    final double side = widget.size * math.sqrt2;
    return SizedBox(
      width: side,
      height: side,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) => CustomPaint(
          painter: _F7dPainter(
            phase: _controller.value,
            foreground: widget.foreground,
            background: widget.background,
          ),
        ),
      ),
    );
  }
}

/// 按相位把那一堆矩形摆出来。
class _F7dPainter extends CustomPainter {
  _F7dPainter({
    required this.phase,
    required this.foreground,
    required this.background,
  });

  /// 0 → 1 就是一个完整周期。
  final double phase;

  final Color foreground;
  final Color background;

  /// 原版所有尺寸都是按 200×200 的框定的，这里沿用同一套坐标，最后整体缩放。
  static const double _base = 200;

  /// 在 [a] 和 [b] 之间按 [t] 插值。
  static double _mix(double a, double b, double t) => a + (b - a) * t;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fg = Paint()..color = foreground;
    final Paint bg = Paint()..color = background;

    // 正弦信号：p 在 0 → 1 → 0 之间平滑来回
    final double p = (1 - math.cos(2 * math.pi * phase)) / 2;
    // 一个周期分两段：前半段「张开」，后半段「收回」
    final int halfSeg = (phase * 2).floor();
    final bool opening = halfSeg.isEven;
    final double segProgress = opening ? p : 1 - p;
    final double angle = (45 * (halfSeg + segProgress)) % 90 * math.pi / 180;

    // 摆好画布：挪到中心 → 旋转 → 退回左上角，之后就能按 200 的坐标直接画
    final double side = size.shortestSide / math.sqrt2;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    canvas.translate(-side / 2, -side / 2);
    canvas.scale(side / _base);

    // ===== 各部分尺寸（照搬原版 apply()）=====
    // 张开时左右两条厚边 22 → 10；收回时停在 10，只让上下两条薄边 10 → 22 追上去
    final double edgeW = opening ? _mix(22, 10, p) : 10;
    final double edgeH = opening ? 10 : _mix(10, 22, 1 - p);
    // 覆盖条和它上面那两条：宽度张开时从初始值涨到最终值，
    // 收回时则从 10（与边同厚）倒着放回去，其余维度原路返回
    final double overlayW = _mix(opening ? 22 : 10, 75, p);
    final double overlayH = _mix(120, 85, p);
    final double barW = _mix(opening ? 22 : 10, 160, p);
    final double barH = _mix(25, 8, p);
    final double blockW = _mix(opening ? 22 : 10, 75, p);
    final double blockH = _mix(66, 50, p);

    // ===== 底色 =====
    canvas.drawRect(const Rect.fromLTRB(0, 0, _base, _base), bg);

    // ===== 四条常驻的边（先画，后面会被覆盖条压住）=====
    canvas.drawRect(Rect.fromLTRB(0, 0, _base, edgeH), fg); // 上
    canvas.drawRect(Rect.fromLTRB(0, _base - edgeH, _base, _base), fg); // 下
    canvas.drawRect(Rect.fromLTRB(0, 0, edgeW, _base), fg); // 左
    canvas.drawRect(Rect.fromLTRB(_base - edgeW, 0, _base, _base), fg); // 右

    // ===== 左边那条覆盖条：贴顶，里面的横条贴底 =====
    canvas.drawRect(Rect.fromLTRB(0, 0, overlayW, overlayH), fg);
    canvas.drawRect(Rect.fromLTRB(0, overlayH - barH, barW, overlayH), fg);
    canvas.drawRect(
      Rect.fromLTRB(barW - blockW, overlayH - blockH, barW, overlayH),
      fg,
    );

    // ===== 右边那条：贴底，里面的横条贴顶（跟左边呈 180° 对角）=====
    canvas.drawRect(
      Rect.fromLTRB(_base - overlayW, _base - overlayH, _base, _base),
      fg,
    );
    canvas.drawRect(
      Rect.fromLTRB(_base - barW, _base - overlayH, _base, _base - overlayH + barH),
      fg,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        _base - barW,
        _base - overlayH,
        _base - barW + blockW,
        _base - overlayH + blockH,
      ),
      fg,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_F7dPainter old) =>
      old.phase != phase ||
      old.foreground != foreground ||
      old.background != background;
}
