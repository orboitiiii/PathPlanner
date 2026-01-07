// lib/domain/algos/clothoid.dart
//
// Clothoid（迴旋曲線/Euler 螺線）曲線實作
// 特性：曲率隨弧長線性變化，κ(s) = κ₀ + (κ₁ - κ₀) × s / L
// 這確保了曲率連續性，消除向心加速度突變。

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Clothoid 曲線段
/// 從曲率 kappa0 變化到 kappa1，長度為 length
class ClothoidSegment {
  final Offset startPos;
  final double startHeading; // rad
  final double kappa0; // 起始曲率 (1/m)
  final double kappa1; // 終點曲率 (1/m)
  final double length; // 弧長 (m)

  const ClothoidSegment({
    required this.startPos,
    required this.startHeading,
    required this.kappa0,
    required this.kappa1,
    required this.length,
  });

  /// 曲率變化率 (1/m²)
  double get kappaRate => (length > 1e-9) ? (kappa1 - kappa0) / length : 0.0;

  /// 在弧長 s 處的曲率
  double curvatureAt(double s) {
    final sNorm = s.clamp(0.0, length);
    return kappa0 + kappaRate * sNorm;
  }

  /// 在弧長 s 處的航向角
  double headingAt(double s) {
    final sNorm = s.clamp(0.0, length);
    // θ(s) = θ₀ + κ₀s + (κ₁-κ₀)s²/(2L)
    return startHeading + kappa0 * sNorm + kappaRate * sNorm * sNorm / 2.0;
  }

  /// 在弧長 s 處的位置（使用 Fresnel 積分近似）
  Offset positionAt(double s) {
    final sNorm = s.clamp(0.0, length);
    // 使用數值積分計算位置
    return _integratePosition(sNorm, 100);
  }

  /// 數值積分計算位置
  Offset _integratePosition(double s, int steps) {
    double x = startPos.dx;
    double y = startPos.dy;
    final ds = s / steps;

    for (int i = 0; i < steps; i++) {
      final sMid = (i + 0.5) * ds;
      final theta = headingAt(sMid);
      x += math.cos(theta) * ds;
      y += math.sin(theta) * ds;
    }

    return Offset(x, y);
  }
}

/// Clothoid 路徑生成器
///
/// 給定航點列表，生成曲率連續的路徑
class ClothoidPathGenerator {
  /// 最大曲率限制 (1/m)
  final double maxCurvature;

  /// 最大曲率變化率限制 (1/m²)
  final double maxKappaRate;

  ClothoidPathGenerator({
    this.maxCurvature = 3.0,
    this.maxKappaRate = 5.0,
  });

  /// 生成 Clothoid 路徑點
  ///
  /// [waypoints] 航點列表
  /// [waypointYaws] 各航點的偏航角（rad），null 表示自動計算
  /// [resolution] 弧長解析度 (m)
  ///
  /// 返回 (arclength, position, heading, curvature) 的列表
  List<ClothoidSample> generatePath({
    required List<Offset> waypoints,
    required List<double?> waypointYaws,
    double resolution = 0.02,
  }) {
    if (waypoints.length < 2) return [];

    final samples = <ClothoidSample>[];
    final segments = _buildSegments(waypoints, waypointYaws);

    double sAccum = 0.0;
    for (int segIdx = 0; segIdx < segments.length; segIdx++) {
      final seg = segments[segIdx];
      final n = (seg.length / resolution).ceil().clamp(5, 500);

      for (int j = 0; j < n; j++) {
        final t = (j == n - 1) ? 1.0 : j / (n - 1);
        final sLocal = t * seg.length;
        final pos = seg.positionAt(sLocal);
        final heading = seg.headingAt(sLocal);
        final kappa = seg.curvatureAt(sLocal);

        // 驗證數值有效性
        if (!pos.dx.isFinite || !pos.dy.isFinite) continue;

        samples.add(ClothoidSample(
          s: sAccum + sLocal,
          position: pos,
          heading: heading,
          curvature: kappa,
          segmentIndex: segIdx,
        ));
      }
      sAccum += seg.length;
    }

    // 確保最後一點
    if (samples.isNotEmpty && waypoints.length >= 2) {
      final lastWp = waypoints.last;
      final lastSample = samples.last;
      if ((lastSample.position - lastWp).distance > 0.01) {
        samples.add(ClothoidSample(
          s: sAccum,
          position: lastWp,
          heading: lastSample.heading,
          curvature: 0.0,
          segmentIndex: segments.length - 1,
        ));
      }
    }

    return samples;
  }

