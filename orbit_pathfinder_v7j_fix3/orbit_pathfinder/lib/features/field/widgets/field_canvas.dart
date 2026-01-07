import 'dart:math' as math;
import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';

import '../../../domain/algos/geometry.dart';
import '../../../domain/models/constraints.dart';
import '../../../domain/models/field_config.dart';
import '../../../domain/models/waypoint.dart';

class FieldCanvas extends StatefulWidget {
  final FieldConfig cfg;
  final List<Waypoint> waypoints; // in meters
  final void Function(List<Waypoint>) onChanged;
  final ui.Image? bgImage;
  final Constraints cons;
  final List<Offset> plannedPath; // 新增：規劃好的路徑點
  final List<PathGeomSample> pathSamples; // 新增：路徑樣本數據
  
  const FieldCanvas({
    super.key,
    required this.cfg,
    required this.waypoints,
    required this.onChanged,
    this.bgImage,
    required this.cons,
    this.plannedPath = const [],
    this.pathSamples = const [],
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
        
        // 建立規劃路徑的Path物件
        Path plannedPathObj = Path();
        if (widget.plannedPath.isNotEmpty) {
          final firstPoint = _meterToCanvas(widget.plannedPath.first, size);
          plannedPathObj.moveTo(firstPoint.dx, firstPoint.dy);
          for (int i = 1; i < widget.plannedPath.length; i++) {
            final point = _meterToCanvas(widget.plannedPath[i], size);
            plannedPathObj.lineTo(point.dx, point.dy);
          }
        }
        
        // 建立原始航點連線的Path (用於顯示原始航點連接)
        final waypointPath = Path();
        if (wps.isNotEmpty) {
          waypointPath.moveTo(_meterToCanvas(wps.first.m, size).dx, _meterToCanvas(wps.first.m, size).dy);
          for (int i = 1; i < wps.length; i++) {
            final c = _meterToCanvas(wps[i].m, size);
            waypointPath.lineTo(c.dx, c.dy);
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
            painter: _FieldPainter(
              widget.cfg, 
              widget.cons, 
              wps, 
              waypointPath, 
              plannedPathObj,  // 傳遞規劃路徑
              widget.bgImage,
              widget.pathSamples,
            ),
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
  final Path waypointPath;
  final Path plannedPath;  // 新增：規劃路徑
  final ui.Image? bg;
  final List<PathGeomSample> pathSamples;  // 新增：路徑樣本
  
  _FieldPainter(this.cfg, this.cons, this.wps, this.waypointPath, this.plannedPath, this.bg, this.pathSamples);

  // 輔助方法：繪製虛線
  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint, {double dashLength = 5, double gapLength = 3}) {
    final distance = (end - start).distance;
    final unitVector = (end - start) / distance;
    
    double currentDistance = 0;
    bool isDash = true;
    
    while (currentDistance < distance) {
      final segmentLength = isDash ? dashLength : gapLength;
      final segmentEnd = currentDistance + segmentLength;
      
      if (isDash) {
        final segmentStart = start + unitVector * currentDistance;
        final segmentEndPoint = start + unitVector * math.min(segmentEnd, distance);
        canvas.drawLine(segmentStart, segmentEndPoint, paint);
      }
      
      currentDistance = segmentEnd;
      isDash = !isDash;
    }
  }

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

    // background image if provided
    if (bg != null) {
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

    // 繪製原始航點連線 (手動虛線效果)
    final waypointLinePaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    
    // 手動繪製虛線
    if (wps.length > 1) {
      for (int i = 0; i < wps.length - 1; i++) {
        final start = _meterToCanvas(wps[i].m, size, fs);
        final end = _meterToCanvas(wps[i + 1].m, size, fs);
        _drawDashedLine(canvas, start, end, waypointLinePaint, dashLength: 8, gapLength: 4);
      }
    }

    // 繪製規劃好的平滑路徑 (亮色實線)
    final plannedPathPaint = Paint()
      ..color = const Color(0xFF00E676)  // 亮綠色
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(plannedPath, plannedPathPaint);

    // 可選：繪製路徑採樣點 (用於調試)
    if (pathSamples.isNotEmpty && pathSamples.length < 200) { // 只在點不太多時顯示
      final samplePaint = Paint()
        ..color = const Color(0xFF40FFFF00)  // 半透明黃色
        ..style = PaintingStyle.fill;
      for (final sample in pathSamples) {
        final c = _meterToCanvas(sample.p, size, fs);
        canvas.drawCircle(c, 2, samplePaint);
      }
    }

    // 繪製機器人方向箭頭和footprint
    final Lm = cons.robotLength;
    final Wm = cons.robotWidth;
    for (final p in wps) {
      final c = _meterToCanvas(p.m, size, fs);
      final theta = (p.thetaDeg ?? 0) * math.pi / 180.0;
      final ux = Offset(math.cos(theta), -math.sin(theta));
      final uy = Offset(-ux.dy, ux.dx);

      // 黑色方向箭頭
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

      // 繪製機器人方框（只對起點和終點）
      if (p.kind != WaypointKind.pass) {
        final side = math.max(cons.robotLength, cons.robotWidth);
        final half = side * scale / 2;
        final a = c + ux*half + uy*half;
        final b = c + ux*half - uy*half;
        final d = c - ux*half - uy*half;
        final e = c - ux*half + uy*half;

        final blue = Paint()
          ..color = const Color(0xFF2196F3)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;
        final red = Paint()
          ..color = const Color(0xFFF44336)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

        // front edge (blue)
        canvas.drawLine(a, b, blue);
        // other three edges (red)
        canvas.drawLine(b, d, red);
        canvas.drawLine(d, e, red);
        canvas.drawLine(e, a, red);
      }
    }
        
    // 繪製航點圓圈和標籤
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

    // 原點標記 (0,0) 左下角
    final originCanvas = Offset(ox, oy + fs.height * scale);
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
    return oldDelegate.wps != wps || 
           oldDelegate.bg != bg || 
           oldDelegate.cons != cons ||
           oldDelegate.plannedPath != plannedPath ||
           oldDelegate.pathSamples != pathSamples;
  }
}