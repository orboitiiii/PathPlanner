import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';

class CsvRow {
  final double t;
  final double x;
  final double y;
  final double heading; // radians (tangent)
  final double thetaDeg; // waypoint-orientation (deg)
  final double v;
  final double a;
  CsvRow(this.t, this.x, this.y, this.heading, this.thetaDeg, this.v, this.a);
}

class CsvExporter {
  static Future<File> export(List<Offset> samples, List<double> thetaDegs) async {
    // 20 ms sampling, assume simple constant speed 1 m/s (can be replaced by constraints panel)
    const dt = 0.02;
    final rows = <CsvRow>[];
    double t = 0.0;
    double lastV = 0.0;
    for (int i = 0; i < samples.length; i++) {
      final p = samples[i];
      double v = 0.0;
      double heading = 0.0;
      if (i > 0) {
        final d = samples[i] - samples[i - 1];
        v = d.distance / dt;
        heading = atan2(d.dy, d.dx);
      }
      final a = (v - lastV) / dt;
      final th = (i < thetaDegs.length) ? thetaDegs[i] : 0.0;
      rows.add(CsvRow(t, p.dx, p.dy, heading, th, v, a));
      lastV = v;
      t += dt;
    }
    final buf = StringBuffer();
    buf.writeln("t,x,y,heading_rad,theta_deg,v,a,omega,kappa");
    for (final r in rows) {
      buf.writeln("${r.t.toStringAsFixed(3)},${r.x.toStringAsFixed(3)},${r.y.toStringAsFixed(3)},"
          "${r.heading.toStringAsFixed(5)},${r.v.toStringAsFixed(3)},${r.a.toStringAsFixed(3)}");
    }
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final f = File("${dir.path}${Platform.pathSeparator}orbit_samples.csv");
    return f.writeAsString(buf.toString());
  }
}
