// lib/features/field/widgets/field_canvas.dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../domain/algos/advanced_path_planner.dart';
import '../../../domain/models/constraints.dart';
import '../../../domain/models/field_config.dart';
import '../../../domain/models/waypoint.dart';

class FieldCanvas extends StatefulWidget {
  final FieldConfig cfg;
  final List<Waypoint> waypoints;
  final void Function(List<Waypoint>) onChanged;

  final ui.Image? bgImage;
  final Constraints cons;

  final List<PathPoint> plannedPathPoints;

  // 每一段的二次貝茲控制點（長度 = waypoints.length - 1）
  final List<Offset?>? quadCtrls;
  final void Function(int segIndex, Offset m)? onCtrlChanged;

  const FieldCanvas({
    super.key,
    required this.cfg,
    required this.waypoints,
    required this.onChanged,
    required this.cons,
    this.bgImage,
    this.plannedPathPoints = const [],
    this.quadCtrls,
    this.onCtrlChanged,
  });

  @override
  State<FieldCanvas> createState() => _FieldCanvasState();
}

class _FieldCanvasState extends State<FieldCanvas> {
  _Hit? _active;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            final tf = _Transform.fromSize(widget.cfg, size);
            _active = _hitTest(tf, d.localPosition);
          },
          onPanUpdate: (d) {
            if (_active == null) return;
            final tf = _Transform.fromSize(widget.cfg, size);
            final m = tf.invTp(d.localPosition);
            if (_active!.kind == _HitKind.waypoint) {
              final i = _active!.index;
              final wps = List<Waypoint>.from(widget.waypoints);
              final w = wps[i];
              wps[i] = Waypoint(m, w.kind, w.label, thetaDeg: w.thetaDeg);
              widget.onChanged(wps);
            } else if (_active!.kind == _HitKind.ctrl &&
                widget.onCtrlChanged != null) {
              widget.onCtrlChanged!(_active!.index, m);
            }
          },
          onPanEnd: (_) => _active = null,
          onPanCancel: () => _active = null,
          child: CustomPaint(
            painter: _FieldPainter(
              cfg: widget.cfg,
              cons: widget.cons,
              bg: widget.bgImage,
              waypoints: widget.waypoints,
              planned: widget.plannedPathPoints,
              quadCtrls: widget.quadCtrls,
            ),
          ),
        );
      },
    );
  }

  _Hit? _hitTest(_Transform tf, Offset p) {
    const wpR = 12.0;
    const ctrlR = 10.0;

    // 先測控制點
    final ctrls = widget.quadCtrls;
    if (ctrls != null) {
      for (int i = 0; i < ctrls.length; i++) {
        final c = ctrls[i];
        if (c == null) continue;
        final pc = tf.tp(c);
        if ((pc - p).distance <= ctrlR) {
          return _Hit(_HitKind.ctrl, i);
        }
      }
    }
    // 再測路點
    for (int i = 0; i < widget.waypoints.length; i++) {
      final w = widget.waypoints[i];
      final pw = tf.tp(w.m);
      if ((pw - p).distance <= wpR) {
        return _Hit(_HitKind.waypoint, i);
      }
    }
    return null;
  }
}

class _FieldPainter extends CustomPainter {
  final FieldConfig cfg;
  final Constraints cons;
  final ui.Image? bg;
  final List<Waypoint> waypoints;
  final List<PathPoint> planned;
  final List<Offset?>? quadCtrls;

