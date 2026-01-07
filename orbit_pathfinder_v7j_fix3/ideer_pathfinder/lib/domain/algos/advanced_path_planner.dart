// lib/domain/algos/advanced_path_planner.dart
//
// 目標：每個航點(關鍵點)速度都必須為 0。
// 作法：幾何依航點「分段」，對每段做時間尺度：
//   - 前向：a_fwd(v) = min( aMax*(1 - v/vMax), aSkidLong )   // Forward limit + Skid limit
//   - 反向：a_brake = min(|aMin|, aSkidLong)                  // 煞車不打滑
//   - 區段剎停上限：u ≤ v_end^2 + 2*a_brake*Δx_to_segment_end
// 速度上限同時受：曲率/角速與 swerve 輪速限制。
// 幾何：支援「每段一個二次貝茲控制點」；未提供則退回 Hermite。
// Yaw：航點鍵值做弧長 Hermite 插值；最後航點錨定到 sMax。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/constraints.dart';
import 'clothoid.dart';

class PathPoint {
  final double s;
  final Offset position;
  final double heading; // 切線角 (rad)
  final double curvature; // κ (1/m)
  final double velocity; // v (m/s)
  final double acceleration; // a (m/s^2)
  final double time; // t (s)
  final double yaw; // 車體朝向 (rad)
  final double yawRate; // ω (rad/s)
  const PathPoint({
    required this.s,
    required this.position,
    required this.heading,
    required this.curvature,
    required this.velocity,
    required this.acceleration,
    required this.time,
    required this.yaw,
    required this.yawRate,
  });
}

class AdvancedPathPlanner {
  /// 生成路徑
  ///
  /// [waypointKinds] 可選，用於指定各航點是否為 passThrough（過點不停）。
  /// - true = passThrough，不強制速度歸零
  /// - false = 正常航點，強制速度歸零
  /// 預設所有航點都是停車點。
  List<PathPoint> generatePath({
    required List<Offset> waypoints,
    required List<double?> waypointYaws, // deg
    required Constraints constraints,
    List<Offset?>? quadCtrls, // 每段一控制點（長度=waypoints.length-1）
    List<bool>? waypointPassThrough, // 各航點是否為 passThrough
    double resolution = 0.01,
  }) {
    if (waypoints.length < 2) return const [];

    // 預設所有航點都停車（起點和終點必然停車）
    final isPassThrough = List<bool>.generate(
      waypoints.length,
      (i) => (i > 0 && i < waypoints.length - 1)
          ? (waypointPassThrough != null && i < waypointPassThrough.length
              ? waypointPassThrough[i]
              : false)
          : false, // 起點和終點永遠不是 passThrough
    );

    try {
      // ---- 幾何 ----
      // 優先使用 Clothoid 曲線（曲率連續），若有控制點則使用貝茲
      final _GeometryPath gp;
      if (quadCtrls != null) {
        gp = _generateGeometryPathQuadratic(
            waypoints, quadCtrls, resolution, constraints);
      } else {
        // 使用 Clothoid 曲線生成曲率連續的路徑
        gp = _generateGeometryPathClothoid(
            waypoints, waypointYaws, resolution, constraints);
      }
      final geom = gp.points;
      if (geom.isEmpty) return const [];

      // ---- 幾何/物理速度上限（曲率/角速 + swerve 輪速）----
      final vCapsGeom = _velocityCaps(geom, constraints);

      // ---- 分段時間尺度（根據航點類型決定邊界速度）----
      final vProf = _timeScaleAnchoredSegments(
        gp: gp,
        vCapGeom: vCapsGeom,
        c: constraints,
        isPassThrough: isPassThrough,
        iters: 3,
      );

      // ---- yaw(s)（終點錨定）----
      final yawSchedule =
          _makeYawSchedule_withEndFix(waypoints, waypointYaws, geom);

      // ---- 輸出 ----
      return _buildFinalPath(geom, vProf, yawSchedule, constraints);
    } catch (_) {
      return _generateFallbackPath(waypoints, waypointYaws, constraints);
    }
  }

