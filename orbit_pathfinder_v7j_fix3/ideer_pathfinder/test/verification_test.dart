import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Copying necessary simplified classes to avoid complex dependencies if imports fail,
// but ideally we import them. Since this is a specialized test in the workspace,
// we'll try to import the domain files.
// Assuming the file is at c:\orbit_pathfinder_mvp_flutter_v7j_fix3_scroll\orbit_pathfinder_v7j_fix3\ideer_pathfinder\test\verification_test.dart

import '../lib/domain/algos/advanced_path_planner.dart';
import '../lib/domain/models/constraints.dart';
import '../lib/domain/models/field_config.dart';

// REPLICATING _interpolatePathPoint from main.dart
double _wrapAngleDiff(double a) {
  var d = a;
  while (d > math.pi) {
    d -= 2 * math.pi;
  }
  while (d < -math.pi) {
    d += 2 * math.pi;
  }
  return d;
}

PathPoint? interpolatePathPoint(double targetTime, List<PathPoint> points) {
  if (points.isEmpty) return null;
  if (targetTime <= points.first.time) return points.first;
  if (targetTime >= points.last.time) return points.last;
  for (int i = 0; i < points.length - 1; i++) {
    final p1 = points[i], p2 = points[i + 1];
    if (targetTime >= p1.time && targetTime <= p2.time) {
      final dt = (p2.time - p1.time);
      final r = dt > 1e-6 ? (targetTime - p1.time) / dt : 0.0;
      return PathPoint(
        s: p1.s + (p2.s - p1.s) * r,
        position: Offset.lerp(p1.position, p2.position, r)!,
        heading: p1.heading + _wrapAngleDiff(p2.heading - p1.heading) * r,
        curvature: p1.curvature + (p2.curvature - p1.curvature) * r,
        velocity: p1.velocity + (p2.velocity - p1.velocity) * r,
        acceleration: p1.acceleration + (p2.acceleration - p1.acceleration) * r,
        time: targetTime,
        yaw: p1.yaw + _wrapAngleDiff(p2.yaw - p1.yaw) * r,
        yawRate: p1.yawRate + (p2.yawRate - p1.yawRate) * r,
      );
    }
  }
  return null;
}

void main() {
  test('Straight Line Path Verification', () {
    // 1. Setup - Straight path 10m
    final waypoints = [Offset(0, 0), Offset(10, 0)];
    final yaws = [0.0, 0.0];
    final constraints = Constraints(
      vMax: 2.0,
      aMax: 2.0,
      vMin: 0.0,
      aMin: -2.0,
      yawRateMax: 360.0,
      trackWidth: 0.5,
      wheelBase: 0.5,
      wheelSpeedMax: 5.0,
      mu: 1.0,
      g: 9.8,
    );

    // 2. Generate
    final planner = AdvancedPathPlanner();
    final path = planner.generatePath(
      waypoints: waypoints,
      waypointYaws: yaws,
      constraints: constraints,
      resolution: 0.01,
    );

    expect(path.isNotEmpty, true, reason: "Path should not be empty");

    // 3. Analyze Physics Model
    final totalTime = path.last.time;
    print(
        'Path Total Time: ${totalTime.toStringAsFixed(4)} s (Expected ~6.5s due to motor curve)');

    expect(totalTime, closeTo(6.49, 0.1),
        reason: "Total time calculation should match motor curve model");

    // 4. Resample (Simulate CSV Export)
    const dt = 0.02;
    final resampled = <PathPoint>[];
    for (int i = 0;; i++) {
      final t = math.min(i * dt, totalTime);
      final p = interpolatePathPoint(t, path);
      if (p != null) resampled.add(p);
      if (t >= totalTime - 1e-9) break;
    }

    // 7. Check Position Accuracy
    final last = resampled.last;
    print('End Pos X: ${last.position.dx.toStringAsFixed(4)} (Expected 10.0)');
    expect(last.position.dx, closeTo(10.0, 0.1));
  });

  test('Menger Curvature Check (Turn)', () {
    final wps = [Offset(0, 0), Offset(5, 5)];
    final yaws = [0.0, 90.0];

    final c = Constraints(vMax: 1, aMax: 1, vMin: 0, aMin: -1);
    final planner = AdvancedPathPlanner();
    final path = planner.generatePath(
        waypoints: wps, waypointYaws: yaws, constraints: c);

    double maxK = 0;
    for (final p in path) maxK = math.max(maxK, p.curvature.abs());
    print('Turn Max Curvature: $maxK');

    expect(maxK.isFinite, true);
  });
}
