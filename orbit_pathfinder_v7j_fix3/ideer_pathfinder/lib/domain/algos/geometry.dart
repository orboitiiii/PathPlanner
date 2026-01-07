import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PathGeomSample {
  final double s; // arc length
  final Offset p;
  final double tangent; // heading (rad), world +x=0
  final double kappa; // curvature (1/m)
  PathGeomSample(this.s, this.p, this.tangent, this.kappa);
}

/// Simple centripetal Catmull-Rom sampling to polyline, then compute arc-length & curvature.
List<PathGeomSample> sampleSmoothPath(List<Offset> wps, {double ds = 0.02}) {
  if (wps.length < 2) {
    return [
      PathGeomSample(0.0, wps.first, 0.0, 0.0),
      PathGeomSample(0.1, wps.length > 1 ? wps.last : wps.first, 0.0, 0.0)
    ];
  }

  // 檢查輸入點的有效性
  for (final wp in wps) {
    if (!wp.dx.isFinite || !wp.dy.isFinite) {
      debugPrint("警告：發現無效的航點座標 $wp");
      return [PathGeomSample(0.0, const Offset(0, 0), 0.0, 0.0)];
    }
  }

  // 如果只有兩個點，直接用線性插值
  if (wps.length == 2) {
    return _linearPath(wps, ds);
  }

  // Build dense polyline using Catmull-Rom
  final pts = <Offset>[];

  for (int i = 0; i < wps.length - 1; i++) {
    final p0 = i == 0 ? wps[i] : wps[i - 1];
    final p1 = wps[i];
    final p2 = wps[i + 1];
    final p3 = i + 2 < wps.length ? wps[i + 2] : wps[i + 1];

    // centripetal CR, t spacing
    double tj(double ti, Offset a, Offset b) {
      final d = (b - a).distance;
      return ti + math.pow(math.max(d, 1e-6), 0.5);
    }

    const t0 = 0.0;
    final t1 = tj(t0, p0, p1);
    final t2 = tj(t1, p1, p2);
    final t3 = tj(t2, p2, p3);

    // 檢查時間參數的有效性
    if (!t1.isFinite || !t2.isFinite || !t3.isFinite || t2 - t1 < 1e-6) {
      // 退化情況，使用線性插值
      final segmentLength = (p2 - p1).distance;
      final N = math.max(4, (segmentLength / ds).ceil());
      for (int j = 0; j < N; j++) {
        final t = j / (N - 1);
        pts.add(Offset.lerp(p1, p2, t)!);
      }
      continue;
    }

    // Sample N points between p1 and p2
    final segmentLength = (p2 - p1).distance;
    final N = math.max(4, (segmentLength / ds).ceil()).clamp(4, 100); // 限制最大點數

    for (int j = 0; j < N; j++) {
      final tau = t1 + (t2 - t1) * j / (N - 1);

      // Catmull-Rom interpolation
      try {
        final a1x =
            (t1 - tau) / (t1 - t0) * p0.dx + (tau - t0) / (t1 - t0) * p1.dx;
        final a1y =
            (t1 - tau) / (t1 - t0) * p0.dy + (tau - t0) / (t1 - t0) * p1.dy;
        final a2x =
            (t2 - tau) / (t2 - t1) * p1.dx + (tau - t1) / (t2 - t1) * p2.dx;
        final a2y =
            (t2 - tau) / (t2 - t1) * p1.dy + (tau - t1) / (t2 - t1) * p2.dy;
        final a3x =
            (t3 - tau) / (t3 - t2) * p2.dx + (tau - t2) / (t3 - t2) * p3.dx;
        final a3y =
            (t3 - tau) / (t3 - t2) * p2.dy + (tau - t2) / (t3 - t2) * p3.dy;

        final b1x = (t2 - tau) / (t2 - t0) * a1x + (tau - t0) / (t2 - t0) * a2x;
        final b1y = (t2 - tau) / (t2 - t0) * a1y + (tau - t0) / (t2 - t0) * a2y;
        final b2x = (t3 - tau) / (t3 - t1) * a2x + (tau - t1) / (t3 - t1) * a3x;
        final b2y = (t3 - tau) / (t3 - t1) * a2y + (tau - t1) / (t3 - t1) * a3y;

        final cx = (t2 - tau) / (t2 - t1) * b1x + (tau - t1) / (t2 - t1) * b2x;
        final cy = (t2 - tau) / (t2 - t1) * b1y + (tau - t1) / (t2 - t1) * b2y;

        if (cx.isFinite && cy.isFinite) {
          pts.add(Offset(cx, cy));
        } else {
          // 如果計算失敗，使用線性插值
          pts.add(Offset.lerp(p1, p2, j / (N - 1))!);
        }
      } catch (e) {
        // 計算錯誤時使用線性插值
        pts.add(Offset.lerp(p1, p2, j / (N - 1))!);
      }
    }
  }

  // 確保最後一個點
  if (pts.isEmpty || (pts.last - wps.last).distance > 1e-3) {
    pts.add(wps.last);
  }

  // 如果點太少，補充一些點
  if (pts.length < 10) {
    return _linearPath(wps, ds);
  }

  // Build arc-length and curvature from polyline
  return _computeGeometry(pts);
}

