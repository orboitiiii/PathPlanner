
import 'dart:math' as math;

class TimeScalingResult {
  final List<double> s; // m
  final List<double> v; // m/s
  final List<double> a; // m/s^2
  TimeScalingResult(this.s, this.v, this.a);
}

TimeScalingResult timeScale({
  required List<double> s,             // m
  required List<double> kappa,         // 1/m (path curvature)
  required List<double> vStatic,       // static velocity limit (wheel/yaw/chassis)
  required List<double> dtheta_ds,     // rad/m
  required List<double> ddtheta_ds2,   // rad/m^2
  required double aMax,                // m/s^2
  required double aMin,                // m/s^2 (negative)
  required double mu,                  // friction coeff for circle
  required double g,                   // gravity
  required double yawAccelMax,         // rad/s^2
  required double vStart,
  required double vEnd,
}){
  final n = s.length;
  final v = List<double>.filled(n, 0.0);
  final vF = List<double>.filled(n, 0.0);
  final vB = List<double>.filled(n, 0.0);

  final aPos = (double v, double kap, double dth, double ddth){
    // friction circle: |a_t| <= sqrt((μg)^2 - (v^2 κ)^2), cap with aMax
    final alat = (v*v*kap).abs();
    final circle = math.max(0.0, mu*g*mu*g - alat*alat);
    double limit = math.sqrt(circle);
    limit = math.min(limit, aMax);
    // yaw accel: |α| = |θ'' v^2 + θ' a| <= yawAccelMax  => |a| <= (yawAccelMax - |θ''| v^2)/|θ'|
    final dthAbs = dth.abs();
    if (dthAbs > 1e-6){
      final extra = (yawAccelMax - (ddth.abs()*v*v)) / dthAbs;
      if (extra.isFinite) limit = math.min(limit, extra);
    }
    return math.max(0.0, limit);
  };

  final aNeg = (double v, double kap, double dth, double ddth){
    double amin = (-aMin).abs(); // magnitude
    // friction circle
    final alat = (v*v*kap).abs();
    final circle = math.max(0.0, mu*g*mu*g - alat*alat);
    double limit = math.sqrt(circle);
    limit = math.min(limit, amin);
    // yaw accel
    final dthAbs = dth.abs();
    if (dthAbs > 1e-6){
      final extra = (yawAccelMax - (ddth.abs()*v*v)) / dthAbs;
      if (extra.isFinite) limit = math.min(limit, extra);
    }
    return math.max(0.0, limit);
  };

  // Static velocity limits
  for(int i=0;i<n;i++){ v[i] = math.min(vStatic[i], double.maxFinite); }

  // Forward
  vF[0] = math.min(v[0], vStart);
  for(int i=1;i<n;i++){
    final ds = math.max(1e-6, s[i]-s[i-1]);
    final a_allow = aPos(vF[i-1], kappa[i-1], dtheta_ds[i-1], ddtheta_ds2[i-1]);
    vF[i] = math.min(v[i], math.sqrt(math.max(0.0, vF[i-1]*vF[i-1] + 2*a_allow*ds)));
  }
  // Backward
  vB[n-1] = math.min(v[n-1], vEnd);
  for(int i=n-2;i>=0;i--){
    final ds = math.max(1e-6, s[i+1]-s[i]);
    final a_allow = aNeg(vB[i+1], kappa[i+1], dtheta_ds[i+1], ddtheta_ds2[i+1]);
    vB[i] = math.min(v[i], math.sqrt(math.max(0.0, vB[i+1]*vB[i+1] + 2*a_allow*ds)));
  }

  // Final profile = min(static, forward, backward) + compute a
  final vOut = List<double>.filled(n, 0.0);
  final aOut = List<double>.filled(n, 0.0);
  for(int i=0;i<n;i++){
    vOut[i] = math.min(v[i], math.min(vF[i], vB[i]));
  }
  for(int i=1;i<n;i++){
    final ds = math.max(1e-6, s[i]-s[i-1]);
    final dv = vOut[i] - vOut[i-1];
    aOut[i] = 0.5 * (vOut[i] + vOut[i-1]) * (dv/ds); // a = v * dv/ds (avg v)
  }
  return TimeScalingResult(s, vOut, aOut);
}
