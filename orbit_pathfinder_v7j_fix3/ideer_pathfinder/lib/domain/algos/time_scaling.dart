import 'dart:math' as math;

class TimeScalingResult {
  final List<double> s; // m
  final List<double> v; // m/s
  final List<double> a; // m/s^2
  TimeScalingResult(this.s, this.v, this.a);
}

TimeScalingResult timeScale({
  required List<double> s, // m
  required List<double> kappa, // 1/m (path curvature)
  required List<double> vStatic, // static velocity limit (wheel/yaw/chassis)
  required List<double> dtheta_ds, // rad/m
  required List<double> ddtheta_ds2, // rad/m^2
  required double aMax, // m/s^2
  required double aMin, // m/s^2 (negative)
  required double mu, // friction coeff for circle
  required double g, // gravity
  required double yawAccelMax, // rad/s^2
  required double vStart,
  required double vEnd,
}) {
  final n = s.length;
  if (n < 2) {
    return TimeScalingResult([0.0], [0.0], [0.0]);
  }

  // 輸入驗證
  for (int i = 0; i < n; i++) {
    if (!s[i].isFinite ||
        !kappa[i].isFinite ||
        !vStatic[i].isFinite ||
        !dtheta_ds[i].isFinite ||
        !ddtheta_ds2[i].isFinite) {
      print("警告：時間縮放輸入數據無效，索引: $i");
      // 使用安全的預設值
      return TimeScalingResult(
        List.generate(n, (i) => i * 0.1),
        List.filled(n, 1.0),
        List.filled(n, 0.0),
      );
    }
  }

  final v = List<double>.filled(n, 0.0);
  final vF = List<double>.filled(n, 0.0);
  final vB = List<double>.filled(n, 0.0);

  // 確保輸入參數有效
  final safeAMax = math.max(aMax.abs(), 0.1);
  final safeAMin = math.min(aMin, -0.1);
  final safeMu = math.max(mu, 0.1);
  final safeG = math.max(g, 1.0);
  final safeYawAccelMax = math.max(yawAccelMax, 1.0);

  double aPos(double v, double kap, double dth, double ddth) {
    v = math.max(v.abs(), 0.0);
    kap = kap.isFinite ? kap : 0.0;
    dth = dth.isFinite ? dth.abs() : 0.0;
    ddth = ddth.isFinite ? ddth.abs() : 0.0;

    // friction circle: |a_t| <= sqrt((μg)^2 - (v^2 κ)^2), cap with aMax
    final alat = v * v * kap.abs();
    final circleLimit = safeMu * safeG;
    final availableAccel =
        math.max(0.0, circleLimit * circleLimit - alat * alat);
    double limit = math.sqrt(availableAccel);
    limit = math.min(limit, safeAMax);

    // yaw accel: |α| = |θ'' v^2 + θ' a| <= yawAccelMax  => |a| <= (yawAccelMax - |θ''| v^2)/|θ'|
    if (dth > 1e-6) {
      final yawConstraint = (safeYawAccelMax - ddth * v * v) / dth;
      if (yawConstraint.isFinite && yawConstraint > 0) {
        limit = math.min(limit, yawConstraint);
      }
    }

    return math.max(0.0, limit);
  }

  double aNeg(double v, double kap, double dth, double ddth) {
    v = math.max(v.abs(), 0.0);
    kap = kap.isFinite ? kap : 0.0;
    dth = dth.isFinite ? dth.abs() : 0.0;
    ddth = ddth.isFinite ? ddth.abs() : 0.0;

    double amin = safeAMin.abs(); // magnitude
    // friction circle
    final alat = v * v * kap.abs();
    final circleLimit = safeMu * safeG;
    final availableAccel =
        math.max(0.0, circleLimit * circleLimit - alat * alat);
    double limit = math.sqrt(availableAccel);
    limit = math.min(limit, amin);

    // yaw accel
    if (dth > 1e-6) {
      final yawConstraint = (safeYawAccelMax - ddth * v * v) / dth;
      if (yawConstraint.isFinite && yawConstraint > 0) {
        limit = math.min(limit, yawConstraint);
      }
    }

    return math.max(0.0, limit);
  }

  // Static velocity limits
  for (int i = 0; i < n; i++) {
    v[i] = math.min(math.max(vStatic[i], 0.0), 10.0); // 限制最大速度避免極值
  }

  // Forward pass
  vF[0] = math.min(v[0], math.max(vStart, 0.0));
  for (int i = 1; i < n; i++) {
    final ds = math.max(1e-6, s[i] - s[i - 1]);
    final aAllow =
        aPos(vF[i - 1], kappa[i - 1], dtheta_ds[i - 1], ddtheta_ds2[i - 1]);
    final vNext =
        math.sqrt(math.max(0.0, vF[i - 1] * vF[i - 1] + 2 * aAllow * ds));
    vF[i] = math.min(v[i], vNext);

    // 驗證結果
    if (!vF[i].isFinite) {
      vF[i] = math.min(1.0, v[i]);
    }
  }

  // Backward pass
  vB[n - 1] = math.min(v[n - 1], math.max(vEnd, 0.0));
  for (int i = n - 2; i >= 0; i--) {
    final ds = math.max(1e-6, s[i + 1] - s[i]);
    final aAllow =
        aNeg(vB[i + 1], kappa[i + 1], dtheta_ds[i + 1], ddtheta_ds2[i + 1]);
    final vNext =
        math.sqrt(math.max(0.0, vB[i + 1] * vB[i + 1] + 2 * aAllow * ds));
    vB[i] = math.min(v[i], vNext);

    // 驗證結果
    if (!vB[i].isFinite) {
      vB[i] = math.min(1.0, v[i]);
    }
  }

  // Final profile = min(static, forward, backward) + compute a
  final vOut = List<double>.filled(n, 0.0);
  final aOut = List<double>.filled(n, 0.0);

  for (int i = 0; i < n; i++) {
    vOut[i] = math.min(v[i], math.min(vF[i], vB[i]));
    // 確保速度為正且有限
    vOut[i] = math.max(0.0, vOut[i]);
    if (!vOut[i].isFinite) vOut[i] = 0.1;
  }

  // 計算加速度
  aOut[0] = 0.0;
  for (int i = 1; i < n; i++) {
    final ds = math.max(1e-6, s[i] - s[i - 1]);
    final dv = vOut[i] - vOut[i - 1];
    final avgV = math.max(1e-6, 0.5 * (vOut[i] + vOut[i - 1]));
    aOut[i] = avgV * (dv / ds); // a = v * dv/ds (avg v)

    // 限制加速度範圍
    aOut[i] = aOut[i].clamp(-10.0, 10.0);
    if (!aOut[i].isFinite) aOut[i] = 0.0;
  }

  return TimeScalingResult(s, vOut, aOut);
}