  // ======================== 幾何：二次貝茲 ========================
  _GeometryPath _generateGeometryPathQuadratic(
    List<Offset> wps,
    List<Offset?> ctrls,
    double resolution,
    Constraints constraints,
  ) {
    final out = <_GeometryPoint>[];
    final segEnds = <int>[];
    final anchorS = <double>[];

    for (int i = 0; i < wps.length - 1; i++) {
      final p0 = wps[i];
      final p1 = wps[i + 1];
      final Lc = (p1 - p0).distance;
      if (Lc < 1e-9) {
        if (out.isEmpty) out.add(_GeometryPoint(0.0, p0, 0.0, 0.0));
        segEnds.add(out.length - 1);
        anchorS.add(out.last.s);
        continue;
      }

      // 預設控制點：中點 + 少許法向
      final mid = (p0 + p1) * 0.5;
      final dir = (p1 - p0);
      final nrm = Offset(-dir.dy, dir.dx);
      final c = (i < ctrls.length && ctrls[i] != null)
          ? ctrls[i]!
          : (mid + nrm * 0.1);

      final n = (Lc / resolution).ceil().clamp(8, 1500);
      double sAccum = out.isEmpty ? 0.0 : out.last.s;
      Offset? prev;

      for (int j = 0; j < n; j++) {
        final u = n == 1 ? 1.0 : j / (n - 1);
        final bu = _quadPos(p0, c, p1, u);
        final d1 = _quadD1(p0, c, p1, u);
        final d2 = _quadD2(p0, c, p1);
        if (prev != null) sAccum += (bu - prev).distance;
        prev = bu;

        final heading = math.atan2(d1.dy, d1.dx);
        final kappa = _signedCurvature(d1, d2, constraints);
        out.add(_GeometryPoint(sAccum, bu, heading, kappa));
      }
      segEnds.add(out.length - 1);
      anchorS.add(out.last.s);
    }

    if (anchorS.length < wps.length) {
      anchorS.add(out.isNotEmpty ? out.last.s : 0.0);
    }
    return _GeometryPath(out, segEnds, anchorS);
  }

  // ======================== 幾何：Clothoid（曲率連續） ========================
  /// 使用 Clothoid 曲線生成曲率連續的路徑
  /// 這消除了向心加速度突變，提升高速運動穩定性
  _GeometryPath _generateGeometryPathClothoid(
    List<Offset> wps,
    List<double?> yawDegs,
    double resolution,
    Constraints c,
  ) {
    if (wps.length < 2) {
      return _GeometryPath([], [], []);
    }

    // 使用 Clothoid 生成器
    final generator = ClothoidPathGenerator(
      maxCurvature: c.maxPhysicalCurvature,
      maxKappaRate: 3.0, // 1/m² - 曲率變化率限制
    );

    // 將角度轉換為弧度
    final yawRads = yawDegs
        .map((deg) => deg != null ? deg * math.pi / 180.0 : null)
        .toList();

    final samples = generator.generatePath(
      waypoints: wps,
      waypointYaws: yawRads,
      resolution: resolution,
    );

    if (samples.isEmpty) {
      // 退回 Hermite
      return _generateGeometryPathHermite(wps, yawDegs, resolution, c);
    }

    // 轉換為 _GeometryPoint 列表
    final out = <_GeometryPoint>[];
    final segEnds = <int>[];
    final anchorS = <double>[];

    int lastSegIdx = -1;
    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i];

      // 驗證數值有效性
      if (!sample.position.dx.isFinite || !sample.position.dy.isFinite)
        continue;

      out.add(_GeometryPoint(
        sample.s,
        sample.position,
        sample.heading,
        sample.curvature.clamp(-c.maxPhysicalCurvature, c.maxPhysicalCurvature),
      ));

