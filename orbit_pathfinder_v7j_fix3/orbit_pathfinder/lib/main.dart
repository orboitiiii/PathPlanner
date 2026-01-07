import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'domain/algos/geometry.dart';
import 'domain/algos/swerve_limits.dart';
import 'domain/algos/time_scaling.dart';
import 'domain/algos/yaw_profile.dart';
import 'domain/models/constraints.dart';
import 'domain/models/field_config.dart';
import 'domain/models/waypoint.dart';
import 'features/field/widgets/field_canvas.dart';
import 'features/panels/constraints_panel.dart';
import 'features/panels/waypoints_panel.dart';
import 'services/exporters/csv_exporter.dart';

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
  
  // 路徑規劃結果
  List<PathGeomSample> pathSamples = [];
  List<Offset> plannedPath = [];
  List<double> velocityProfile = [];

  @override
  void initState() {
    super.initState();
    cfg = FieldConfig(
      fieldSizeMeters: const Size(17.548250, 8.051902),
      pixelRect: const Rect.fromLTWH(534, 291, 3466 - 534, 1638 - 291),
      originCorner: OriginCorner.bottomLeft,
    );
    // initial points: start at (0,0) end at (5,0)
    waypoints = [
      Waypoint(const Offset(0, 0), WaypointKind.start, "Start", thetaDeg: 0),
      Waypoint(const Offset(5, 0), WaypointKind.end, "End", thetaDeg: 0),
    ];
    _loadBg();
    _updatePath(); // 初始化路徑
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

  // 更新路徑規劃
  void _updatePath() {
    if (waypoints.length < 2) {
      setState(() {
        pathSamples = [];
        plannedPath = [];
        velocityProfile = [];
      });
      return;
    }

    try {
      final pts = waypoints.map((w) => w.m).toList();
      
      // 驗證航點數據
      for (int i = 0; i < pts.length; i++) {
        if (!pts[i].dx.isFinite || !pts[i].dy.isFinite) {
          print("錯誤：航點 $i 包含無效座標: ${pts[i]}");
          setState(() {
            pathSamples = [];
            plannedPath = [];
            velocityProfile = [];
          });
          return;
        }
      }
      
      // 1. 幾何採樣
      final samples = sampleSmoothPath(pts, ds: 0.02); // 增大採樣間隔避免過密
      if (samples.isEmpty) {
        print("警告：幾何採樣失敗");
        setState(() {
          pathSamples = [];
          plannedPath = [];
          velocityProfile = [];
        });
        return;
      }
      
      final s = samples.map((e) => e.s).toList();
      final xy = samples.map((e) => e.p).toList();
      final tang = samples.map((e) => e.tangent).toList();
      final kappa = samples.map((e) => e.kappa).toList();
      
      // 驗證採樣結果
      bool hasValidData = true;
      for (int i = 0; i < samples.length; i++) {
        if (!s[i].isFinite || !xy[i].dx.isFinite || !xy[i].dy.isFinite || 
            !tang[i].isFinite || !kappa[i].isFinite) {
          print("錯誤：採樣點 $i 包含無效數據");
          hasValidData = false;
          break;
        }
      }
      
      if (!hasValidData) {
        setState(() {
          pathSamples = [];
          plannedPath = [];
          velocityProfile = [];
        });
        return;
      }

      // 2. 計算航點的s位置
      final wpS = <double>[];
      final wpTheta = <double?>[];
      for (final w in waypoints) {
        double best = 0, bestd = double.infinity;
        for (int j = 0; j < samples.length; j++) {
          final d = (samples[j].p - w.m).distance;
          if (d < bestd) {
            bestd = d;
            best = samples[j].s;
          }
        }
        wpS.add(best);
        wpTheta.add(w.thetaDeg);
      }

      // 3. 建立偏航角配置
      final yaw = buildYawProfile(
        sSample: s,
        tangent: tang,
        waypointS: wpS,
        waypointThetaDeg: wpTheta,
      );
      
      // 驗證偏航角數據
      for (int i = 0; i < yaw.theta.length; i++) {
        if (!yaw.theta[i].isFinite || !yaw.dtheta_ds[i].isFinite || !yaw.ddtheta_ds2[i].isFinite) {
          print("錯誤：偏航角數據無效，索引: $i");
          setState(() {
            pathSamples = [];
            plannedPath = [];
            velocityProfile = [];
          });
          return;
        }
      }

      // 4. 計算速度限制
      final lim = swerveVelocityBounds(
        s: s,
        tangent: tang,
        kappa: kappa,
        theta: yaw.theta,
        dtheta_ds: yaw.dtheta_ds,
        trackWidth: cons.trackWidth,
        wheelBase: cons.wheelBase,
        vWheelMax: cons.wheelSpeedMax,
        vMaxChassis: cons.vMax,
        yawRateMax: cons.yawRateMax,
      );

      // 5. 時間縮放
      final ts = timeScale(
        s: s,
        kappa: kappa,
        vStatic: lim.vStat,
        dtheta_ds: yaw.dtheta_ds,
        ddtheta_ds2: yaw.ddtheta_ds2,
        aMax: cons.aMax,
        aMin: cons.aMin,
        mu: cons.mu,
        g: cons.g,
        yawAccelMax: cons.yawAccelMax,
        vStart: cons.vStart,
        vEnd: cons.vEnd,
      );

      setState(() {
        pathSamples = samples;
        plannedPath = xy;
        velocityProfile = ts.v;
      });
    } catch (e) {
      print("路徑規劃錯誤: $e");
      setState(() {
        pathSamples = [];
        plannedPath = [];
        velocityProfile = [];
      });
    }
  }

  void _addPass() {
    final center = Offset(cfg.fieldSizeMeters.width/2, cfg.fieldSizeMeters.height/2);
    final idx = waypoints.where((w)=>w.kind==WaypointKind.pass).length + 1;
    setState(() {
      final copy = List<Waypoint>.from(waypoints);
      copy.insert(copy.length-1, Waypoint(center, WaypointKind.pass, "P$idx"));
      waypoints = copy;
    });
    _updatePath();
  }

  void _updateStart(double x, double y, double? thetaDeg) {
    setState(() {
      final copy = List<Waypoint>.from(waypoints);
      copy[0] = Waypoint(Offset(x,y), WaypointKind.start, "Start", thetaDeg: thetaDeg ?? copy[0].thetaDeg ?? 0.0);
      waypoints = copy;
    });
    _updatePath();
  }

  void _updateEnd(double x, double y, double? thetaDeg) {
    setState(() {
      final copy = List<Waypoint>.from(waypoints);
      copy[copy.length-1] = Waypoint(Offset(x,y), WaypointKind.end, "End", thetaDeg: thetaDeg ?? copy.last.thetaDeg ?? 0.0);
      waypoints = copy;
    });
    _updatePath();
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
      _updatePath();
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
      _updatePath();
    }
  }

  void _onWaypointsChanged(List<Waypoint> wps) {
    setState(() => waypoints = List<Waypoint>.from(wps));
    _updatePath();
  }

  void _onConstraintsChanged(Constraints newCons) {
    setState(() => cons = newCons);
    _updatePath();
  }
  
  Future<void> _exportCsv() async {
    if (plannedPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("沒有可匯出的路徑數據"))
      );
      return;
    }

    try {
      // 使用規劃好的路徑數據
      final s = pathSamples.map((e) => e.s).toList();
      final xy = pathSamples.map((e) => e.p).toList();
      final tang = pathSamples.map((e) => e.tangent).toList();
      final kappa = pathSamples.map((e) => e.kappa).toList();

      // 重新計算完整的路徑資料用於導出
      final wpS = <double>[];
      final wpTheta = <double?>[];
      for (final w in waypoints) {
        double best = 0, bestd = double.infinity;
        for (final smp in pathSamples) {
          final d = (smp.p - w.m).distance;
          if (d < bestd) {
            bestd = d;
            best = smp.s;
          }
        }
        wpS.add(best);
        wpTheta.add(w.thetaDeg);
      }

      final yaw = buildYawProfile(
        sSample: s,
        tangent: tang,
        waypointS: wpS,
        waypointThetaDeg: wpTheta,
      );

      final lim = swerveVelocityBounds(
        s: s,
        tangent: tang,
        kappa: kappa,
        theta: yaw.theta,
        dtheta_ds: yaw.dtheta_ds,
        trackWidth: cons.trackWidth,
        wheelBase: cons.wheelBase,
        vWheelMax: cons.wheelSpeedMax,
        vMaxChassis: cons.vMax,
        yawRateMax: cons.yawRateMax,
      );

      final ts = timeScale(
        s: s,
        kappa: kappa,
        vStatic: lim.vStat,
        dtheta_ds: yaw.dtheta_ds,
        ddtheta_ds2: yaw.ddtheta_ds2,
        aMax: cons.aMax,
        aMin: cons.aMin,
        mu: cons.mu,
        g: cons.g,
        yawAccelMax: cons.yawAccelMax,
        vStart: cons.vStart,
        vEnd: cons.vEnd,
      );

      // 重採樣到20ms時間線
      const dt = 0.02;
      final outXY = <Offset>[];
      final outTheta = <double>[];
      final outV = <double>[];
      final outA = <double>[];
      final outT = <double>[];

      if (s.isNotEmpty && ts.v.isNotEmpty) {
        double t = 0.0;
        int i = 0;
        
        // 添加第一個點
        outXY.add(xy.first);
        outTheta.add(yaw.theta.first * 180.0 / math.pi);
        outV.add(ts.v.first);
        outA.add(ts.a.first);
        outT.add(t);

        while (i < s.length - 1 && outXY.length < 10000) { // 限制輸出點數避免無限迴圈
          final vNow = math.max(ts.v[i], 0.001); // 避免除以零
          final ds = vNow * dt;
          final sTarget = (outXY.length > 0 ? s[i] : 0) + ds;
          
          // 找到對應的s位置
          while (i < s.length - 1 && s[i + 1] < sTarget) {
            i++;
          }
          
          if (i >= s.length - 1) break;
          
          // 線性插值
          final ratio = (s[i + 1] - s[i] > 1e-6) ? (sTarget - s[i]) / (s[i + 1] - s[i]) : 0.0;
          final w = ratio.clamp(0.0, 1.0);
          
          final p = Offset.lerp(xy[i], xy[i + 1], w)!;
          final th = yaw.theta[i] * (1 - w) + yaw.theta[i + 1] * w;
          final v = ts.v[i] * (1 - w) + ts.v[i + 1] * w;
          final a = ts.a[i] * (1 - w) + ts.a[i + 1] * w;
          
          outXY.add(p);
          outTheta.add(th * 180.0 / math.pi);
          outV.add(v);
          outA.add(a);
          outT.add(t);
          
          t += dt;
          
          if (sTarget >= s.last - 1e-6) break;
        }
      }

      final file = await CsvExporter.exportWithTimeData(outXY, outTheta, outV, outA, outT);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("已匯出：${file.path}")));
      }
    } catch (e) {
      print("CSV 導出錯誤: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("匯出失敗：$e")));
      }
    }
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
                  ConstraintsPanel(constraints: cons, onApply: _onConstraintsChanged),
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
                  // 顯示路徑統計資訊
                  if (pathSamples.isNotEmpty) ...[
                    const Divider(height: 20),
                    const Text("路徑資訊", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text("路徑長度: ${pathSamples.last.s.toStringAsFixed(2)} m"),
                    Text("採樣點數: ${pathSamples.length}"),
                    if (velocityProfile.isNotEmpty)
                      Text("最大速度: ${velocityProfile.reduce(math.max).toStringAsFixed(2)} m/s"),
                  ],
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
              onChanged: _onWaypointsChanged,
              bgImage: bgImg,
              cons: cons,
              plannedPath: plannedPath,  // 傳遞規劃好的路徑
              pathSamples: pathSamples,  // 傳遞路徑樣本用於調試
            ),
          ),
        ],
      ),
    );
  }
}