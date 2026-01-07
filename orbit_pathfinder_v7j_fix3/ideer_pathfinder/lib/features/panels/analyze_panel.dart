import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/models/constraints.dart'; // Adjust path
import '../../domain/algos/advanced_path_planner.dart'; // For PathPoint
import '../../theme/spacex_theme.dart'; // Use SpaceX colors

class AnalyzePanel extends StatelessWidget {
  final List<PathPoint> points;
  final Constraints cons;
  final double time;
  final ValueChanged<double> onSeekTime;

  const AnalyzePanel({
    super.key,
    required this.points,
    required this.cons,
    required this.time,
    required this.onSeekTime,
  });

  @override
  Widget build(BuildContext context) {
    // Basic implementation for dashboard
    // We can rely on a simpler version or the full version.
    // Let's enable a flexible layout.
    return LayoutBuilder(builder: (context, constraints) {
      return Container(
          color: SpaceXColors.surface,
          padding: const EdgeInsets.all(8),
          child: points.isEmpty
              ? const Center(
                  child: Text("No Path Data",
                      style: TextStyle(color: SpaceXColors.textMuted)))
              : Column(
                  children: [
                    Expanded(
                        child: _MiniChart(
                      labelLeft: "Speed (m/s)",
                      domainLabel: "Time (s)",
                      domainMin: 0,
                      domainMax: points.last.time,
                      samples: points
                          .map((p) => Offset(p.time, p.velocity))
                          .toList(),
                      cursorX: time,
                      onTapX: onSeekTime,
                    )),
                    const SizedBox(height: 4),
                    Expanded(
                        child: _MiniChart(
                      labelLeft: "Accel (m/s²)",
                      domainLabel: "Time (s)",
                      domainMin: 0,
                      domainMax: points.last.time,
                      samples: points
                          .map((p) => Offset(p.time, p.acceleration))
                          .toList(),
                      cursorX: time,
                      onTapX: onSeekTime,
                      symmetricY: true,
                    )),
                  ],
                ));
    });
  }
}

class _MiniChart extends StatelessWidget {
  final String labelLeft;
  final String domainLabel;
  final double domainMin;
  final double domainMax;
  final List<Offset> samples; // x=domain, y=value
  final double? cursorX;
  final bool symmetricY;
  final ValueChanged<double>? onTapX;
  const _MiniChart({
    required this.labelLeft,
    required this.domainLabel,
    required this.domainMin,
    required this.domainMax,
    required this.samples,
    this.cursorX,
    this.onTapX,
    this.symmetricY = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        if (onTapX == null) return;
        final w = context.size!.width;
        final plotW = w - 40; // padding estimation
        if (plotW <= 0) return;
        final xLocal = (d.localPosition.dx - 30).clamp(0.0, plotW);
        final t = domainMin + (xLocal / plotW) * (domainMax - domainMin);
        onTapX!(t);
      },
      child: CustomPaint(
        painter: _ChartPainter(
          samples: samples,
          labelLeft: labelLeft,
          domainLabel: domainLabel,
          domainMin: domainMin,
          domainMax: domainMax,
          cursorX: cursorX,
          symmetricY: symmetricY,
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<Offset> samples;
  final String labelLeft;
  final String domainLabel;
  final double domainMin;
  final double domainMax;
  final double? cursorX;
  final bool symmetricY;

  _ChartPainter({
    required this.samples,
    required this.labelLeft,
    required this.domainLabel,
    required this.domainMin,
    required this.domainMax,
    required this.cursorX,
    required this.symmetricY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(30, 10, size.width - 40, size.height - 20);
    // Draw bg
    canvas.drawRect(rect, Paint()..color = SpaceXColors.surfaceElevated);
    // Grid
    final grid = Paint()
      ..color = SpaceXColors.border.withOpacity(0.3)
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, grid);

    // Draw Line
    if (samples.isEmpty) return;

    double minY = samples.first.dy, maxY = samples.first.dy;
    for (final s in samples) {
      if (s.dy < minY) minY = s.dy;
      if (s.dy > maxY) maxY = s.dy;
    }
    if (symmetricY) {
      final m = math.max(minY.abs(), maxY.abs());
      minY = -m;
      maxY = m;
    }
    if (minY == maxY) {
      maxY += 1;
      minY -= 1;
    }

    final path = Path();
    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      final x =
          rect.left + (s.dx - domainMin) / (domainMax - domainMin) * rect.width;
      final y = rect.bottom - (s.dy - minY) / (maxY - minY) * rect.height;
      if (i == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = SpaceXColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Cursor
    if (cursorX != null) {
      final cx = rect.left +
          (cursorX! - domainMin) / (domainMax - domainMin) * rect.width;
      if (cx >= rect.left && cx <= rect.right) {
        canvas.drawLine(Offset(cx, rect.top), Offset(cx, rect.bottom),
            Paint()..color = SpaceXColors.primary);
      }
    }

    // Text
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
        text: labelLeft,
        style:
            const TextStyle(color: SpaceXColors.textSecondary, fontSize: 10));
    tp.layout();
    tp.paint(canvas, Offset(2, rect.top));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
