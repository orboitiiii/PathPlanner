import 'dart:math' as math;
import 'dart:ui' as ui show Image;
import 'package:flutter/material.dart';
import '../../../domain/models/field_config.dart';
import '../../../domain/models/waypoint.dart';
import '../../../domain/models/constraints.dart';

class FieldCanvas extends StatefulWidget {
  final FieldConfig cfg;
  final List<Waypoint> waypoints; // in meters
  final void Function(List<Waypoint>) onChanged;
  final ui.Image? bgImage;
  final Constraints cons;
  const FieldCanvas({
    super.key,
    required this.cfg,
    required this.waypoints,
    required this.onChanged,
    this.bgImage,
    required this.cons,
  });

  @override
  State<FieldCanvas> createState() => _FieldCanvasState();
}

class _FieldCanvasState extends State<FieldCanvas> {
  late List<Waypoint> wps;
  int? draggingIdx;

  @override
  void initState() {
    super.initState();
    wps = widget.waypoints.map((w)=>Waypoint(w.m, w.kind, w.label, thetaDeg: w.thetaDeg)).toList();
  }

  @override
  void didUpdateWidget(covariant FieldCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Always sync from parent
    wps = widget.waypoints.map((w)=>Waypoint(w.m, w.kind, w.label, thetaDeg: w.thetaDeg)).toList();
  }

  void _commit() => widget.onChanged(List<Waypoint>.from(wps));

  int? _hitTest(Offset pCanvas, Size size) {
    // convert field meters to canvas coord (we draw field scaled to full size)
    const r = 10.0;
    for (int i = 0; i < wps.length; i++) {
      if (wps[i].kind == WaypointKind.pass) {
        final pt = _meterToCanvas(wps[i].m, size);
        if ((pt - pCanvas).distance <= r) return i;
      }
    }
    return null;
  }

  Offset _meterToCanvas(Offset m, Size size) {
    // map field meters to canvas pixels (fit to width, keep aspect, origin bottom-left)
    final fs = widget.cfg.fieldSizeMeters;
    final scale = math.min(size.width / fs.width, size.height / fs.height);
    final ox = (size.width - fs.width * scale) / 2;
    final oy = (size.height - fs.height * scale) / 2;
    // bottom-left origin -> canvas has y down, so invert y
    final x = ox + m.dx * scale;
    final y = size.height - (oy + m.dy * scale);
    return Offset(x, y);
  }

