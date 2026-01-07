import 'dart:math' as math;

class YawProfile {
  final List<double> s; // arc-length sample
  final List<double> theta; // yaw (rad)
  final List<double> dtheta_ds; // rad/m
  final List<double> ddtheta_ds2; // rad/m^2
  YawProfile(this.s, this.theta, this.dtheta_ds, this.ddtheta_ds2);
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

YawProfile buildYawProfile({
  required List<double> sSample,
  required List<double> tangent, // rad
  required List<double> waypointS, // arc-length of waypoints
  required List<double?> waypointThetaDeg, // nullable deg
}) {
  // θ at waypoints: default to tangent
  final n = sSample.length;
  final theta = List<double>.filled(n, 0.0);
  final dth = List<double>.filled(n, 0.0);
  final ddth = List<double>.filled(n, 0.0);

  // Build per-waypoint desired theta and slope m = dθ/ds (use kappa if theta follows tangent)
  final mLoc = <double>[];
  final tLoc = <double>[];
  for (int i = 0; i < waypointS.length; i++) {
    // find nearest index in sSample
    int idx = 0;
    while (idx < n - 1 && sSample[idx] < waypointS[i]) {
      idx++;
    }
    idx = idx.clamp(0, n - 1);
    final th = (waypointThetaDeg[i] != null)
        ? waypointThetaDeg[i]! * math.pi / 180.0
        : tangent[idx];
    tLoc.add(th);
    // derivative: if orientation is unspecified use kappa (since d(tangent)/ds = curvature).
    final m = (waypointThetaDeg[i] == null)
        ? 0.0 /* we avoid forcing slope to reduce overshoot */
        : 0.0;
    mLoc.add(m);
  }

  // Piecewise cubic Hermite between waypoints
  int seg = 0;
  for (int k = 0; k < n; k++) {
    final s = sSample[k];
    while (seg < waypointS.length - 2 && s > waypointS[seg + 1]) {
      seg++;
    }
    final s0 = waypointS[seg];
    final s1 = waypointS[seg + 1];
    final th0 = tLoc[seg];
    final th1 = tLoc[seg + 1];
    final m0 = mLoc[seg];
    final m1 = mLoc[seg + 1];
    if (s1 - s0 < 1e-6) {
      theta[k] = th0;
      dth[k] = 0;
      ddth[k] = 0;
      continue;
    }
    final u = ((s - s0) / (s1 - s0)).clamp(0.0, 1.0);
    // Hermite basis
    final h00 = (2 * u * u * u - 3 * u * u + 1);
    final h10 = (u * u * u - 2 * u * u + u);
    final h01 = (-2 * u * u * u + 3 * u * u);
    final h11 = (u * u * u - u * u);
    final th =
        h00 * th0 + (s1 - s0) * h10 * m0 + h01 * th1 + (s1 - s0) * h11 * m1;
    // unwrap w.r.t tangent to avoid jumps
    theta[k] = _wrapPi(th);
    final dUDs = 1.0 / (s1 - s0);
    final dh00 = (6 * u * u - 6 * u) * dUDs;
    final dh10 = (3 * u * u - 4 * u + 1) * dUDs;
    final dh01 = (-6 * u * u + 6 * u) * dUDs;
    final dh11 = (3 * u * u - 2 * u) * dUDs;
    dth[k] =
        dh00 * th0 + dh10 * (s1 - s0) * m0 + dh01 * th1 + dh11 * (s1 - s0) * m1;
    // second derivative approx finite diff later
  }
  // ddtheta/ds^2 via central diff
  for (int k = 1; k < n - 1; k++) {
    final ds0 = sSample[k] - sSample[k - 1];
    final ds1 = sSample[k + 1] - sSample[k];
    final v0 = (dth[k] - dth[k - 1]) / (ds0 > 1e-6 ? ds0 : 1e-6);
    final v1 = (dth[k + 1] - dth[k]) / (ds1 > 1e-6 ? ds1 : 1e-6);
    ddth[k] = 0.5 * (v0 + v1);
  }
  return YawProfile(sSample, theta, dth, ddth);
}