/// 線性路徑生成（用於簡單情況）
List<PathGeomSample> _linearPath(List<Offset> wps, double ds) {
  final samples = <PathGeomSample>[];
  double s = 0.0;

  samples.add(PathGeomSample(0.0, wps.first, 0.0, 0.0));

  for (int i = 1; i < wps.length; i++) {
    final start = wps[i - 1];
    final end = wps[i];
    final segmentLength = (end - start).distance;
    final tangent = math.atan2(end.dy - start.dy, end.dx - start.dx);

    if (segmentLength > ds) {
      final numPoints = (segmentLength / ds).ceil();
      for (int j = 1; j <= numPoints; j++) {
        final t = j / numPoints;
        final p = Offset.lerp(start, end, t)!;
        s += segmentLength / numPoints;
        samples.add(PathGeomSample(s, p, tangent, 0.0));
      }
    } else {
      s += segmentLength;
      samples.add(PathGeomSample(s, end, tangent, 0.0));
    }
  }

  return samples;
}

/// 計算幾何屬性（弧長、切線、曲率）
List<PathGeomSample> _computeGeometry(List<Offset> pts) {
  if (pts.length < 2) {
    return [PathGeomSample(0.0, pts.first, 0.0, 0.0)];
  }

  final out = <PathGeomSample>[];
  double s = 0.0;

  for (int i = 0; i < pts.length; i++) {
    // 累積弧長
    if (i > 0) {
      final ds = (pts[i] - pts[i - 1]).distance;
      s += ds;
    }

    // 計算切線角度
    double tangent = 0.0;
    if (i < pts.length - 1) {
      final dx = pts[i + 1].dx - pts[i].dx;
      final dy = pts[i + 1].dy - pts[i].dy;
      tangent = math.atan2(dy, dx);
    } else if (i > 0) {
      final dx = pts[i].dx - pts[i - 1].dx;
      final dy = pts[i].dy - pts[i - 1].dy;
      tangent = math.atan2(dy, dx);
    }

    // 計算曲率
    double kappa = 0.0;
    if (i > 0 && i < pts.length - 1) {
      final p1 = pts[i - 1];
      final p2 = pts[i];
      final p3 = pts[i + 1];

      final a = p2 - p1;
      final b = p3 - p2;
      final al = a.distance;
      final bl = b.distance;

      if (al > 1e-6 && bl > 1e-6) {
        // 使用向量叉積計算曲率
        final cross = a.dx * b.dy - a.dy * b.dx;
        final cl = (p3 - p1).distance;

        if (cl > 1e-6) {
          kappa = 2 * cross / (al * bl * cl);
          // 限制曲率範圍：κ_max = 5.0 (1/m) 對應 R_min = 0.2m
          // 這是保守值，實際應該由 Constraints.maxPhysicalCurvature 提供
          const kappaMax = 5.0;
          kappa = kappa.clamp(-kappaMax, kappaMax);
        }
      }
    }

    // 驗證所有值都是有限的
    if (!s.isFinite) s = 0.0;
    if (!tangent.isFinite) tangent = 0.0;
    if (!kappa.isFinite) kappa = 0.0;

    out.add(PathGeomSample(s, pts[i], tangent, kappa));
  }

  return out;
}