  Offset _canvasToMeter(Offset c, Size size) {
    final fs = widget.cfg.fieldSizeMeters;
    final scale = math.min(size.width / fs.width, size.height / fs.height);
    final ox = (size.width - fs.width * scale) / 2;
    final oy = (size.height - fs.height * scale) / 2;
    final x = (c.dx - ox) / scale;
    final y = ((size.height - c.dy) - oy) / scale;
    return Offset(x.clamp(0, fs.width), y.clamp(0, fs.height));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final path = Path();
        if (wps.isNotEmpty) {
          path.moveTo(_meterToCanvas(wps.first.m, size).dx, _meterToCanvas(wps.first.m, size).dy);
          for (int i = 1; i < wps.length; i++) {
            final c = _meterToCanvas(wps[i].m, size);
            path.lineTo(c.dx, c.dy);
          }
        }
        return GestureDetector(
          onTapDown: (d) {
            final i = _hitTest(d.localPosition, size);
            if (i != null) {
              // select only pass points
              draggingIdx = i;
            }
          },
          onPanUpdate: (d) {
            if (draggingIdx != null) {
              final m = _canvasToMeter(d.localPosition, size);
              setState(() {
                wps[draggingIdx!].m = m;
              });
              _commit();
            }
          },
          onPanEnd: (_) => draggingIdx = null,
          child: CustomPaint(
            painter: _FieldPainter(widget.cfg, widget.cons, wps, path, widget.bgImage),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _FieldPainter extends CustomPainter {
  final FieldConfig cfg;
  final Constraints cons;
  final List<Waypoint> wps;
  final Path path;
  final ui.Image? bg;
  _FieldPainter(this.cfg, this.cons, this.wps, this.path, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    // draw field frame (fit)
    final fs = cfg.fieldSizeMeters;
    final scale = math.min(size.width / fs.width, size.height / fs.height);
    final ox = (size.width - fs.width * scale) / 2;
    final oy = (size.height - fs.height * scale) / 2;
    final rect = Rect.fromLTWH(ox, oy, fs.width * scale, fs.height * scale);

    final paintFrame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF7BAAF7);
    canvas.drawRect(rect, paintFrame);

    // background image if provided: draw inside rect with bottom-left origin mapping
    if (bg != null) {
      // image is in image coords (y down). Our meters->canvas already flips y for display suitable.
      // Just fit the image rect to 'rect' area.
      final src = cfg.pixelRect;
      canvas.drawImageRect(bg!, src, rect, Paint());
    }

    // grid (1m)
    final grid = Paint()
      ..color = const Color(0x2248D1CC)
      ..strokeWidth = 1;
    for (double x = 0; x <= fs.width + 1e-6; x += 1.0) {
      final sx = ox + x * scale;
      canvas.drawLine(Offset(sx, oy), Offset(sx, oy + fs.height * scale), grid);
    }
    for (double y = 0; y <= fs.height + 1e-6; y += 1.0) {
      final sy = size.height - (oy + y * scale);
      canvas.drawLine(Offset(ox, sy), Offset(ox + fs.width * scale, sy), grid);
    }

    // path
    final pathPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(path, pathPaint);

    // points

    // orientation arrows + robot footprint (use user constraints L/W)
    final Lm = cons.robotLength;
    final Wm = cons.robotWidth;
    final lpx = Lm * scale / 2;
    final wpx = Wm * scale / 2;
    for (final p in wps) {
      final c = _meterToCanvas(p.m, size, fs);
      final theta = (p.thetaDeg ?? 0) * math.pi / 180.0;
      // canvas forward unit (y-down canvas)
      final ux = Offset(math.cos(theta), -math.sin(theta));
      final uy = Offset(-ux.dy, ux.dx); // left

      // black arrow for heading
      final arrowLen = 0.45 * scale;
      final arrowEnd = c + ux * arrowLen;
      final arr = Paint()
        ..color = const Color(0xFF000000)
        ..strokeWidth = 2;
      canvas.drawLine(c, arrowEnd, arr);
      final headBase = arrowEnd - ux * 8;
      final tri = Path()
        ..moveTo(arrowEnd.dx, arrowEnd.dy)
        ..lineTo(headBase.dx + uy.dx*4, headBase.dy + uy.dy*4)
        ..lineTo(headBase.dx - uy.dx*4, headBase.dy - uy.dy*4)
        ..close();
      canvas.drawPath(tri, arr);

      
      // draw robot square only for start/end; edges: front(blue), others(red)
      if (p.kind != WaypointKind.pass) {
        final side = math.max(cons.robotLength, cons.robotWidth);
        final half = side * scale / 2;
        final a = c + ux*half + uy*half; // front-left
        final b = c + ux*half - uy*half; // front-right
        final d = c - ux*half - uy*half; // rear-right
        final e = c - ux*half + uy*half; // rear-left

        final blue = Paint()
          ..color = const Color(0xFF2196F3)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;
        final red = Paint()
          ..color = const Color(0xFFF44336)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

        // front edge
        canvas.drawLine(a, b, blue);
        // other three edges
        canvas.drawLine(b, d, red);
        canvas.drawLine(d, e, red);
        canvas.drawLine(e, a, red);
      }
    }
        
    for (int i = 0; i < wps.length; i++) {
      final p = wps[i];
      final c = _meterToCanvas(p.m, size, fs);
      final color = switch (p.kind) {
        WaypointKind.start => const Color(0xFF4CAF50),
        WaypointKind.end => const Color(0xFFF44336),
        WaypointKind.pass => const Color(0xFF29B6F6),
      };
      final fill = Paint()..color = color;
      canvas.drawCircle(c, 6, fill);
      final tp = TextPainter(
        text: TextSpan(text: p.label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c + const Offset(8, -18));
    }

    // origin marker (0,0) bottom-left
    final originCanvas = Offset(ox, oy + fs.height * scale); // bottom-left of rect
    final mark = Paint()..color = const Color(0xFFE91E63);
    canvas.drawCircle(originCanvas, 4, mark);
  }

  Offset _meterToCanvas(Offset m, Size size, Size fs) {
    final scale = math.min(size.width / fs.width, size.height / fs.height);
    final ox = (size.width - fs.width * scale) / 2;
    final oy = (size.height - fs.height * scale) / 2;
    final x = ox + m.dx * scale;
    final y = size.height - (oy + m.dy * scale);
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _FieldPainter oldDelegate) {
    return oldDelegate.wps != wps || oldDelegate.bg != bg || oldDelegate.cons != cons;
    }
}
