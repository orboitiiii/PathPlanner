import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'features/field/widgets/field_canvas.dart';
import 'features/panels/waypoints_panel.dart';
import 'domain/models/field_config.dart';
import 'domain/models/waypoint.dart';
import 'services/exporters/csv_exporter.dart';
import 'domain/algos/geometry.dart';
import 'domain/algos/yaw_profile.dart';
import 'domain/algos/swerve_limits.dart';
import 'domain/algos/time_scaling.dart';
import 'domain/models/constraints.dart';
import 'features/panels/constraints_panel.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orbit Pathfinder (Flutter MVP)',
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late FieldConfig cfg;
  ui.Image? bgImg;
  List<Waypoint> waypoints = [];
  Constraints cons = Constraints();

  @override
  void initState() {
    super.initState();
    cfg = FieldConfig(
      fieldSizeMeters: const Size(17.548250, 8.051902),
      // These numbers match your Reefscape JSON (pixel rect),
      // but we render by fitting meters to canvas directly, so this is only for mapping if needed.
      pixelRect: const Rect.fromLTWH(534, 291, 3466 - 534, 1638 - 291),
      originCorner: OriginCorner.bottomLeft,
    );
    // initial points: start at (0,0) end at (5,0)
    waypoints = [
      Waypoint(const Offset(0, 0), WaypointKind.start, "Start", thetaDeg: 0),
      Waypoint(const Offset(5, 0), WaypointKind.end, "End", thetaDeg: 0),
    ];
    _loadBg(); // ignore errors if image missing
  }

  Future<void> _loadBg() async {
    try {
      final img = await _loadImageFromAsset('assets/images/2025-field.png');
      setState(() => bgImg = img);
    } catch (_) {
      // silently ignore if asset not provided yet
    }
  }

  Future<ui.Image> _loadImageFromAsset(String asset) async {
    final bd = await DefaultAssetBundle.of(context).load(asset);
    final codec = await ui.instantiateImageCodec(bd.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _addPass() {
    final center = Offset(cfg.fieldSizeMeters.width/2, cfg.fieldSizeMeters.height/2);
    final idx = waypoints.where((w)=>w.kind==WaypointKind.pass).length + 1;
    setState(() {
      final copy = List<Waypoint>.from(waypoints);
      copy.insert(copy.length-1, Waypoint(center, WaypointKind.pass, "P$idx"));
      waypoints = copy;
    });
  }

  void _updateStart(double x, double y, double? thetaDeg) {
    setState(() {
      final copy = List<Waypoint>.from(waypoints);
      copy[0] = Waypoint(Offset(x,y), WaypointKind.start, "Start", thetaDeg: thetaDeg ?? copy[0].thetaDeg ?? 0.0);
      waypoints = copy;
    });
  }

  void _updateEnd(double x, double y, double? thetaDeg) {
    setState(() {
      final copy = List<Waypoint>.from(waypoints);
      copy[copy.length-1] = Waypoint(Offset(x,y), WaypointKind.end, "End", thetaDeg: thetaDeg ?? copy.last.thetaDeg ?? 0.0);
      waypoints = copy;
    });
  }

  void _updatePass(int passIdx, double x, double y, double? thetaDeg) {
    final globalIdx = 1 + passIdx;
    if (globalIdx >= 1 && globalIdx <= waypoints.length-2) {
      setState(() {
        final copy = List<Waypoint>.from(waypoints);
        final label = copy[globalIdx].label;
        copy[globalIdx] = Waypoint(Offset(x,y), WaypointKind.pass, label, thetaDeg: thetaDeg ?? copy[globalIdx].thetaDeg ?? 0.0);
        waypoints = copy;
      });
    }
  }

  void _deletePass(int passIdx) {
    final globalIdx = 1 + passIdx;
    if (globalIdx >= 1 && globalIdx <= waypoints.length-2) {
      setState(() {
        final copy = List<Waypoint>.from(waypoints);
        copy.removeAt(globalIdx);
        int k=1; for (int i=1;i<=copy.length-2;i++){ copy[i].label = "P${k++}"; }
        waypoints = copy;
      });
    }
  }


  double _wrapLerpDeg(double a, double b, double t) {
    double d = b - a;
    while (d > 180) d -= 360;
    while (d < -180) d += 360;
    return a + d * t;
  }

  double _tangentDeg(Offset a, Offset b) {
    final r = math.atan2(b.dy - a.dy, b.dx - a.dx);
    return r * 180.0 / math.pi;
  }

  
  Future<void> _exportCsv() async {
    // Build path points
    final pts = waypoints.map((w)=>w.m).toList();
    if (pts.length < 2) return;

    // --- Geometry sampling
    final samples = sampleSmoothPath(pts, ds: 0.02);
    final s = samples.map((e)=>e.s).toList();
    final xy = samples.map((e)=>e.p).toList();
    final tang = samples.map((e)=>e.tangent).toList();
    final kappa = samples.map((e)=>e.kappa).toList();

    // waypoint s-positions
    final wpS = <double>[]; final wpTheta = <double?>[];
    for (final w in waypoints){
      // find nearest s
      double best=0, bestd=1e9;
      for (final smp in samples){
        final d=(smp.p - w.m).distance;
        if (d < bestd){ bestd=d; best=smp.s; }
      }
      wpS.add(best);
      wpTheta.add(w.thetaDeg);
    }

    // --- Yaw profile (rad), independent of tangent if user set thetaDeg
    final yaw = buildYawProfile(sSample: s, tangent: tang, waypointS: wpS, waypointThetaDeg: wpTheta);
    final theta = yaw.theta;
    final dtheta_ds = yaw.dtheta_ds;
    final ddtheta_ds2 = yaw.ddtheta_ds2;

    // --- Swerve static velocity bounds
    final lim = swerveVelocityBounds(
      s: s, tangent: tang, kappa: kappa, theta: theta, dtheta_ds: dtheta_ds,
      trackWidth: cons.trackWidth, wheelBase: cons.wheelBase,
      vWheelMax: cons.wheelSpeedMax, vMaxChassis: cons.vMax, yawRateMax: cons.yawRateMax,
    );

    // --- Time scaling with friction circle + yaw accel limit
    final ts = timeScale(
      s: s, kappa: kappa, vStatic: lim.vStat,
      dtheta_ds: dtheta_ds, ddtheta_ds2: ddtheta_ds2,
      aMax: cons.aMax, aMin: cons.aMin, mu: cons.mu, g: cons.g,
      yawAccelMax: cons.yawAccelMax, vStart: cons.vStart, vEnd: cons.vEnd,
    );

    // --- Resample to 20ms timeline
    const dt = 0.02;
    final outS = <double>[0.0];
    final outXY = <Offset>[xy.first];
    final outHeading = <double>[tang.first];
    final outTheta = <double>[theta.first * 180.0 / math.pi];
    final outV = <double>[ts.v.first];
    final outA = <double>[ts.a.first];
    final outOmega = <double>[dtheta_ds.first * ts.v.first];
    final outKappa = <double>[kappa.first];

    double t = 0.0;
    int i = 0;
    while (i < s.length-1){
      final vNow = ts.v[i].clamp(1e-6, 1e9);
      final ds = vNow * dt;
      double sTarget = outS.last + ds;
      // advance along s until reaching sTarget
      while (i < s.length-1 && s[i+1] < sTarget) { i++; }
      // linear interp between i && i+1
      final w = ((sTarget - s[i]) / (s[i+1]-s[i])).clamp(0.0, 1.0);
      final p = Offset.lerp(xy[i], xy[i+1], w)!;
      final head = (tang[i]*(1-w) + tang[i+1]*w);
      final th = (theta[i]*(1-w) + theta[i+1]*w);
      final v = (ts.v[i]*(1-w) + ts.v[i+1]*w);
      final a = (ts.a[i]*(1-w) + ts.a[i+1]*w);
      final dthds = (dtheta_ds[i]*(1-w) + dtheta_ds[i+1]*w);
      final kap = (kappa[i]*(1-w) + kappa[i+1]*w);
      outS.add(sTarget);
      outXY.add(p);
      outHeading.add(head);
      outTheta.add(th * 180.0 / math.pi);
      outV.add(v);
      outA.add(a);
      outOmega.add(dthds * v);
      outKappa.add(kap);
      t += dt;
      i += 0; // stay or move depending on while loop
      if (sTarget >= s.last - 1e-6) break;
    }

    final file = await CsvExporter.export(outXY, outTheta);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("已匯出：${file.path}")));
    }
  }