      // 記錄分段結束位置
      if (sample.segmentIndex != lastSegIdx && lastSegIdx >= 0) {
        segEnds.add(i - 1);
        if (out.isNotEmpty) anchorS.add(out[i - 1].s);
      }
      lastSegIdx = sample.segmentIndex;
    }

    // 添加最後一段的結束
    if (out.isNotEmpty) {
      segEnds.add(out.length - 1);
      anchorS.add(out.last.s);
    }

    // 確保 anchorS 長度正確
    while (anchorS.length < wps.length) {
      anchorS.add(out.isNotEmpty ? out.last.s : 0.0);
    }

    return _GeometryPath(out, segEnds, anchorS);
  }

  Offset _quadPos(Offset p0, Offset c, Offset p1, double u) {
    final v0 = (1 - u) * (1 - u);
    final v1 = 2 * (1 - u) * u;
    final v2 = u * u;
    return Offset(v0 * p0.dx + v1 * c.dx + v2 * p1.dx,
        v0 * p0.dy + v1 * c.dy + v2 * p1.dy);
  }

  Offset _quadD1(Offset p0, Offset c, Offset p1, double u) {
    final a = c - p0;
    final b = p1 - c;
    return (a * (2 * (1 - u))) + (b * (2 * u));
  }

  Offset _quadD2(Offset p0, Offset c, Offset p1) {
    final t = p1 - c * 2.0 + p0;
    return t * 2.0;
  }

  // ======================== 幾何：Hermite（後備） ========================
  _GeometryPath _generateGeometryPathHermite(
    List<Offset> wps,
    List<double?> yawDegs,
    double resolution,
    Constraints c,
  ) {
    final out = <_GeometryPoint>[];
    final segEnds = <int>[];
    final anchorS = <double>[];

    for (int i = 0; i < wps.length - 1; i++) {
      final p0 = wps[i];
      final p1 = wps[i + 1];
      final L = (p1 - p0).distance;
      if (L < 1e-9) {
        if (out.isEmpty) out.add(_GeometryPoint(0.0, p0, 0.0, 0.0));
        segEnds.add(out.length - 1);
        anchorS.add(out.last.s);
        continue;
      }

      final chordYaw = math.atan2(p1.dy - p0.dy, p1.dx - p0.dx);
      final yaw0 = (i < yawDegs.length && yawDegs[i] != null)
          ? yawDegs[i]! * math.pi / 180.0
          : chordYaw;
      final yaw1 = (i + 1 < yawDegs.length && yawDegs[i + 1] != null)
          ? yawDegs[i + 1]! * math.pi / 180.0
          : chordYaw;

      final tp = _arcTangentsWithPhysicalKappaLimit(p0, p1, yaw0, yaw1, c);
      final t0 = tp.t0, t1 = tp.t1;

      final dot = ((t0.dx * t1.dx + t0.dy * t1.dy) /
              (t0.distance * t1.distance).clamp(1e-12, double.maxFinite))
          .clamp(-1.0, 1.0);
      final corner = math.acos(dot);
      final cornerFactor = 1.0 + 2.0 * (corner / math.pi);
      final baseN = (L / resolution).ceil().clamp(8, 800);
      final n = (baseN * cornerFactor).ceil().clamp(8, 1500);

      double sAccum = out.isEmpty ? 0.0 : out.last.s;
      Offset? prevPos;

      for (int j = 0; j < n; j++) {
        final u = n == 1 ? 1.0 : j / (n - 1);
        final pos = _hermitePos(p0, p1, t0, t1, u, L);
        final d1u = _hermiteD1_u(p0, p1, t0, t1, u, L);
        final d2u = _hermiteD2_u(p0, p1, t0, t1, u, L);
        if (!pos.dx.isFinite || !pos.dy.isFinite) continue;

        if (prevPos != null) sAccum += (pos - prevPos).distance;
        prevPos = pos;

        final heading = math.atan2(d1u.dy, d1u.dx);
        final kappa = _signedCurvature(d1u, d2u, c);
        out.add(_GeometryPoint(sAccum, pos, heading, kappa));
      }
      segEnds.add(out.length - 1);
      anchorS.add(out.last.s);
    }

    if (anchorS.length < wps.length) {
      anchorS.add(out.isNotEmpty ? out.last.s : 0.0);
    }
    return _GeometryPath(out, segEnds, anchorS);
  }

  _TangentPair _arcTangentsWithPhysicalKappaLimit(
    Offset p0,
    Offset p1,
    double yaw0,
    double yaw1,
    Constraints c,
  ) {
    final d = p1 - p0;
    final L = d.distance;
    if (L < 1e-9) {
      final t = Offset(math.cos(yaw0), math.sin(yaw0)) * 1.0;
      return _TangentPair(t, t);
    }

    var dYaw = _wrap(yaw1 - yaw0);

    // 角速/摩擦導出的曲率上限
    final kLimYaw = c.yawRateMax / math.max(0.3, c.vMax);
    final kLimFric = (0.7 * c.mu * c.g) / (c.vMax * c.vMax);
    final kLim = math.min(kLimYaw, kLimFric);

    // 圓弧一致估算所需轉角，超過上限則壓制
    final k0 = 2.0 * math.sin(dYaw.abs() / 2.0) / L;
    if (k0 > kLim && kLim > 1e-12) {
      final x = (kLim * L / 2.0).clamp(0.0, 1.0);
      final dYawEff = 2.0 * math.asin(x);
      dYaw = dYaw.sign * dYawEff;
    }

    if (dYaw.abs() < 1e-3) {
      final dir = (d / L);
      final t = dir * 1.0;
      return _TangentPair(t, t);
    }
    final R = L / (2.0 * math.sin(dYaw.abs() / 2.0));
    final h = (4.0 / 3.0) * R * math.tan(dYaw.abs() / 4.0);
    var sHermite = 2.0 * h / L;
    sHermite = sHermite.clamp(0.2, 3.0);

    final t0 = Offset(math.cos(yaw0), math.sin(yaw0)) * sHermite;
    final t1 = Offset(math.cos(yaw1), math.sin(yaw1)) * sHermite;
    return _TangentPair(t0, t1);
  }

  Offset _hermitePos(
      Offset p0, Offset p1, Offset t0, Offset t1, double u, double L) {
    final u2 = u * u, u3 = u2 * u;
    final h00 = 2 * u3 - 3 * u2 + 1;
    final h10 = u * u * u - 2 * u * u + u;
    final h01 = -2 * u * u * u + 3 * u * u;
    final h11 = u * u * u - u * u;
    final m0 = t0 * (0.5 * L);
    final m1 = t1 * (0.5 * L);
    return Offset(
      h00 * p0.dx + h10 * m0.dx + h01 * p1.dx + h11 * m1.dx,
      h00 * p0.dy + h10 * m0.dy + h01 * p1.dy + h11 * m1.dy,
    );
  }

  Offset _hermiteD1_u(
      Offset p0, Offset p1, Offset t0, Offset t1, double u, double L) {
    final u2 = u * u;
    final dh00 = 6 * u * u - 6 * u;
    final dh10 = 3 * u * u - 4 * u + 1;
    final dh01 = -6 * u * u + 6 * u;
    final dh11 = 3 * u * u - 2 * u;
    final m0 = t0 * (0.5 * L);
    final m1 = t1 * (0.5 * L);
    return Offset(
      dh00 * p0.dx + dh10 * m0.dx + dh01 * p1.dx + dh11 * m1.dx,
      dh00 * p0.dy + dh10 * m0.dy + dh01 * p1.dy + dh11 * m1.dy,
    );
  }

  Offset _hermiteD2_u(
      Offset p0, Offset p1, Offset t0, Offset t1, double u, double L) {
    final d2h00 = 12 * u - 6;
    final d2h10 = 6 * u - 4;
    final d2h01 = -12 * u + 6;
    final d2h11 = 6 * u - 2;
    final m0 = t0 * (0.5 * L);
    final m1 = t1 * (0.5 * L);
    return Offset(
      d2h00 * p0.dx + d2h10 * m0.dx + d2h01 * p1.dx + d2h11 * m1.dx,
      d2h00 * p0.dy + d2h10 * m0.dy + d2h01 * p1.dy + d2h11 * m1.dy,
    );
  }

  /// 計算帶符號曲率 κ = (x'y'' - y'x'') / (x'^2 + y'^2)^(3/2)
  /// 並限制在物理可達範圍內
  double _signedCurvature(Offset d1, Offset d2, [Constraints? c]) {
    final x1 = d1.dx, y1 = d1.dy, x2 = d2.dx, y2 = d2.dy;
    final den = math.pow(x1 * x1 + y1 * y1, 1.5).toDouble();
    if (den < 1e-12) return 0.0;
    var kappa = (x1 * y2 - y1 * x2) / den;
    // 限制曲率在物理可達範圍（基於機器人幾何）
    if (c != null) {
      final kappaMax = c.maxPhysicalCurvature;
      kappa = kappa.clamp(-kappaMax, kappaMax);
    }
    return kappa;
  }

  // ======================== 幾何/物理速度上限 ========================
  List<double> _velocityCaps(List<_GeometryPoint> geom, Constraints c) {
    final vCaps = <double>[];
    for (final p in geom) {
      final kAbs = p.curvature.abs();
      double vMax = c.vMax;

      if (kAbs > 1e-9) {
        // 向心加速度上限 → v ≤ sqrt(aC/|k|)
        // 使用可配置的安全係數（預設 0.7 = 30% 餘量）
        final aC = c.lateralAccelSafetyFactor * c.mu * c.g;
        vMax =
            math.min(vMax, math.sqrt((aC / kAbs).clamp(0.0, double.maxFinite)));
        // 車體角速度上限 → v ≤ ω_max/|k|
        vMax = math.min(vMax, c.yawRateMax / kAbs);
      }

      // swerve 模組輪速上限
      vMax = math.min(vMax, _swerveLimitFromKappa(p.curvature, c));

      vCaps.add(math.max(c.vMin, vMax));
    }
    return vCaps;
  }

  double _swerveLimitFromKappa(double kappa, Constraints c) {
    final xh = c.wheelBase / 2.0;
    final yh = c.trackWidth / 2.0;
    final modules = <Offset>[
      Offset(xh, yh),
      Offset(xh, -yh),
      Offset(-xh, yh),
      Offset(-xh, -yh),
    ];
    double vMax = c.vMax;
    for (final r in modules) {
      final den = math
          .sqrt(math.pow(1.0 - kappa * r.dy, 2) + math.pow(kappa * r.dx, 2));
      final vLimit = c.wheelSpeedMax / (den > 1e-12 ? den : 1e-12);
      vMax = math.min(vMax, vLimit);
    }
    return vMax;
  }

  // ======================== 分段時間尺度（以停車點為邊界）========================
  /// 對路徑進行時間縮放
  ///
  /// **關鍵設計**：只有「停車點」（非 passThrough）才作為分段邊界。
  /// passThrough 航點不影響速度規劃，路徑在停車點之間作為連續段落規劃。
  /// 這確保了 passThrough 點的速度曲線與整條路徑一致，沒有突變。
  List<double> _timeScaleAnchoredSegments({
    required _GeometryPath gp,
    required List<double> vCapGeom,
    required Constraints c,
    required List<bool> isPassThrough,
    int iters = 2,
  }) {
    final geom = gp.points;
    final n = geom.length;
    if (n == 0) return const [];

    // ========== 找出所有「停車點」的幾何索引 ==========
    final stopGeomIndices = <int>[0]; // 幾何索引 0 = 起點

    for (int wpIdx = 1; wpIdx < isPassThrough.length - 1; wpIdx++) {
      if (!isPassThrough[wpIdx]) {
        if (wpIdx - 1 < gp.segEnds.length) {
          stopGeomIndices.add(gp.segEnds[wpIdx - 1]);
        }
      }
    }

    stopGeomIndices.add(n - 1);

    // ========== 初始化速度為幾何上限 ==========
    final v = List<double>.generate(n, (i) => vCapGeom[i]);

    // 共同參數
    final aSkidLong = _aSkidMaxLong(c);
    final aBrake = math.min((-c.aMin).abs(), aSkidLong);

    // ========== 在每個停車段內進行速度規劃 ==========
    for (int segIdx = 0; segIdx < stopGeomIndices.length - 1; segIdx++) {
      final i0 = stopGeomIndices[segIdx];
      final i1 = stopGeomIndices[segIdx + 1];
      final m = i1 - i0 + 1;

      if (m <= 1) {
        v[i0] = 0.0;
        continue;
      }

      final vCapLocal = List<double>.filled(m, 0.0);
      for (int k = 0; k < m; k++) {
        final gi = i0 + k;
        final dx = (geom[i1].position - geom[gi].position).distance;
        final capStop =
            math.sqrt((2.0 * aBrake * dx).clamp(0.0, double.maxFinite));
        vCapLocal[k] = math.min(vCapGeom[gi], capStop);
      }

      final u = List<double>.generate(m, (k) => vCapLocal[k] * vCapLocal[k]);
      u[0] = 0.0;
      u[m - 1] = 0.0;

      final ds = List<double>.generate(
        m - 1,
        (k) => (geom[i0 + k + 1].s - geom[i0 + k].s)
            .abs()
            .clamp(1e-9, double.maxFinite),
      );

      double aForwardMotor(double vNow) {
        final r = 1.0 - (vNow / c.vMax);
        return (c.aMax * r).clamp(0.0, c.aMax);
      }

      for (int it = 0; it < iters; it++) {
        for (int k = 0; k < m - 1; k++) {
          final vi = math.sqrt(u[k].clamp(0.0, double.maxFinite));
          final aFwd = math.min(aForwardMotor(vi), aSkidLong);
          final uNext = u[k] + 2.0 * aFwd * ds[k];
          u[k + 1] =
              _min3(u[k + 1], uNext, vCapLocal[k + 1] * vCapLocal[k + 1]);
        }
        for (int k = m - 1; k >= 1; k--) {
          final uPrev = u[k] + 2.0 * aBrake * ds[k - 1];
          u[k - 1] =
              _min3(u[k - 1], uPrev, vCapLocal[k - 1] * vCapLocal[k - 1]);
        }
        u[0] = 0.0;
        u[m - 1] = 0.0;
      }

      for (int k = 0; k < m; k++) {
        v[i0 + k] = math.sqrt(u[k].clamp(0.0, double.maxFinite));
      }
      v[i0] = 0.0;
      v[i1] = 0.0;
    }

    return v;
  }

  double _aSkidMaxLong(Constraints c) {
    // Skid limit：最大縱向不打滑加速度，簡化為 μ g
    return c.mu * c.g;
  }

  // ======================== yaw(s) 插值（終點錨定） ========================
  _YawSchedule? _makeYawSchedule_withEndFix(
    List<Offset> wps,
    List<double?> yawDegs,
    List<_GeometryPoint> geom,
  ) {
    final keys = <double>[];
    final vals = <double>[];
    for (int i = 0; i < wps.length; i++) {
      final y = (i < yawDegs.length) ? yawDegs[i] : null;
      if (y == null) continue;
      final sNear = (i == wps.length - 1)
          ? geom.last.s
          : _nearestSOnGeometry(wps[i], geom);
      keys.add(sNear);
      vals.add(y * math.pi / 180.0);
    }
    if (keys.length < 2) return null;

    final idx = List<int>.generate(keys.length, (i) => i)
      ..sort((a, b) => keys[a].compareTo(keys[b]));
    final sK = [for (final i in idx) keys[i]];
    final yK = [for (final i in idx) vals[i]];
    for (int i = 1; i < yK.length; i++) {
      double d = yK[i] - yK[i - 1];
      while (d > math.pi) {
        yK[i] -= 2 * math.pi;
        d -= 2 * math.pi;
      }
      while (d < -math.pi) {
        yK[i] += 2 * math.pi;
        d += 2 * math.pi;
      }
    }

    final mK = List<double>.filled(yK.length, 0.0);
    if (yK.length >= 2) {
      mK[0] = (yK[1] - yK[0]) / math.max(1e-9, sK[1] - sK[0]);
      mK[mK.length - 1] = (yK.last - yK[mK.length - 2]) /
          math.max(1e-9, sK.last - sK[mK.length - 2]);
    }
    for (int i = 1; i < yK.length - 1; i++) {
      final ds0 = math.max(1e-9, sK[i] - sK[i - 1]);
      final ds1 = math.max(1e-9, sK[i + 1] - sK[i]);
      final s0 = (yK[i] - yK[i - 1]) / ds0;
      final s1 = (yK[i + 1] - yK[i]) / ds1;
      mK[i] = 0.5 * (s0 + s1);
    }
    return _YawSchedule(sK, yK, mK, sMin: geom.first.s, sMax: geom.last.s);
  }

  double _nearestSOnGeometry(Offset w, List<_GeometryPoint> geom) {
    int best = 0;
    double bestD = double.infinity;
    final n = geom.length;
    final step = math.max(1, n ~/ 400);
    for (int i = 0; i < n; i += step) {
      final d = (geom[i].position - w).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    final lo = math.max(0, best - 20);
    final hi = math.min(n - 1, best + 20);
    for (int i = lo; i <= hi; i++) {
      final d = (geom[i].position - w).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return geom[best].s;
  }

  // ======================== 輸出 ========================
  List<PathPoint> _buildFinalPath(
    List<_GeometryPoint> geom,
    List<double> v,
    _YawSchedule? yawSch,
    Constraints c,
  ) {
    final out = <PathPoint>[];
    double tAccum = 0.0;

    for (int i = 0; i < geom.length; i++) {
      final g = geom[i];
      var vel = v[i]; // Mutable for sign flip
      double accel = 0.0, dt = 0.0;

      if (i > 0) {
        final ds = (g.s - geom[i - 1].s).abs().clamp(1e-6, double.maxFinite);
        final vAvg = math.max(1e-3, 0.5 * (v[i] + v[i - 1]));
        dt = ds / vAvg;
        accel = (v[i] - v[i - 1]) / dt;
        accel = accel.clamp(c.aMin, c.aMax);
        tAccum += dt;
      }

      double yaw, yawRate;
      if (yawSch != null) {
        yaw = yawSch.valueAt(g.s);
        final dyawDs = yawSch.derivAt(g.s);
        yawRate = (dyawDs * vel).clamp(-c.yawRateMax, c.yawRateMax);
      } else {
        yaw = g.heading;
        yawRate = (g.curvature * vel).clamp(-c.yawRateMax, c.yawRateMax);
      }

      // [Counter-Intuitive Engineering] Reversing Logic
      // 標準控制器傾向於將 Heading 誤差最小化。若運動方向 (Heading) 與車頭 (Yaw)
      // 相差超過 90 度，控制器會試圖掉頭。
      // 這裡我們 "欺騙" 控制器：將 Heading 翻轉 180 度使其與 Yaw 對齊，
      // 同時將速度設為負值。物理運動向量不變 ((-V) * (-Dir) = +Motion)，
      // 但控制器會認為 "我們正朝目標方向看，只是在倒車"。
      var heading = g.heading;
      var curvature = g.curvature;

      final yawDiff = (yaw - heading).abs();
      // Normalize to [-pi, pi] ish
      final normDiff = _wrap(yawDiff).abs();

      if (normDiff > math.pi / 2) {
        heading = _wrap(heading + math.pi);
        vel = -vel;
        // 反向行駛時，曲率符號定義需反轉以維持角速度正確 (omega = v * k)
        // v變成負，omega保持不變(物理上轉向沒變)，所以k也要變負?
        // omega = v_signed * k_signed.
        // Old: v (+) * k (+). New: v (-) * k (?). result should be same omega.
        // So k must be (-).
        curvature = -curvature;

        // 注意：Accel 也要反向嗎?
        // a = dv/dt. If v curve is flipped...
        // 簡單起見，我們先保留代數 accel (基於 speed profile)，
        // 但因為 v 變負了，若 speed 增加 (0 -> -10)，dv 為負。
        // 原本 accel 是純量 (speed derivative)。
        // 這裡我們需要真實的 signed acceleration。
        // 若前面算的是 speed_accel (always positive when speeding up).
        // 則 signed_accel = speed_accel * sign(vel)?
        // 暫略，只翻轉 velocity 其實足夠大部分控制器運作，但為了嚴謹：
        if (dt > 1e-9 && i > 0) {
          // 重新計算基於 signed velocity 的 acceleration
          // 由於我們是逐點翻轉，需確保前一點也處理過...
          // 這在 loop 中有點困難，因為我們依賴 v[i-1] (原本是正的)。
          // **優化**: 我們應該在 loop 外先決定每一點的 "Reversed" 狀態。
        }
      }

      out.add(PathPoint(
        s: g.s,
        position: g.position,
        heading: heading,
        curvature: curvature,
        velocity: vel,
        acceleration: accel * (vel.sign), // 簡化處理：假設加速方向與速度同向
        time: tAccum,
        yaw: yaw,
        yawRate: yawRate,
      ));
    }
    return out;
  }

  List<PathPoint> _generateFallbackPath(
    List<Offset> wps,
    List<double?> yawsDeg,
    Constraints c,
  ) {
    final out = <PathPoint>[];
    double s = 0.0, t = 0.0;
    for (int i = 0; i < wps.length; i++) {
      if (i > 0) {
        final ds = (wps[i] - wps[i - 1]).distance;
        s += ds;
        final v = math.max(0.1, 0.5 * c.vMax);
        t += ds / v;
      }
      final heading = i < wps.length - 1
          ? math.atan2(wps[i + 1].dy - wps[i].dy, wps[i + 1].dx - wps[i].dx)
          : 0.0;
      final yaw = (i < yawsDeg.length && yawsDeg[i] != null)
          ? (yawsDeg[i]! * math.pi / 180.0)
          : heading;
      out.add(PathPoint(
        s: s,
        position: wps[i],
        heading: heading,
        curvature: 0.0,
        velocity: 0.0, // 航點速度固定為 0
        acceleration: 0.0,
        time: t,
        yaw: yaw,
        yawRate: 0.0,
      ));
    }
    return out;
  }

  double _wrap(double a) {
    var d = a;
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    return d;
  }
}

// ======================== 內部型別 ========================
class _GeometryPoint {
  final double s;
  final Offset position;
  final double heading;
  final double curvature;
  const _GeometryPoint(this.s, this.position, this.heading, this.curvature);
}

class _GeometryPath {
  final List<_GeometryPoint> points;
  // 各段的「結束點索引」（含端點）。第 k 段索引範圍：
  // [k==0 ? 0 : segEnds[k-1] , segEnds[k]]
  final List<int> segEnds;
  final List<double> anchorS;
  const _GeometryPath(this.points, this.segEnds, this.anchorS);
}

class _TangentPair {
  final Offset t0;
  final Offset t1;
  const _TangentPair(this.t0, this.t1);
}

double _min3(double a, double b, double c) => math.min(a, math.min(b, c));

// ======================== Yaw Hermite 插值 ========================
class _YawSchedule {
  final List<double> s; // 鍵點弧長
  final List<double> y; // unwrap 後角度(rad)
  final List<double> m; // dy/ds
  final double sMin;
  final double sMax;
  const _YawSchedule(this.s, this.y, this.m,
      {required this.sMin, required this.sMax});

  double valueAt(double ss) {
    if (s.isEmpty) return 0.0;
    if (ss <= s.first) return y.first;
    if (ss >= s.last) return y.last;
    int i = 0;
    while (i < s.length - 2 && ss > s[i + 1]) {
      i++;
    }
    final s0 = s[i], s1 = s[i + 1];
    final y0 = y[i], y1 = y[i + 1];
    final m0 = m[i], m1 = m[i + 1];
    final ds = (s1 - s0).clamp(1e-9, double.maxFinite);
    final u = ((ss - s0) / ds).clamp(0.0, 1.0);
    final h00 = 2 * u * u * u - 3 * u * u + 1;
    final h10 = u * u * u - 2 * u * u + u;
    final h01 = -2 * u * u * u + 3 * u * u;
    final h11 = u * u * u - u * u;
    var val = h00 * y0 + h10 * ds * m0 + h01 * y1 + h11 * ds * m1;
    while (val > math.pi) {
      val -= 2 * math.pi;
    }
    while (val < -math.pi) {
      val += 2 * math.pi;
    }
    return val;
  }

  /// 計算 yaw(s) 在指定弧長位置的導數 dθ/ds
  /// 邊界處理：使用 Hermite 外插而非直接返回端點斜率，確保平滑過渡
  double derivAt(double ss) {
    if (s.isEmpty) return 0.0;

    // 邊界外使用 Hermite 外插（基於最近的兩個鍵點）
    if (ss <= s.first) {
      if (s.length < 2) return m.first;
      // 使用第一段的 Hermite 導數公式在 u=0 處
      final ds = (s[1] - s[0]).clamp(1e-9, double.maxFinite);
      final frac = ((ss - s.first) / ds).clamp(-0.5, 0.0);
      // 線性外插斜率變化
      return m.first + frac * (m[1] - m.first) * 0.5;
    }
    if (ss >= s.last) {
      if (s.length < 2) return m.last;
      final nEnd = s.length - 1;
      final ds = (s[nEnd] - s[nEnd - 1]).clamp(1e-9, double.maxFinite);
      final frac = ((ss - s.last) / ds).clamp(0.0, 0.5);
      // 線性外插斜率變化
      return m.last + frac * (m.last - m[nEnd - 1]) * 0.5;
    }

    int i = 0;
    while (i < s.length - 2 && ss > s[i + 1]) {
      i++;
    }
    final s0 = s[i], s1 = s[i + 1];
    final y0 = y[i], y1 = y[i + 1];
    final m0 = m[i], m1 = m[i + 1];
    final ds = (s1 - s0).clamp(1e-9, double.maxFinite);
    final u = ((ss - s0) / ds).clamp(0.0, 1.0);
    final dh00 = 6 * u * u - 6 * u;
    final dh10 = 3 * u * u - 4 * u + 1;
    final dh01 = -6 * u * u + 6 * u;
    final dh11 = 3 * u * u - 2 * u;
    final dvalDu = dh00 * y0 + dh10 * ds * m0 + dh01 * y1 + dh11 * ds * m1;
    return dvalDu / ds;
  }
}