  _FieldPainter({
    required this.cfg,
    required this.cons,
    required this.bg,
    required this.waypoints,
    required this.planned,
    required this.quadCtrls,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tf = _Transform.fromSize(cfg, size);

    // 背景：裁切 pixelRect → 映射到世界場地矩形 dst（正確縮放）
    final dst = Rect.fromLTWH(
      tf.dx,
      tf.dy,
      cfg.fieldSizeMeters.width * tf.s,
      cfg.fieldSizeMeters.height * tf.s,
    );

    if (bg != null) {
      final pr = cfg.pixelRect;
      final src = Rect.fromLTWH(pr.left, pr.top, pr.width, pr.height);
      canvas.drawImageRect(
        bg!,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.high,
      );
    } else {
      final r = RRect.fromRectXY(dst, 12, 12);
      canvas.drawRRect(r, Paint()..color = const Color(0xFF263238));
    }

    _drawGrid(canvas, tf);
    if (planned.isNotEmpty) _drawPlanned(canvas, tf);
    _drawQuadCtrls(canvas, tf);
    _drawWaypoints(canvas, tf);
  }

  void _drawGrid(Canvas canvas, _Transform tf) {
    final fw = cfg.fieldSizeMeters.width;
    final fh = cfg.fieldSizeMeters.height;
    const step = 1.0; // 1m
    final p = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;

    for (double x = 0; x <= fw + 1e-6; x += step) {
      final a = tf.tp(Offset(x, 0));
      final b = tf.tp(Offset(x, fh));
      canvas.drawLine(a, b, p);
    }
    for (double y = 0; y <= fh + 1e-6; y += step) {
      final a = tf.tp(Offset(0, y));
      final b = tf.tp(Offset(fw, y));
      canvas.drawLine(a, b, p);
    }
  }

  void _drawPlanned(Canvas canvas, _Transform tf) {
    final path = Path();
    for (int i = 0; i < planned.length; i++) {
      final p = tf.tp(planned[i].position);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    final stroke = Paint()
      ..color = const Color(0xFF64B5F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(path, stroke);
  }

  void _drawQuadCtrls(Canvas canvas, _Transform tf) {
    if (quadCtrls == null || quadCtrls!.isEmpty) return;
    final nSeg = math.max(0, waypoints.length - 1);

    final linkP = Paint()
      ..color = const Color(0xFFAB47BC)
      ..strokeWidth = 2;
    final dashP = Paint()
      ..color = const Color(0xFFAB47BC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 0; i < nSeg; i++) {
      final p0 = tf.tp(waypoints[i].m);
      final p1 = tf.tp(waypoints[i + 1].m);
      final c = quadCtrls![i];
      if (c == null) continue;
      final pc = tf.tp(c);

      // 輔助線
      canvas.drawLine(p0, pc, linkP);
      canvas.drawLine(pc, p1, linkP);

      // 曲線示意（虛線）
      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..quadraticBezierTo(pc.dx, pc.dy, p1.dx, p1.dy);
      _drawDashedPath(canvas, path, dashP, 8, 6);

      // 控制點手把
      const r = 6.0;
      canvas.drawRect(
        Rect.fromCenter(center: pc, width: r * 2, height: r * 2),
        Paint()..color = const Color(0xFFCE93D8),
      );
    }
  }

  void _drawWaypoints(Canvas canvas, _Transform tf) {
    const r = 7.0;
    for (int i = 0; i < waypoints.length; i++) {
      final w = waypoints[i];
      final p = tf.tp(w.m);
      final fill = Paint()
        ..color = switch (w.kind) {
          WaypointKind.start => const Color(0xFF00E676),
          WaypointKind.end => const Color(0xFFFF5252),
          WaypointKind.pass => const Color(0xFFFFD54F),
          WaypointKind.passThrough => const Color(0xFF00BCD4), // 青色：過點不停
        };
      canvas.drawCircle(p, r, fill);

      final tp = TextPainter(
        text: TextSpan(
            text: w.label,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p + const Offset(8, -6));
    }
  }

  @override
  bool shouldRepaint(covariant _FieldPainter old) {
    return old.bg != bg ||
        old.waypoints != waypoints ||
        old.planned != planned ||
        old.quadCtrls != quadCtrls ||
        old.cfg != cfg ||
        old.cons != cons;
  }
}

// 世界↔畫布轉換（等比縮放 + 居中 + Y 翻轉）
class _Transform {
  final double s;
  final double dx;
  final double dy;
  final double fw;
  final double fh;

  _Transform(this.s, this.dx, this.dy, this.fw, this.fh);

  factory _Transform.fromSize(FieldConfig cfg, Size size) {
    final fw = cfg.fieldSizeMeters.width;
    final fh = cfg.fieldSizeMeters.height;
    final s = math.min(size.width / fw, size.height / fh);
    final dx = (size.width - fw * s) / 2.0;
    final dy = (size.height - fh * s) / 2.0;
    return _Transform(s, dx, dy, fw, fh);
  }

  // m → px
  Offset tp(Offset m) => Offset(dx + m.dx * s, dy + (fh - m.dy) * s);

  // px → m
  Offset invTp(Offset p) => Offset(
        (p.dx - dx) / s,
        fh - (p.dy - dy) / s,
      );
}

// 繪製虛線
void _drawDashedPath(
    Canvas canvas, Path path, Paint paint, double dash, double gap) {
  for (final m in path.computeMetrics()) {
    double dist = 0.0;
    while (dist < m.length) {
      final a = dist;
      final b = math.min(dist + dash, m.length);
      canvas.drawPath(m.extractPath(a, b), paint);
      dist += dash + gap;
    }
  }
}

enum _HitKind { waypoint, ctrl }

class _Hit {
  final _HitKind kind;
  final int index;
  _Hit(this.kind, this.index);
}
