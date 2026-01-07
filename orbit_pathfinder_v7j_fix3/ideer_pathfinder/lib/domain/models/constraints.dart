// lib/domain/models/constraints.dart
class Constraints {
  // Kinematics / limits
  double vMax; // m/s
  double vMin; // m/s
  double aMax; // m/s^2
  double aMin; // m/s^2 (negative for braking)

  // Swerve-specific (used)
  double trackWidth; // m (左右輪距，Y 方向)
  double wheelBase; // m (前後輪距，X 方向)
  double wheelSpeedMax; // m/s (per wheel surface speed)
  double yawRateMax; // rad/s

  // Surface
  double mu; // 摩擦係數 (-)
  double g; // 重力加速度 m/s^2

  /// 向心（橫向）加速度安全係數 (0.0 ~ 1.0)
  /// 實際允許向心加速度 = lateralAccelSafetyFactor * mu * g
  /// 預設 0.7 提供 30% 安全餘量以應對場地條件變化與輪胎磨損
  double lateralAccelSafetyFactor;

  Constraints({
    this.vMax = 3.0,
    this.vMin = 0.0,
    this.aMax = 4.0,
    this.aMin = -4.0,
    this.trackWidth = 0.6,
    this.wheelBase = 0.6,
    this.wheelSpeedMax = 15.0,
    this.yawRateMax = 8.0,
    this.mu = 1.2,
    this.g = 9.80665,
    this.lateralAccelSafetyFactor = 0.7,
  });

  /// 計算基於機器人幾何的最大曲率上限
  /// κ_max ≈ 2 / min(wheelBase, trackWidth)
  double get maxPhysicalCurvature {
    final minDim = trackWidth < wheelBase ? trackWidth : wheelBase;
    return 2.0 / (minDim > 0.1 ? minDim : 0.1);
  }

  Constraints copyWith({
    double? vMax,
    double? vMin,
    double? aMax,
    double? aMin,
    double? trackWidth,
    double? wheelBase,
    double? wheelSpeedMax,
    double? yawRateMax,
    double? mu,
    double? g,
    double? lateralAccelSafetyFactor,
  }) =>
      Constraints(
        vMax: vMax ?? this.vMax,
        vMin: vMin ?? this.vMin,
        aMax: aMax ?? this.aMax,
        aMin: aMin ?? this.aMin,
        trackWidth: trackWidth ?? this.trackWidth,
        wheelBase: wheelBase ?? this.wheelBase,
        wheelSpeedMax: wheelSpeedMax ?? this.wheelSpeedMax,
        yawRateMax: yawRateMax ?? this.yawRateMax,
        mu: mu ?? this.mu,
        g: g ?? this.g,
        lateralAccelSafetyFactor:
            lateralAccelSafetyFactor ?? this.lateralAccelSafetyFactor,
      );
}