double _polylineLen(List<Offset> pts) {
    double s = 0;
    for (int i=1;i<pts.length;i++) { s += (pts[i]-pts[i-1]).distance; }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Orbit Pathfinder (Flutter MVP)"),
        actions: [
          IconButton(onPressed: _exportCsv, tooltip: "匯出 CSV (20 ms)", icon: const Icon(Icons.download)),
        ],
      ),
      body: Row(
        children: [
          // left panel
          SizedBox(
            width: 360,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Scrollbar(
              thumbVisibility: true,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Text("座標系：左下 (0,0)，+X→右，+Y→上", style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  ConstraintsPanel(constraints: cons, onApply: (c)=>setState(()=>cons=c)),
                  const SizedBox(height: 12),
                  WaypointsPanel(
                    cfg: cfg,
                    waypoints: waypoints,
                    onAddPass: _addPass,
                    onUpdateStart: _updateStart,
                    onUpdateEnd: _updateEnd,
                    onUpdatePass: _updatePass,
                    onDeletePass: _deletePass,
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
            ),
          ),
          const VerticalDivider(width: 1),
          // canvas
          Expanded(
            child: FieldCanvas(
              cfg: cfg,
              waypoints: waypoints,
              onChanged: (wps) => setState(()=>waypoints = List<Waypoint>.from(wps)),
              bgImage: bgImg,
              cons: cons,
            ),
          ),
        ],
      ),
    );
  }
}
