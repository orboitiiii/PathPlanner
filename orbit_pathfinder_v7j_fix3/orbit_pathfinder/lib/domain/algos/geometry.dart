
import 'dart:math' as math;
import 'package:flutter/material.dart';

class PathGeomSample {
  final double s; // arc length
  final Offset p;
  final double tangent; // heading (rad), world +x=0
  final double kappa;   // curvature (1/m)
  PathGeomSample(this.s, this.p, this.tangent, this.kappa);
}

/// Simple centripetal Catmull-Rom sampling to polyline, then compute arc-length & curvature.
List<PathGeomSample> sampleSmoothPath(List<Offset> wps, {double ds = 0.02}) {
  if (wps.length < 2) {
    return [PathGeomSample(0.0, wps.first, 0.0, 0.0), PathGeomSample(0.0, wps.last, 0.0, 0.0)];
  }
  // Build dense polyline using Catmull-Rom
  final pts = <Offset>[];
  for (int i = 0; i < wps.length-1; i++) {
    final p0 = i==0 ? wps[i] : wps[i-1];
    final p1 = wps[i];
    final p2 = wps[i+1];
    final p3 = i+2 < wps.length ? wps[i+2] : wps[i+1];
    // centripetal CR, t spacing
    double tj(double ti, Offset a, Offset b) {
      final d = (b - a).distance;
      return ti + math.pow(d, 0.5) as double;
    }
    final t0 = 0.0;
    final t1 = tj(t0, p0, p1);
    final t2 = tj(t1, p1, p2);
    final t3 = tj(t2, p2, p3);
    double t(double tau) {
      // tau in [t1,t2]
      double a1x = (t1 - tau)/(t1 - t0)*p0.dx + (tau - t0)/(t1 - t0)*p1.dx;
      double a1y = (t1 - tau)/(t1 - t0)*p0.dy + (tau - t0)/(t1 - t0)*p1.dy;
      double a2x = (t2 - tau)/(t2 - t1)*p1.dx + (tau - t1)/(t2 - t1)*p2.dx;
      double a2y = (t2 - tau)/(t2 - t1)*p1.dy + (tau - t1)/(t2 - t1)*p2.dy;
      double a3x = (t3 - tau)/(t3 - t2)*p2.dx + (tau - t2)/(t3 - t2)*p3.dx;
      double a3y = (t3 - tau)/(t3 - t2)*p2.dy + (tau - t2)/(t3 - t2)*p3.dy;
      double b1x = (t2 - tau)/(t2 - t0)*a1x + (tau - t0)/(t2 - t0)*a2x;
      double b1y = (t2 - tau)/(t2 - t0)*a1y + (tau - t0)/(t2 - t0)*a2y;
      double b2x = (t3 - tau)/(t3 - t1)*a2x + (tau - t1)/(t3 - t1)*a3x;
      double b2y = (t3 - tau)/(t3 - t1)*a2y + (tau - t1)/(t3 - t1)*a3y;
      double cx = (t2 - tau)/(t2 - t1)*b1x + (tau - t1)/(t2 - t1)*b2x;
      double cy = (t2 - tau)/(t2 - t1)*b1y + (tau - t1)/(t2 - t1)*b2y;
      // pack x in return via static var? Instead, store to global list using closure? Simpler: write to temp list below.
      return cx; // unused
    }
    // Sample N points between p1 and p2
    final N = math.max(4, ((p2 - p1).distance / ds).ceil());
    for (int j = 0; j < N; j++) {
      final tau = (t1*(N-j) + t2*j)/N;
      // manual evaluation (duplicated to get both x,y)
      double a1x = (t1 - tau)/(t1 - 0.0)*p0.dx + (tau - 0.0)/(t1 - 0.0)*p1.dx;
      double a1y = (t1 - tau)/(t1 - 0.0)*p0.dy + (tau - 0.0)/(t1 - 0.0)*p1.dy;
      double a2x = (t2 - tau)/(t2 - t1)*p1.dx + (tau - t1)/(t2 - t1)*p2.dx;
      double a2y = (t2 - tau)/(t2 - t1)*p1.dy + (tau - t1)/(t2 - t1)*p2.dy;
      double a3x = (t3 - tau)/(t3 - t2)*p2.dx + (tau - t2)/(t3 - t2)*p3.dx;
      double a3y = (t3 - tau)/(t3 - t2)*p2.dy + (tau - t2)/(t3 - t2)*p3.dy;
      double b1x = (t2 - tau)/(t2 - 0.0)*a1x + (tau - 0.0)/(t2 - 0.0)*a2x;
      double b1y = (t2 - tau)/(t2 - 0.0)*a1y + (tau - 0.0)/(t2 - 0.0)*a2y;
      double b2x = (t3 - tau)/(t3 - t1)*a2x + (tau - t1)/(t3 - t1)*a3x;
      double b2y = (t3 - tau)/(t3 - t1)*a2y + (tau - t1)/(t3 - t1)*a3y;
      double cx = (t2 - tau)/(t2 - t1)*b1x + (tau - t1)/(t2 - t1)*b2x;
      double cy = (t2 - tau)/(t2 - t1)*b1y + (tau - t1)/(t2 - t1)*b2y;
      pts.add(Offset(cx, cy));
    }
  }
  pts.add(wps.last);
  // Build arc-length and curvature from polyline
  final out = <PathGeomSample>[];
  double s=0.0;
  for(int i=0;i<pts.length;i++){
    if(i>0) s += (pts[i]-pts[i-1]).distance;
    final tang = i<pts.length-1 ? math.atan2(pts[i+1].dy-pts[i].dy, pts[i+1].dx-pts[i].dx)
                                : math.atan2(pts[i].dy-pts[i-1].dy, pts[i].dx-pts[i-1].dx);
    double kappa=0.0;
    if (i>0 && i<pts.length-1){
      final a=pts[i]-pts[i-1], b=pts[i+1]-pts[i];
      final cross = a.dx*b.dy - a.dy*b.dx;
      final al = a.distance; final bl = b.distance; final cl = (pts[i+1]-pts[i-1]).distance;
      final area2 = cross.abs();
      if (al>1e-6 && bl>1e-6 && cl>1e-6){
        kappa = (2*cross)/(al*bl*cl);
      }
    }
    out.add(PathGeomSample(s, pts[i], tang, kappa));
  }
  return out;
}