  /// 構建 Clothoid 段列表
  List<ClothoidSegment> _buildSegments(
    List<Offset> waypoints,
    List<double?> waypointYaws,
  ) {
    final segments = <ClothoidSegment>[];
    final n = waypoints.length;

    // 計算每個航點的切線方向
    final headings = <double>[];
    for (int i = 0; i < n; i++) {
      if (waypointYaws.length > i && waypointYaws[i] != null) {
        headings.add(waypointYaws[i]!);
      } else {
        // 自動計算：使用相鄰航點的弦向方向
        if (i == 0 && n > 1) {
          headings.add(_chordHeading(waypoints[0], waypoints[1]));
        } else if (i == n - 1 && n > 1) {
          headings.add(_chordHeading(waypoints[n - 2], waypoints[n - 1]));
        } else if (i > 0 && i < n - 1) {
          // 使用前後航點的平均方向
          final h1 = _chordHeading(waypoints[i - 1], waypoints[i]);
          final h2 = _chordHeading(waypoints[i], waypoints[i + 1]);
          headings.add(_averageAngle(h1, h2));
        } else {
          headings.add(0.0);
        }
      }
    }

    // 計算目標曲率（基於航向角變化）
    final targetCurvatures = <double>[];
    for (int i = 0; i < n; i++) {
      if (i == 0 || i == n - 1) {
        targetCurvatures.add(0.0); // 端點曲率為零
      } else {
        // 估計曲率：使用相鄰段的航向變化
        final prevDist = (waypoints[i] - waypoints[i - 1]).distance;
        final nextDist = (waypoints[i + 1] - waypoints[i]).distance;
        final dTheta = _normalizeAngle(headings[i + 1] - headings[i - 1]);
        final avgDist = (prevDist + nextDist) / 2.0;
        var kappa = avgDist > 1e-6 ? dTheta / avgDist : 0.0;
        kappa = kappa.clamp(-maxCurvature, maxCurvature);
        targetCurvatures.add(kappa);
      }
    }

    // 構建 Clothoid 段（確保 heading 連續性）
    double currentHeading = headings.isNotEmpty ? headings[0] : 0.0;
    Offset currentPos = waypoints.isNotEmpty ? waypoints[0] : Offset.zero;

    for (int i = 0; i < n - 1; i++) {
      final p1 = waypoints[i + 1];
      final length = (p1 - currentPos).distance;

      if (length < 1e-6) continue;

      // 起始和終點曲率
      final k0 = targetCurvatures[i];
      final k1 = targetCurvatures[i + 1];

      // 限制曲率變化率
      final maxDeltaK = maxKappaRate * length;
      var dk = (k1 - k0).clamp(-maxDeltaK, maxDeltaK);
      final limitedK1 = k0 + dk;

      final segment = ClothoidSegment(
        startPos: currentPos,
        startHeading: currentHeading,
        kappa0: k0,
        kappa1: limitedK1,
        length: length,
      );
      segments.add(segment);

      // 更新下一段的起始狀態（確保連續性）
      currentPos = segment.positionAt(length);
      currentHeading = segment.headingAt(length);
    }

    return segments;
  }

  double _chordHeading(Offset a, Offset b) {
    return math.atan2(b.dy - a.dy, b.dx - a.dx);
  }

  double _averageAngle(double a, double b) {
    final dx = math.cos(a) + math.cos(b);
    final dy = math.sin(a) + math.sin(b);
    return math.atan2(dy, dx);
  }

  double _normalizeAngle(double angle) {
    while (angle > math.pi) angle -= 2 * math.pi;
    while (angle < -math.pi) angle += 2 * math.pi;
    return angle;
  }
}

/// Clothoid 路徑採樣點
class ClothoidSample {
  final double s; // 弧長
  final Offset position; // 位置
  final double heading; // 航向角 (rad)
  final double curvature; // 曲率 (1/m)
  final int segmentIndex; // 所屬分段索引

  const ClothoidSample({
    required this.s,
    required this.position,
    required this.heading,
    required this.curvature,
    required this.segmentIndex,
  });
}
