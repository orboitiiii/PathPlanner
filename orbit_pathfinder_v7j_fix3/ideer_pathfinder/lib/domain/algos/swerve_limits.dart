import 'dart:math' as math;

class SwerveLimitResult {
  final List<double> vStat; // static v limit per s
  SwerveLimitResult(this.vStat);
}

double _wrapPi(double a) {
  while (a > math.pi) {
    a -= 2 * math.pi;
  }
  while (a < -math.pi) {
    a += 2 * math.pi;
  }
  return a;
}

SwerveLimitResult swerveVelocityBounds({
  required List<double> s,
  required List<double> tangent, // rad
  required List<double>
      kappa, // 1/m (path curvature, for lateral acceleration only)
  required List<double> theta, // yaw rad
  required List<double> dtheta_ds, // rad/m
  required double trackWidth,
  required double wheelBase,
  required double vWheelMax,
  required double vMaxChassis,
  required double yawRateMax,
}) {
  final n = s.length;
  final vlim = List<double>.filled(n, vMaxChassis);
  // 模組位置在機器人座標系中（x = 前進方向, y = 左側）
  // wheelBase = 前後輪距（X 方向），trackWidth = 左右輪距（Y 方向）
  final halfX = wheelBase / 2.0; // 前後方向半距
  final halfY = trackWidth / 2.0; // 左右方向半距
  final mods = [
    [halfX, halfY], // 左前 (Front-Left)
    [halfX, -halfY], // 右前 (Front-Right)
    [-halfX, halfY], // 左後 (Rear-Left)
    [-halfX, -halfY], // 右後 (Rear-Right)
  ];
  for (int i = 0; i < n; i++) {
    final delta = _wrapPi(
        theta[i] - tangent[i]); // translational direction in robot frame
    final c = math.cos(delta);
    final sgn = math.sin(delta);
    double facMax = 0.0;
    for (final m in mods) {
      final xi = m[0], yi = m[1];
      final vx = c - dtheta_ds[i] * yi; // dimensionless
      final vy = sgn + dtheta_ds[i] * xi;
      final fac = math.sqrt(vx * vx + vy * vy);
      if (fac > facMax) facMax = fac;
    }
    final limitWheel = vWheelMax / (facMax > 1e-9 ? facMax : 1e9);
    final limitYawRate = (dtheta_ds[i].abs() > 1e-9)
        ? (yawRateMax / dtheta_ds[i].abs())
        : vMaxChassis;
    final limitChassis = vMaxChassis;
    vlim[i] = math.min(limitChassis, math.min(limitWheel, limitYawRate));
  }
  return SwerveLimitResult(vlim);
}
