
class Constraints {
  double vMax;  // m/s
  double vMin;  // m/s
  double aMax;  // m/s^2
  double aMin;  // m/s^2 (negative for braking)
  double robotLength; // m
  double robotWidth;  // m
  double wheelRadius; // m

  // Swerve-specific
  double trackWidth;   // m (distance between left-right module centers)
  double wheelBase;    // m (front-back module distance)
  double wheelSpeedMax; // m/s (per wheel surface speed)
  double yawRateMax;    // rad/s
  double yawAccelMax;   // rad/s^2
  double mu;            // friction coefficient
  double g;             // gravity m/s^2

  // Desired start/end speeds (optional)
  double vStart;
  double vEnd;

  Constraints({
    this.vMax = 3.0,
    this.vMin = 0.0,
    this.aMax = 4.0,
    this.aMin = -4.0,
    this.robotLength = 0.8,
    this.robotWidth = 0.7,
    this.wheelRadius = 0.0762,
    this.trackWidth = 0.6,
    this.wheelBase = 0.6,
    this.wheelSpeedMax = 15.0,
    this.yawRateMax = 8.0,
    this.yawAccelMax = 30.0,
    this.mu = 1.2,
    this.g = 9.80665,
    this.vStart = 0.0,
    this.vEnd = 0.0,
  });

  Constraints copyWith({
    double? vMax, double? vMin, double? aMax, double? aMin,
    double? robotLength, double? robotWidth, double? wheelRadius,
    double? trackWidth, double? wheelBase,
    double? wheelSpeedMax, double? yawRateMax, double? yawAccelMax,
    double? mu, double? g, double? vStart, double? vEnd,
  }) => Constraints(
    vMax: vMax ?? this.vMax,
    vMin: vMin ?? this.vMin,
    aMax: aMax ?? this.aMax,
    aMin: aMin ?? this.aMin,
    robotLength: robotLength ?? this.robotLength,
    robotWidth: robotWidth ?? this.robotWidth,
    wheelRadius: wheelRadius ?? this.wheelRadius,
    trackWidth: trackWidth ?? this.trackWidth,
    wheelBase: wheelBase ?? this.wheelBase,
    wheelSpeedMax: wheelSpeedMax ?? this.wheelSpeedMax,
    yawRateMax: yawRateMax ?? this.yawRateMax,
    yawAccelMax: yawAccelMax ?? this.yawAccelMax,
    mu: mu ?? this.mu,
    g: g ?? this.g,
    vStart: vStart ?? this.vStart,
    vEnd: vEnd ?? this.vEnd,
  );
}
