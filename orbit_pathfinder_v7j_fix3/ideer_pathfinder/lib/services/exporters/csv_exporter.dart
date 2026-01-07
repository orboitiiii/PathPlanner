import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';

import '../../../domain/algos/advanced_path_planner.dart';

class CsvRow {
  final double t;
  final double x;
  final double y;
  final double heading;
  final double thetaDeg;
  final double v;
  final double a;
  final double omega;
  final double kappa;

  CsvRow(this.t, this.x, this.y, this.heading, this.thetaDeg, this.v, this.a,
      this.omega, this.kappa);
}

class CsvExporter {
  // 主要導出方法 - 使用PathPoint數據
  static Future<File> exportPathPoints(List<PathPoint> pathPoints) async {
    if (pathPoints.isEmpty) {
      throw Exception("沒有路徑點數據可導出");
    }

    final rows = <CsvRow>[];

    for (final point in pathPoints) {
      rows.add(CsvRow(
        point.time,
        point.position.dx,
        point.position.dy,
        point.heading,
        point.yaw * 180.0 / pi,
        point.velocity,
        point.acceleration,
        point.yawRate,
        point.curvature,
      ));
    }

    return _writeRowsToFile(rows, "path_points");
  }

  // 原有的簡單導出方法（向後兼容）
  static Future<File> export(
      List<Offset> samples, List<double> thetaDegs) async {
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
      rows.add(CsvRow(t, p.dx, p.dy, heading, th, v, a, 0.0, 0.0));
      lastV = v;
      t += dt;
    }

    return _writeRowsToFile(rows);
  }

  // 詳細導出方法
  static Future<File> exportWithTimeData(
    List<Offset> positions,
    List<double> thetaDegs,
    List<double> velocities,
    List<double> accelerations,
    List<double> times,
  ) async {
    if (positions.isEmpty) {
      throw Exception("沒有位置數據可導出");
    }

    final rows = <CsvRow>[];

    for (int i = 0; i < positions.length; i++) {
      final p = positions[i];
      final t = (i < times.length) ? times[i] : i * 0.02;
      final v = (i < velocities.length) ? velocities[i] : 0.0;
      final a = (i < accelerations.length) ? accelerations[i] : 0.0;
      final thetaDeg = (i < thetaDegs.length) ? thetaDegs[i] : 0.0;

      // 計算切線方向
      double heading = 0.0;
      if (i > 0 && i < positions.length) {
        final prev = (i > 0) ? positions[i - 1] : positions[i];
        final next =
            (i < positions.length - 1) ? positions[i + 1] : positions[i];
        final d = next - prev;
        if (d.distance > 1e-6) {
          heading = atan2(d.dy, d.dx);
        }
      }

      // 計算角速度
      double omega = 0.0;
      if (i > 0 && i < thetaDegs.length - 1) {
        const deltaT = 0.02;
        final dTheta = (thetaDegs[i + 1] - thetaDegs[i - 1]) * pi / 180.0;
        omega = dTheta / (2 * deltaT);
      }

      // 計算曲率
      double kappa = 0.0;
      if (i > 0 && i < positions.length - 1 && v > 1e-6) {
        final p1 = positions[i - 1];
        final p2 = positions[i];
        final p3 = positions[i + 1];

        final a = (p2 - p1).distance;
        final b = (p3 - p2).distance;
        final c = (p3 - p1).distance;

        if (a > 1e-6 && b > 1e-6 && c > 1e-6) {
          final cross = (p2.dx - p1.dx) * (p3.dy - p1.dy) -
              (p2.dy - p1.dy) * (p3.dx - p1.dx);
          final area = cross.abs() / 2;
          kappa = 4 * area / (a * b * c);
          if (cross < 0) kappa = -kappa;
        }
      }

      rows.add(CsvRow(t, p.dx, p.dy, heading, thetaDeg, v, a, omega, kappa));
    }

    return _writeRowsToFile(rows);
  }

  // 寫入檔案
  static Future<File> _writeRowsToFile(List<CsvRow> rows,
      [String prefix = "orbit_path"]) async {
    final buf = StringBuffer();
    // Rigorous Header: time, x, y, yaw(rad), vx, vy, omega(rad/s)
    buf.writeln("time_s,x_m,y_m,yaw_rad,vx_mps,vy_mps,omega_rads");

    for (final r in rows) {
      // Calculate angular components
      final vx = r.v * cos(r.heading);
      final vy = r.v * sin(r.heading);
      final yawRad = r.thetaDeg * pi / 180.0;

      buf.writeln("${r.t.toStringAsFixed(4)},"
          "${r.x.toStringAsFixed(4)},"
          "${r.y.toStringAsFixed(4)},"
          "${yawRad.toStringAsFixed(4)},"
          "${vx.toStringAsFixed(4)},"
          "${vy.toStringAsFixed(4)},"
          "${r.omega.toStringAsFixed(4)}");
    }

    try {
      final dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = "${prefix}_$timestamp.csv";
      final f = File("${dir.path}${Platform.pathSeparator}$fileName");
      return f.writeAsString(buf.toString());
    } catch (e) {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = "${prefix}_$timestamp.csv";
      final f = File("${dir.path}${Platform.pathSeparator}$fileName");
      return f.writeAsString(buf.toString());
    }
  }
}
