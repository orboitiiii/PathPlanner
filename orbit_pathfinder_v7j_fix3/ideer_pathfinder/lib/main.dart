// lib/main.dart
//
// 更新：
// - 右側改為 Column + Flexible（上：地圖 flex=9；下：分析 flex=5），不再用固定高度，杜絕底部溢出
// - Analyze 改單一卡片，內部 2x2 自適應（每張圖用 Expanded 橫向補滿、垂直等分）
// - 保留 Undo/Redo、圖層著色、Playback 等既有功能
//
// 依賴：shared_preferences: ^2.2.2

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'domain/algos/advanced_path_planner.dart';
import 'domain/models/constraints.dart';
import 'domain/models/field_config.dart';
import 'domain/models/waypoint.dart';
import 'features/field/widgets/field_canvas.dart';
import 'features/panels/constraints_panel.dart';
import 'features/panels/waypoints_panel.dart';
import 'services/exporters/csv_exporter.dart';
import 'theme/spacex_theme.dart';

// =================== UI Colors (SpaceX Style) ===================
class AppColors {
  static const path = SpaceXColors.primary;
  static const pathGlow = Color(0x66B3E5FC);
  static const vWorld = SpaceXColors.secondary;
  static const vBody = SpaceXColors.warning;
  static const omega = Color(0xFFCC79A7);
  static const robotStroke = SpaceXColors.textPrimary;
  static const robotFill = Color(0x22ECEFF1);
  static const wpStart = SpaceXColors.waypointStart;
  static const wpEnd = SpaceXColors.waypointEnd;
  static const wpPass = SpaceXColors.waypointStop;
  static const yawMarker = SpaceXColors.textPrimary;
  static const yawHalo = Color(0x55FFFFFF);

  // 指標著色
  static const divergeNeg = SpaceXColors.primary;
  static const divergeZero = SpaceXColors.textPrimary;
  static const divergePos = SpaceXColors.error;
  static const safeGood = SpaceXColors.secondary;
  static const safeWarn = SpaceXColors.warning;
  static const safeBad = SpaceXColors.error;
}

// void main() => runApp(const MyApp());

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  windowManager.setTitle('Ideer Pathfinder');
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ideer Pathfinder',
      theme: createSpaceXTheme(),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// =================== Project Model ===================
class Project {
  String id;
  String name;
  List<Waypoint> waypoints;
  Constraints constraints;
  List<Offset?> quadCtrls;

  Project({
    required this.id,
    required this.name,
    required this.waypoints,
    required this.constraints,
    required this.quadCtrls,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'waypoints': waypoints.map(_waypointToJson).toList(),
        'constraints': _constraintsToJson(constraints),
        'quadCtrls': quadCtrls
            .map((o) => o == null ? null : {'x': o.dx, 'y': o.dy})
            .toList(),
      };

  static Project fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String,
        waypoints:
            (j['waypoints'] as List).map((e) => _waypointFromJson(e)).toList(),
        constraints:
            _constraintsFromJson(j['constraints'] as Map<String, dynamic>),
        quadCtrls: (j['quadCtrls'] as List).map((e) {
          if (e == null) return null;
          final m = e as Map<String, dynamic>;
          return Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble());
        }).toList(),
      );
}

Map<String, dynamic> _waypointToJson(Waypoint w) => {
      'x': w.m.dx,
      'y': w.m.dy,
      'kind': _kindToStr(w.kind),
      'label': w.label,
      'thetaDeg': w.thetaDeg,
    };

Waypoint _waypointFromJson(dynamic j) {
  final m = j as Map<String, dynamic>;
  return Waypoint(
    Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble()),
    _strToKind(m['kind'] as String),
    (m['label'] as String?) ?? '',
    thetaDeg:
        (m['thetaDeg'] == null) ? null : (m['thetaDeg'] as num).toDouble(),
  );
}

String _kindToStr(WaypointKind k) {
  switch (k) {
    case WaypointKind.start:
      return 'start';
    case WaypointKind.end:
      return 'end';
    case WaypointKind.pass:
      return 'pass';
    case WaypointKind.passThrough:
      return 'passThrough';
  }
}

WaypointKind _strToKind(String s) {
  switch (s) {
    case 'start':
      return WaypointKind.start;
    case 'end':
      return WaypointKind.end;
    case 'passThrough':
      return WaypointKind.passThrough;
    default:
      return WaypointKind.pass;
  }
}

// Constraints <-> json
Map<String, dynamic> _constraintsToJson(Constraints c) => {
      'vMax': c.vMax,
      'vMin': c.vMin,
      'aMax': c.aMax,
      'aMin': c.aMin,
      'trackWidth': c.trackWidth,
      'wheelBase': c.wheelBase,
      'wheelSpeedMax': c.wheelSpeedMax,
      'yawRateMax': c.yawRateMax,
      'mu': c.mu,
      'g': c.g,
    };

Constraints _constraintsFromJson(Map<String, dynamic> m) => Constraints(
      vMax: (m['vMax'] as num).toDouble(),
      vMin: (m['vMin'] as num).toDouble(),
      aMax: (m['aMax'] as num).toDouble(),
      aMin: (m['aMin'] as num).toDouble(),
      trackWidth: (m['trackWidth'] as num).toDouble(),
      wheelBase: (m['wheelBase'] as num).toDouble(),
      wheelSpeedMax: (m['wheelSpeedMax'] as num).toDouble(),
      yawRateMax: (m['yawRateMax'] as num).toDouble(),
      mu: (m['mu'] as num).toDouble(),
      g: (m['g'] as num).toDouble(),
    );

// =================== Undo / Redo ===================
class _Snapshot {
  final List<Waypoint> wps;
  final List<Offset?> ctrls;
  final Constraints cons;
  const _Snapshot(this.wps, this.ctrls, this.cons);
}

Waypoint _cloneWp(Waypoint w) =>
    Waypoint(Offset(w.m.dx, w.m.dy), w.kind, w.label, thetaDeg: w.thetaDeg);

class _History {
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  DateTime? _lastPush;
  void push(_Snapshot s,
      {Duration minGap = const Duration(milliseconds: 180)}) {
    final now = DateTime.now();
    if (_lastPush != null && now.difference(_lastPush!) < minGap) return;
    _undo.add(s);
    _redo.clear();
    _lastPush = now;
  }

  _Snapshot? undo(_Snapshot current) {
    if (_undo.isEmpty) return null;
    final prev = _undo.removeLast();
    _redo.add(current);
    return prev;
  }

  _Snapshot? redo(_Snapshot current) {
    if (_redo.isEmpty) return null;
    final next = _redo.removeLast();
    _undo.add(current);
    return next;
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
}

// =================== Layer Mode ===================
enum LayerMode { solid, speed, accel, curvature, safety }

// =================== Home ===================
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  static const _prefsKey = 'projects_v1';

  final ScrollController _leftScrollCtrl = ScrollController();

  final _History _history = _History();

  // Projects
  List<Project> _projects = [];
  int _selectedProject = 0;
  String get _curProjKey =>
      _projects.isNotEmpty ? _projects[_selectedProject].id : 'none';

  // 場地與幾何
  late FieldConfig cfg;
  ui.Image? bgImg;

  // 當前專案資料
  List<Waypoint> waypoints = [];
  Constraints cons = Constraints();
  List<Offset?> _quadCtrls = [];

  // 規劃結果
  List<PathPoint> plannedPathPoints = [];
  AdvancedPathPlanner? pathPlanner;

  // 播放
  late final Ticker _ticker;
  Duration? _lastElapsed;
  bool _playing = false;
  double _speed = 1.0;
  double _t = 0.0;

  // 視覺層
  LayerMode _layerMode = LayerMode.solid;

  @override
  void initState() {
    super.initState();
    cfg = FieldConfig(
      fieldSizeMeters: const Size(17.548250, 8.051902),
      pixelRect: const Rect.fromLTWH(534, 291, 3466 - 534, 1638 - 291),
      originCorner: OriginCorner.bottomLeft,
    );
    _initializePathPlanner();
    _ticker = createTicker(_onTick);
    _loadBg();
    _loadProjects();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _leftScrollCtrl.dispose();
    super.dispose();
  }

  // ---------------- Projects ----------------
  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) {
      final defCons = Constraints();
      final defWps = [
        Waypoint(const Offset(0, 0), WaypointKind.start, "Start", thetaDeg: 0),
        Waypoint(const Offset(5, 0), WaypointKind.end, "End", thetaDeg: 0),
      ];
      final defCtrls = <Offset?>[
        (defWps[0].m + defWps[1].m) * 0.5 + const Offset(0, 0.1)
      ];
      final proj = Project(
        id: _newId(),
        name: "New Project",
        waypoints: defWps,
        constraints: defCons,
        quadCtrls: defCtrls,
      );
      _projects = [proj];
      _selectedProject = 0;
      _applyProjectToState(proj);
      _saveProjects();
    } else {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final list =
            (decoded['items'] as List).map((e) => Project.fromJson(e)).toList();
        final sel = (decoded['selected'] as int?) ?? 0;
        _projects = list.isNotEmpty ? list : _defaultProjectList();
        _selectedProject = sel.clamp(0, _projects.length - 1);
        _applyProjectToState(_projects[_selectedProject]);
      } catch (_) {
        _projects = _defaultProjectList();
        _selectedProject = 0;
        _applyProjectToState(_projects[0]);
        _saveProjects();
      }
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _saveProjects() async {
    if (_projects.isNotEmpty) {
      _projects[_selectedProject] =
          _captureStateToProject(_projects[_selectedProject]);
    }
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'selected': _selectedProject,
      'items': _projects.map((p) => p.toJson()).toList(),
    });
    await prefs.setString(_prefsKey, payload);
  }

  List<Project> _defaultProjectList() {
    final defCons = Constraints();
    final defWps = [
      Waypoint(const Offset(0, 0), WaypointKind.start, "Start", thetaDeg: 0),
      Waypoint(const Offset(5, 0), WaypointKind.end, "End", thetaDeg: 0),
    ];
    final defCtrls = <Offset?>[
      (defWps[0].m + defWps[1].m) * 0.5 + const Offset(0, 0.1)
    ];
    return [
      Project(
          id: _newId(),
          name: "New Project",
          waypoints: defWps,
          constraints: defCons,
          quadCtrls: defCtrls)
    ];
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _applyProjectToState(Project p) {
    setState(() {
      waypoints = List<Waypoint>.from(p.waypoints);
      cons = p.constraints;
      _quadCtrls = List<Offset?>.from(p.quadCtrls);
      _syncCtrlLen();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updatePath();
    });
  }

  Project _captureStateToProject(Project base) => Project(
        id: base.id,
        name: base.name,
        waypoints: waypoints.map(_cloneWp).toList(),
        constraints: cons.copyWith(),
        quadCtrls: _quadCtrls
            .map((o) => o == null ? null : Offset(o.dx, o.dy))
            .toList(),
      );

  Future<void> _addProject() async {
    await _saveProjects();
    const baseName = "New Project";
    String name = baseName;
    int k = 2;
    final exist = _projects.map((e) => e.name).toSet();
    while (exist.contains(name)) {
      name = "$baseName $k";
      k++;
    }
    final defCons = Constraints();
    final defWps = [
      Waypoint(const Offset(0, 0), WaypointKind.start, "Start", thetaDeg: 0),
      Waypoint(const Offset(5, 0), WaypointKind.end, "End", thetaDeg: 0),
    ];
    final defCtrls = <Offset?>[
      (defWps[0].m + defWps[1].m) * 0.5 + const Offset(0, 0.1)
    ];
    final proj = Project(
      id: _newId(),
      name: name,
      waypoints: defWps,
      constraints: defCons,
      quadCtrls: defCtrls,
    );
    setState(() {
      _projects.add(proj);
      _selectedProject = _projects.length - 1;
    });
    _applyProjectToState(proj);
    await _saveProjects();
  }

  Future<void> _renameProjectDialog() async {
    if (_projects.isEmpty) return;
    final controller =
        TextEditingController(text: _projects[_selectedProject].name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Project'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('OK')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _projects[_selectedProject].name = controller.text.trim().isEmpty
            ? _projects[_selectedProject].name
            : controller.text.trim();
      });
      await _saveProjects();
    }
  }

  Future<void> _deleteProject() async {
    if (_projects.length <= 1) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('至少需要保留一個專案')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除專案？'),
        content: Text('確定刪除 "${_projects[_selectedProject].name}"？此動作無法復原。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('刪除')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _projects.removeAt(_selectedProject);
        _selectedProject = _selectedProject.clamp(0, _projects.length - 1);
      });
      _applyProjectToState(_projects[_selectedProject]);
      await _saveProjects();
    }
  }

  // ---------------- Init helpers ----------------
  void _initializePathPlanner() {
    pathPlanner = AdvancedPathPlanner();
  }

  Future<void> _loadBg() async {
    try {
      final img = await _loadImageFromAsset('assets/images/2025-field.png');
      if (!mounted) return;
      setState(() => bgImg = img);
    } catch (_) {}
  }

  Future<ui.Image> _loadImageFromAsset(String asset) async {
    final bd = await DefaultAssetBundle.of(context).load(asset);
    final codec = await ui.instantiateImageCodec(bd.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  // ---------------- Ctrl points ----------------
  void _syncCtrlLen() {
    final need = (waypoints.length - 1).clamp(0, 1 << 20);
    while (_quadCtrls.length < need) {
      final i = _quadCtrls.length;
      _quadCtrls.add(_defaultCtrlForSeg(i));
    }
    while (_quadCtrls.length > need) {
      _quadCtrls.removeLast();
    }
  }

  Offset _defaultCtrlForSeg(int i) {
    final p0 = waypoints[i].m, p1 = waypoints[i + 1].m;
    final mid = (p0 + p1) * 0.5;
    final dir = (p1 - p0);
    final nrm = Offset(-dir.dy, dir.dx);
    return mid + nrm * 0.1;
  }

  // ---------------- Planning ----------------
  void _updatePath() {
    if (waypoints.length < 2 || pathPlanner == null) {
      setState(() => plannedPathPoints = []);
      _resetPlayback();
      return;
    }
    try {
      final positions = waypoints.map((w) => w.m).toList();
      final yaws = waypoints.map((w) => w.thetaDeg).toList();
      // 根據航點類型生成 passThrough 列表
      final passThroughs =
          waypoints.map((w) => w.kind == WaypointKind.passThrough).toList();
      final pathPoints = pathPlanner!.generatePath(
        waypoints: positions,
        waypointYaws: yaws,
        constraints: cons,
        quadCtrls: _quadCtrls,
        waypointPassThrough: passThroughs,
        resolution: 0.05,
      );
      setState(() {
        plannedPathPoints = pathPoints;
        final total = pathPoints.isNotEmpty ? pathPoints.last.time : 0.0;
        _t = _t.clamp(0.0, total);
        _playing = false;
        _ticker.stop();
        _lastElapsed = null;
      });
      _saveProjects();
    } catch (_) {
      setState(() => plannedPathPoints = []);
      _resetPlayback();
    }
  }

  // ---------------- Playback ----------------
  void _onTick(Duration elapsed) {
    if (!_playing || plannedPathPoints.isEmpty) return;
    final total = plannedPathPoints.last.time;
    if (total <= 0) return;

    final dt = (_lastElapsed == null)
        ? 0.0
        : (elapsed - _lastElapsed!).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt <= 0) return;

    setState(() {
      _t = (_t + dt * _speed).clamp(0.0, total);
      if (_t >= total - 1e-9) {
        _playing = false;
        _ticker.stop();
      }
    });
  }

  void _playPause() {
    if (plannedPathPoints.isEmpty) return;
    final total = plannedPathPoints.last.time;
    if (total <= 0) return;
    if (_t >= total - 1e-9) _t = 0.0;
    setState(() {
      _playing = !_playing;
      if (_playing) {
        _lastElapsed = null;
        _ticker.start();
      } else {
        _ticker.stop();
      }
    });
  }

  void _stopPlayback() {
    setState(() {
      _playing = false;
      _ticker.stop();
      _t = plannedPathPoints.isNotEmpty ? plannedPathPoints.last.time : 0.0;
      _lastElapsed = null;
    });
  }

  void _resetPlayback() {
    _playing = false;
    _ticker.stop();
    _t = plannedPathPoints.isNotEmpty ? plannedPathPoints.last.time : 0.0;
    _lastElapsed = null;
  }

  // 插值
  PathPoint? _interpolatePathPoint(double targetTime, List<PathPoint> points) {
    if (points.isEmpty) return null;
    if (targetTime <= points.first.time) return points.first;
    if (targetTime >= points.last.time) return points.last;
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i], p2 = points[i + 1];
      if (targetTime >= p1.time && targetTime <= p2.time) {
        final dt = (p2.time - p1.time);
        final r = dt > 1e-6 ? (targetTime - p1.time) / dt : 0.0;
        return PathPoint(
          s: p1.s + (p2.s - p1.s) * r,
          position: Offset.lerp(p1.position, p2.position, r)!,
          heading: p1.heading + _wrapAngleDiff(p2.heading - p1.heading) * r,
          curvature: p1.curvature + (p2.curvature - p1.curvature) * r,
          velocity: p1.velocity + (p2.velocity - p1.velocity) * r,
          acceleration:
              p1.acceleration + (p2.acceleration - p1.acceleration) * r,
          time: targetTime,
          yaw: p1.yaw + _wrapAngleDiff(p2.yaw - p1.yaw) * r,
          yawRate: p1.yawRate + (p2.yawRate - p1.yawRate) * r,
        );
      }
    }
    return null;
  }

  _Kine? get _liveKine {
    if (plannedPathPoints.isEmpty) return null;
    final p = _interpolatePathPoint(_t, plannedPathPoints);
    if (p == null) return null;

    const dt = 0.02;
    final total = plannedPathPoints.last.time;
    final t0 = (_t - dt).clamp(0.0, total);
    final t1 = (_t + dt).clamp(0.0, total);
    final p0 = _interpolatePathPoint(t0, plannedPathPoints) ?? p;
    final p1 = _interpolatePathPoint(t1, plannedPathPoints) ?? p;
    final denom = (t1 - t0);
    final inv = denom.abs() > 1e-9 ? 1.0 / denom : 0.0;
    final vWorld = (p1.position - p0.position) * inv;

    final yaw = p.yaw;
    final omega = p.yawRate;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final vbx = cy * vWorld.dx + sy * vWorld.dy;
    final vby = -sy * vWorld.dx + cy * vWorld.dy;

    return _Kine(
      pos: p.position,
      yaw: yaw,
      vWorld: vWorld,
      vBody: Offset(vbx, vby),
      omega: omega,
      time: p.time,
      speed: vWorld.distance,
      heading: p.heading,
      acc: p.acceleration,
      curv: p.curvature,
    );
  }

  // Export
  Future<void> _exportCsv() async {
    if (plannedPathPoints.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("沒有可匯出的路徑數據")),
      );
      return;
    }
    try {
      const dt = 0.02;
      final resampled = <PathPoint>[];
      final total = plannedPathPoints.last.time;
      if (total > 0) {
        for (int i = 0;; i++) {
          final t = math.min(i * dt, total);
          final p = _interpolatePathPoint(t, plannedPathPoints);
          if (p != null) resampled.add(p);
          if (t >= total - 1e-9) break;
        }
        if ((resampled.last.time - total).abs() > 1e-6) {
          resampled.add(plannedPathPoints.last);
        }
      }
      final exportPoints = resampled.isNotEmpty ? resampled : plannedPathPoints;
      final file = await CsvExporter.exportPathPoints(exportPoints);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("已匯出 ${exportPoints.length} 個路徑點到：${file.path}")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("匯出失敗：$e")),
      );
    }
  }

  // Helpers
  String _fmtTime(double t) {
    final mm = (t ~/ 60).toString().padLeft(2, '0');
    final ss = (t % 60).toStringAsFixed(2).padLeft(5, '0');
    return '$mm:$ss';
  }

  double _wrapAngleDiff(double a) {
    var d = a;
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    return d;
  }

  _Snapshot _snapshot() => _Snapshot(
        waypoints.map(_cloneWp).toList(),
        _quadCtrls.map((o) => o == null ? null : Offset(o.dx, o.dy)).toList(),
        cons.copyWith(),
      );
  void _pushHistory() => _history.push(_snapshot());
  void _handleUndo() {
    final s = _history.undo(_snapshot());
    if (s == null) return;
    setState(() {
      waypoints = s.wps.map(_cloneWp).toList();
      _quadCtrls =
          s.ctrls.map((o) => o == null ? null : Offset(o.dx, o.dy)).toList();
      cons = s.cons.copyWith();
      _syncCtrlLen();
    });
    _updatePath();
  }

  void _handleRedo() {
    final s = _history.redo(_snapshot());
    if (s == null) return;
    setState(() {
      waypoints = s.wps.map(_cloneWp).toList();
      _quadCtrls =
          s.ctrls.map((o) => o == null ? null : Offset(o.dx, o.dy)).toList();
      cons = s.cons.copyWith();
      _syncCtrlLen();
    });
    _updatePath();
  }

  // =================== UI ===================
  @override
  Widget build(BuildContext context) {
    final total =
        plannedPathPoints.isNotEmpty ? plannedPathPoints.last.time : 0.0;
    final kine = _liveKine;

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyZ):
            const _UndoIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyY):
            const _RedoIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyZ):
            const _UndoIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyY):
            const _RedoIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) {
            _handleUndo();
            return null;
          }),
          _RedoIntent: CallbackAction<_RedoIntent>(onInvoke: (_) {
            _handleRedo();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Ideer Pathfinder'),
              actions: [
                IconButton(
                    tooltip: "復原 (Ctrl+Z)",
                    onPressed: _history.canUndo ? _handleUndo : null,
                    icon: const Icon(Icons.undo)),
                IconButton(
                    tooltip: "重做 (Ctrl+Y)",
                    onPressed: _history.canRedo ? _handleRedo : null,
                    icon: const Icon(Icons.redo)),
                const SizedBox(width: 8),
                IconButton(
                    onPressed: _exportCsv,
                    tooltip: "匯出 CSV (20 ms)",
                    icon: const Icon(Icons.download)),
                const SizedBox(width: 6),
              ],
            ),
            body: Row(
              children: [
                // -------- 左側面板 --------
                SizedBox(
                  width: 420,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Scrollbar(
                      controller: _leftScrollCtrl,
                      thumbVisibility: true,
                      child: ListView(
                        controller: _leftScrollCtrl,
                        primary: false,
                        children: [
                          _SectionCard(
                            icon: Icons.route,
                            title: 'Path / Project',
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                    tooltip: '新增專案',
                                    onPressed: _addProject,
                                    icon: const Icon(Icons.add_circle_outline)),
                                IconButton(
                                    tooltip: '重新命名',
                                    onPressed: _renameProjectDialog,
                                    icon: const Icon(
                                        Icons.drive_file_rename_outline)),
                                IconButton(
                                    tooltip: '刪除專案',
                                    onPressed: _deleteProject,
                                    icon: const Icon(Icons.delete_outline)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_projects.isNotEmpty)
                                  DropdownButton<int>(
                                    isExpanded: true,
                                    value: _selectedProject,
                                    onChanged: (v) async {
                                      if (v == null) return;
                                      await _saveProjects();
                                      setState(() => _selectedProject = v);
                                      _applyProjectToState(
                                          _projects[_selectedProject]);
                                    },
                                    items: [
                                      for (int i = 0; i < _projects.length; i++)
                                        DropdownMenuItem(
                                          value: i,
                                          child: Text(_projects[i].name,
                                              overflow: TextOverflow.ellipsis),
                                        )
                                    ],
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.layers_outlined, size: 18),
                                    const SizedBox(width: 8),
                                    const Text('Layer'),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: DropdownButton<LayerMode>(
                                        isExpanded: true,
                                        value: _layerMode,
                                        onChanged: (m) =>
                                            setState(() => _layerMode = m!),
                                        items: const [
                                          DropdownMenuItem(
                                              value: LayerMode.solid,
                                              child: Text("Solid")),
                                          DropdownMenuItem(
                                              value: LayerMode.speed,
                                              child: Text("速度著色 v")),
                                          DropdownMenuItem(
                                              value: LayerMode.accel,
                                              child: Text("加速度著色 a")),
                                          DropdownMenuItem(
                                              value: LayerMode.curvature,
                                              child: Text("曲率著色 κ")),
                                          DropdownMenuItem(
                                              value: LayerMode.safety,
                                              child: Text("安全裕度 μg−v²|κ|")),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                    "座標系：藍色聯盟靠牆最下(0,0)，+X→右，+Y→上；車頭0°=+X；Swerve",
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                                const SizedBox(height: 8),
                                if (plannedPathPoints.isNotEmpty)
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _statChip('長度',
                                          '${plannedPathPoints.last.s.toStringAsFixed(2)} m'),
                                      _statChip('時間',
                                          '${plannedPathPoints.last.time.toStringAsFixed(2)} s'),
                                      _statChip('平均速',
                                          '${(plannedPathPoints.last.s / math.max(plannedPathPoints.last.time, 1e-6)).toStringAsFixed(2)} m/s'),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SectionCard(
                            icon: Icons.tune,
                            title: 'Constraints',
                            child: ConstraintsPanel(
                              key: ValueKey('cons_$_curProjKey'),
                              constraints: cons,
                              onApply: (nc) {
                                _pushHistory();
                                setState(() => cons = nc);
                                _updatePath();
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SectionCard(
                            icon: Icons.place_outlined,
                            title: 'Waypoints',
                            child: WaypointsPanel(
                              key: ValueKey('wps_$_curProjKey'),
                              cfg: cfg,
                              waypoints: waypoints,
                              onAddPass: () {
                                _pushHistory();
                                _addPass();
                              },
                              onAddPassThrough: () {
                                _pushHistory();
                                _addPassThrough();
                              },
                              onUpdateStart: (x, y, th) {
                                _pushHistory();
                                _updateStart(x, y, th);
                              },
                              onUpdateEnd: (x, y, th) {
                                _pushHistory();
                                _updateEnd(x, y, th);
                              },
                              onUpdatePass: (i, x, y, th) {
                                _pushHistory();
                                _updatePass(i, x, y, th);
                              },
                              onDeletePass: (i) {
                                _pushHistory();
                                _deletePass(i);
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SectionCard(
                            icon: Icons.play_arrow_outlined,
                            title: 'Playback',
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: _playing ? "暫停" : "播放",
                                      onPressed:
                                          (total > 0) ? _playPause : null,
                                      icon: Icon(_playing
                                          ? Icons.pause
                                          : Icons.play_arrow),
                                    ),
                                    IconButton(
                                      tooltip: "停止",
                                      onPressed:
                                          (total > 0) ? _stopPlayback : null,
                                      icon: const Icon(Icons.stop),
                                    ),
                                    const SizedBox(width: 8),
                                    DropdownButton<double>(
                                      value: _speed,
                                      onChanged: (total > 0)
                                          ? (v) => setState(() => _speed = v!)
                                          : null,
                                      items: const [
                                        DropdownMenuItem(
                                            value: 0.25, child: Text("0.25x")),
                                        DropdownMenuItem(
                                            value: 0.5, child: Text("0.5x")),
                                        DropdownMenuItem(
                                            value: 1.0, child: Text("1x")),
                                        DropdownMenuItem(
                                            value: 1.5, child: Text("1.5x")),
                                        DropdownMenuItem(
                                            value: 2.0, child: Text("2x")),
                                      ],
                                    ),
                                    const Spacer(),
                                    Text(
                                        "${_fmtTime(_t)} / ${_fmtTime(total)}"),
                                  ],
                                ),
                                Slider(
                                  value: total > 0 ? _t.clamp(0.0, total) : 0.0,
                                  min: 0.0,
                                  max: total > 0 ? total : 1.0,
                                  onChangeStart: (_) {
                                    if (_playing) {
                                      _playing = false;
                                      _ticker.stop();
                                    }
                                  },
                                  onChanged: (total > 0)
                                      ? (v) => setState(() => _t = v)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                // -------- 右側：上 地圖 / 下 分析（自適應、無溢出）--------
                Expanded(
                  child: Column(
                    children: [
                      Flexible(
                        flex: 9,
                        child: LayoutBuilder(
                          builder: (context, box) {
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                FieldCanvas(
                                  key: ValueKey('canvas_$_curProjKey'),
                                  cfg: cfg,
                                  waypoints: waypoints,
                                  onChanged: (wps) {
                                    _pushHistory();
                                    _onWaypointsChanged(wps);
                                  },
                                  bgImage: bgImg,
                                  cons: cons,
                                  plannedPathPoints: plannedPathPoints,
                                  quadCtrls: _quadCtrls,
                                  onCtrlChanged: (i, m) {
                                    _pushHistory();
                                    _onCtrlChanged(i, m);
                                  },
                                ),
                                IgnorePointer(
                                  ignoring: true,
                                  child: CustomPaint(
                                    painter: _AestheticOverlayPainter(
                                      cfg: cfg,
                                      cons: cons,
                                      waypoints: waypoints,
                                      planned: plannedPathPoints,
                                      layer: _layerMode,
                                    ),
                                  ),
                                ),
                                if (kine != null)
                                  IgnorePointer(
                                    ignoring: true,
                                    child: CustomPaint(
                                      painter: _SwerveOverlayPainter(
                                          cfg: cfg, cons: cons, kine: kine),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      if (plannedPathPoints.isNotEmpty)
                        Flexible(
                          flex: 5,
                          child: Container(
                            decoration: const BoxDecoration(
                              border: Border(
                                  top: BorderSide(color: Color(0xFF2A3A4A))),
                            ),
                            child: _AnalyzePanel(
                              points: plannedPathPoints,
                              cons: cons,
                              time: _t,
                              onSeekTime: (t) => setState(() => _t = t),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Waypoint ops
  void _addPass() {
    final center =
        Offset(cfg.fieldSizeMeters.width / 2, cfg.fieldSizeMeters.height / 2);
    final idx = waypoints
            .where((w) =>
                w.kind == WaypointKind.pass ||
                w.kind == WaypointKind.passThrough)
            .length +
        1;
    setState(() {
      final copy = List<Waypoint>.from(waypoints);
      copy.insert(
          copy.length - 1, Waypoint(center, WaypointKind.pass, "P$idx"));
      waypoints = copy;
    });
    _syncCtrlLen();
    _updatePath();
  }

  /// 添加「過點不停」航點（passThrough，機器人不會在此點停車）
  void _addPassThrough() {
    final center =
        Offset(cfg.fieldSizeMeters.width / 2, cfg.fieldSizeMeters.height / 2);
    final idx = waypoints
            .where((w) =>
                w.kind == WaypointKind.pass ||
                w.kind == WaypointKind.passThrough)
            .length +
        1;
    setState(() {
      final copy = List<Waypoint>.from(waypoints);
      copy.insert(
          copy.length - 1, Waypoint(center, WaypointKind.passThrough, "T$idx"));
      waypoints = copy;
    });
    _syncCtrlLen();
    _updatePath();
  }

  void _updateStart(double x, double y, double? th) {
    setState(() {
      final c = List<Waypoint>.from(waypoints);
      c[0] = Waypoint(Offset(x, y), WaypointKind.start, "Start",
          thetaDeg: th ?? c[0].thetaDeg ?? 0.0);
      waypoints = c;
    });
    _syncCtrlLen();
    _updatePath();
  }

  void _updateEnd(double x, double y, double? th) {
    setState(() {
      final c = List<Waypoint>.from(waypoints);
      c[c.length - 1] = Waypoint(Offset(x, y), WaypointKind.end, "End",
          thetaDeg: th ?? c.last.thetaDeg ?? 0.0);
      waypoints = c;
    });
    _syncCtrlLen();
    _updatePath();
  }

  void _updatePass(int passIdx, double x, double y, double? th) {
    final i = 1 + passIdx;
    if (i >= 1 && i <= waypoints.length - 2) {
      setState(() {
        final c = List<Waypoint>.from(waypoints);
        final label = c[i].label;
        c[i] = Waypoint(Offset(x, y), WaypointKind.pass, label,
            thetaDeg: th ?? c[i].thetaDeg ?? 0.0);
        waypoints = c;
      });
      _syncCtrlLen();
      _updatePath();
    }
  }

  void _deletePass(int passIdx) {
    final i = 1 + passIdx;
    if (i >= 1 && i <= waypoints.length - 2) {
      setState(() {
        final c = List<Waypoint>.from(waypoints);
        c.removeAt(i);
        int k = 1;
        for (int j = 1; j <= c.length - 2; j++) {
          c[j].label = "P${k++}";
        }
        waypoints = c;
      });
      _syncCtrlLen();
      _updatePath();
    }
  }

  void _onWaypointsChanged(List<Waypoint> wps) {
    setState(() => waypoints = List<Waypoint>.from(wps));
    _syncCtrlLen();
    _updatePath();
  }

  void _onCtrlChanged(int segIndex, Offset m) {
    if (segIndex < 0 || segIndex >= _quadCtrls.length) return;
    setState(() => _quadCtrls[segIndex] = m);
    _updatePath();
  }
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

// ===== 左側區塊卡片 =====
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget child;
  final Widget? trailing;
  const _SectionCard(
      {required this.title, required this.child, this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) Icon(icon, size: 18),
                if (icon != null) const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

Widget _statChip(String label, String value) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFF17212A),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0xFF2A3A4A)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 12)),
        const SizedBox(width: 6),
        Text(value, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}

// ===== Swerve 動態結構 =====
class _Kine {
  final Offset pos;
  final double yaw; // 0°=車頭朝 +X
  final Offset vWorld; // 世界座標速度
  final Offset vBody; // 車體座標速度
  final double omega; // 角速度
  final double time;
  final double speed;
  final double heading;
  final double acc;
  final double curv;
  const _Kine({
    required this.pos,
    required this.yaw,
    required this.vWorld,
    required this.vBody,
    required this.omega,
    required this.time,
    required this.speed,
    required this.heading,
    required this.acc,
    required this.curv,
  });
}

// ===== Aesthetic Overlay with metric coloring =====
class _AestheticOverlayPainter extends CustomPainter {
  final FieldConfig cfg;
  final Constraints cons;
  final List<Waypoint> waypoints;
  final List<PathPoint> planned;
  final LayerMode layer;

  _AestheticOverlayPainter({
    required this.cfg,
    required this.cons,
    required this.waypoints,
    required this.planned,
    required this.layer,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fw = cfg.fieldSizeMeters.width;
    final fh = cfg.fieldSizeMeters.height;
    final s = math.min(size.width / fw, size.height / fh);
    final dx = (size.width - fw * s) / 2.0;
    final dy = (size.height - fh * s) / 2.0;

    Offset toPx(Offset m) => Offset(dx + m.dx * s, dy + (fh - m.dy) * s);

    if (planned.isNotEmpty) {
      if (layer == LayerMode.solid) {
        final path = Path();
        for (int i = 0; i < planned.length; i++) {
          final p = toPx(planned[i].position);
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = AppColors.pathGlow
            ..strokeWidth = 8
            ..style = PaintingStyle.stroke
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = AppColors.path
            ..strokeWidth = 3
            ..style = PaintingStyle.stroke
            ..isAntiAlias = true,
        );
      } else {
        final metrics = _metricSeries(planned, cons, layer);
        for (int i = 0; i < planned.length - 1; i++) {
          final a = toPx(planned[i].position);
          final b = toPx(planned[i + 1].position);
          final color = _colorForMetric(
              metrics.values[i], metrics.min, metrics.max, layer);
          final p = Paint()
            ..color = color
            ..strokeWidth = 3
            ..style = PaintingStyle.stroke
            ..isAntiAlias = true;
          canvas.drawLine(a, b, p);
        }
      }

      _drawRobotGhost(
          canvas, toPx(planned.first.position), planned.first.yaw, s);
      _drawRobotGhost(canvas, toPx(planned.last.position), planned.last.yaw, s);
    }

    for (final w in waypoints) {
      if (w.thetaDeg == null) continue;
      final p = toPx(w.m);
      final yaw = (w.thetaDeg! * math.pi / 180.0);
      _drawYawMarker(canvas, p, yaw, s);
    }
  }

  _MetricResult _metricSeries(List<PathPoint> pts, Constraints c, LayerMode m) {
    final vals = <double>[];
    for (final p in pts) {
      double v = 0;
      switch (m) {
        case LayerMode.speed:
          v = p.velocity;
          break;
        case LayerMode.accel:
          v = p.acceleration;
          break;
        case LayerMode.curvature:
          v = p.curvature;
          break;
        case LayerMode.safety:
          v = c.mu * c.g - (p.velocity * p.velocity * p.curvature.abs());
          break;
        case LayerMode.solid:
          v = 0;
          break;
      }
      vals.add(v);
    }
    double min = vals.first, max = vals.first;
    for (final v in vals) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    if (m == LayerMode.accel || m == LayerMode.curvature) {
      final a = math.max(max.abs(), min.abs());
      min = -a;
      max = a;
    }
    return _MetricResult(vals, min, max);
  }

  Color _colorForMetric(double v, double min, double max, LayerMode m) {
    double t(double x) => (max - min).abs() < 1e-9
        ? 0.5
        : ((x - min) / (max - min)).clamp(0.0, 1.0);
    if (m == LayerMode.safety) {
      final x = t(v);
      if (x < 0.5) {
        return Color.lerp(AppColors.safeBad, AppColors.safeWarn, x / 0.5)!;
      }
      return Color.lerp(
          AppColors.safeWarn, AppColors.safeGood, (x - 0.5) / 0.5)!;
    }
    if (m == LayerMode.accel || m == LayerMode.curvature) {
      final x = t(v);
      if (x < 0.5) {
        return Color.lerp(
            AppColors.divergeNeg, AppColors.divergeZero, x / 0.5)!;
      }
      return Color.lerp(
          AppColors.divergeZero, AppColors.divergePos, (x - 0.5) / 0.5)!;
    }
    final x = t(v); // speed
    if (x < 0.5) {
      return Color.lerp(AppColors.path, AppColors.vBody, x / 0.5)!;
    }
    return Color.lerp(
        AppColors.vBody, const Color(0xFFD55E00), (x - 0.5) / 0.5)!;
  }

  void _drawRobotGhost(Canvas canvas, Offset center, double yaw, double s) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-yaw);
    final lw = cons.wheelBase * s;
    final ww = cons.trackWidth * s;
    final rect = Rect.fromCenter(center: Offset.zero, width: lw, height: ww);
    canvas.drawRRect(
        RRect.fromRectXY(rect, 6, 6), Paint()..color = AppColors.robotFill);
    canvas.drawRRect(
      RRect.fromRectXY(rect, 6, 6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.robotStroke,
    );
    final p = Paint()
      ..strokeWidth = 3
      ..color = AppColors.robotStroke;
    canvas.drawLine(Offset(-lw * 0.28, 0), Offset(lw * 0.28, 0), p);
    canvas.drawLine(Offset(lw * 0.28, 0), Offset(lw * 0.18, -ww * 0.14), p);
    canvas.drawLine(Offset(lw * 0.28, 0), Offset(lw * 0.18, ww * 0.14), p);
    canvas.restore();
  }

  void _drawYawMarker(Canvas canvas, Offset c, double yaw, double s) {
    final len = 0.35 * s;
    final dir = Offset(math.cos(-yaw), math.sin(-yaw));
    final tip = c + dir * (len * 1.2);
    canvas.drawCircle(c, 8, Paint()..color = AppColors.yawHalo);
    canvas.drawLine(
        c,
        tip,
        Paint()
          ..color = AppColors.yawMarker
          ..strokeWidth = 3
          ..isAntiAlias = true);
    const ang = 22.0 * math.pi / 180.0;
    const headLen = 12.0;
    final a = math.atan2(dir.dy, dir.dx);
    final p1 = tip +
        Offset(-headLen * math.cos(a - ang), -headLen * math.sin(a - ang));
    final p2 = tip +
        Offset(-headLen * math.cos(a + ang), -headLen * math.sin(a + ang));
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(head, Paint()..color = AppColors.yawMarker);
  }

  @override
  bool shouldRepaint(covariant _AestheticOverlayPainter old) {
    return old.planned != planned ||
        old.waypoints != waypoints ||
        old.cfg != cfg ||
        old.cons != cons ||
        old.layer != layer;
  }
}

class _MetricResult {
  final List<double> values;
  final double min, max;
  const _MetricResult(this.values, this.min, this.max);
}

// ===== Swerve Overlay (vectors) =====
class _SwerveOverlayPainter extends CustomPainter {
  final FieldConfig cfg;
  final Constraints cons;
  final _Kine kine;

  _SwerveOverlayPainter(
      {required this.cfg, required this.cons, required this.kine});

  @override
  void paint(Canvas canvas, Size size) {
    final fw = cfg.fieldSizeMeters.width;
    final fh = cfg.fieldSizeMeters.height;
    final s = math.min(size.width / fw, size.height / fh);
    final dx = (size.width - fw * s) / 2.0;
    final dy = (size.height - fh * s) / 2.0;

    Offset toPx(Offset m) => Offset(dx + m.dx * s, dy + (fh - m.dy) * s);

    final center = toPx(kine.pos);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-kine.yaw);
    final lw = cons.wheelBase * s;
    final ww = cons.trackWidth * s;
    final rect = Rect.fromCenter(center: Offset.zero, width: lw, height: ww);
    canvas.drawRRect(
        RRect.fromRectXY(rect, 6, 6), Paint()..color = AppColors.robotFill);
    canvas.drawRRect(
      RRect.fromRectXY(rect, 6, 6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.robotStroke,
    );
    final head = Paint()
      ..strokeWidth = 3
      ..color = AppColors.robotStroke;
    canvas.drawLine(Offset(-lw * 0.3, 0), Offset(lw * 0.3, 0), head);
    canvas.drawLine(Offset(lw * 0.3, 0), Offset(lw * 0.2, -ww * 0.15), head);
    canvas.drawLine(Offset(lw * 0.3, 0), Offset(lw * 0.2, ww * 0.15), head);
    canvas.restore();

    final vWorldPx = kine.vWorld * (s * 0.6);
    if (vWorldPx.distance > 1.0) {
      _drawArrow(
          canvas,
          center,
          center + Offset(vWorldPx.dx, -vWorldPx.dy),
          Paint()
            ..strokeWidth = 3
            ..color = AppColors.vWorld,
          10,
          26);
    }

    final vBodyPx = Offset(kine.vBody.dx, -kine.vBody.dy) * (s * 0.6);
    if (vBodyPx.distance > 1.0) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-kine.yaw);
      _drawArrow(
          canvas,
          Offset.zero,
          vBodyPx,
          Paint()
            ..strokeWidth = 2
            ..color = AppColors.vBody,
          8,
          22);
      canvas.restore();
    }

    final omegaMag = kine.omega;
    if (omegaMag.abs() > 1e-3) {
      final r = cons.trackWidth * s * 0.6;
      final pa = Paint()
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..color = AppColors.omega;
      final start = -kine.yaw;
      final sweepSign = -omegaMag.sign;
      final sweep = sweepSign * 0.8;
      final rectArc = Rect.fromCircle(center: center, radius: r);
      canvas.drawArc(rectArc, start, sweep, false, pa);
      final endAngle = start + sweep;
      final endPt =
          center + Offset(r * math.cos(endAngle), r * math.sin(endAngle));
      final tanDir = endAngle + (math.pi / 2) * sweepSign;
      _drawArrowHead(canvas, endPt, tanDir, AppColors.omega, 9, 20);
    }

    final text =
        "t=${kine.time.toStringAsFixed(2)}s  |v|=${kine.speed.toStringAsFixed(2)}m/s  "
        "v_body=(${kine.vBody.dx.toStringAsFixed(2)}, ${kine.vBody.dy.toStringAsFixed(2)}) "
        "ω=${kine.omega.toStringAsFixed(2)}rad/s  yaw=${(kine.yaw * 180 / math.pi).toStringAsFixed(1)}°";

    final textPainter = TextPainter(
      text: TextSpan(
          style: const TextStyle(color: Colors.white, fontSize: 12),
          text: text),
      textDirection: TextDirection.ltr,
    )..layout();
    const pad = 4.0;
    final rText = Rect.fromLTWH(
        8, 8, textPainter.width + pad * 2, textPainter.height + pad * 2);
    canvas.drawRRect(RRect.fromRectAndRadius(rText, const Radius.circular(6)),
        Paint()..color = const Color(0xAA000000));
    textPainter.paint(canvas, const Offset(8 + pad, 8 + pad));
  }

  void _drawArrow(Canvas canvas, Offset a, Offset b, Paint p, double headLen,
      double headAngDeg) {
    canvas.drawLine(a, b, p);
    final v = b - a;
    if (v.distance < 1e-6) return;
    final ang = math.atan2(v.dy, v.dx);
    _drawArrowHead(canvas, b, ang, p.color, headLen, headAngDeg);
  }

  void _drawArrowHead(Canvas canvas, Offset tip, double angle, Color color,
      double len, double angDeg) {
    final ang = angDeg * math.pi / 180.0;
    final pHead = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final p1 = tip +
        Offset(-len * math.cos(angle - ang), -len * math.sin(angle - ang));
    final p2 = tip +
        Offset(-len * math.cos(angle + ang), -len * math.sin(angle + ang));
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(path, pHead);
  }

  @override
  bool shouldRepaint(covariant _SwerveOverlayPainter old) {
    return old.kine.time != kine.time || old.cons != cons || old.cfg != cfg;
  }
}

// =================== Analyze Panel（單一卡片，自適應 2x2 網格） ===================
class _AnalyzePanel extends StatelessWidget {
  final List<PathPoint> points;
  final Constraints cons;
  final double time;
  final ValueChanged<double> onSeekTime;
  const _AnalyzePanel({
    required this.points,
    required this.cons,
    required this.time,
    required this.onSeekTime,
  });

  @override
  Widget build(BuildContext context) {
    final totalT = points.isNotEmpty ? points.last.time : 1.0;
    final totalS = points.isNotEmpty ? points.last.s : 1.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Analyze",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: _MiniChart(
                              labelLeft: "v(t) m/s",
                              domainLabel: "t (s)",
                              domainMin: 0,
                              domainMax: totalT,
                              samples: points
                                  .map((p) => Offset(p.time, p.velocity))
                                  .toList(),
                              cursorX: time,
                              onTapX: onSeekTime,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _MiniChart(
                              labelLeft: "a(t) m/s²",
                              domainLabel: "t (s)",
                              domainMin: 0,
                              domainMax: totalT,
                              samples: points
                                  .map((p) => Offset(p.time, p.acceleration))
                                  .toList(),
                              cursorX: time,
                              onTapX: onSeekTime,
                              symmetricY: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: _MiniChart(
                              labelLeft: "ω(t) rad/s",
                              domainLabel: "t (s)",
                              domainMin: 0,
                              domainMax: totalT,
                              samples: points
                                  .map((p) => Offset(p.time, p.yawRate))
                                  .toList(),
                              cursorX: time,
                              onTapX: onSeekTime,
                              symmetricY: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _MiniChart(
                              labelLeft: "κ(s) 1/m",
                              domainLabel: "s (m)",
                              domainMin: 0, domainMax: totalS,
                              samples: points
                                  .map((p) => Offset(p.s, p.curvature))
                                  .toList(),
                              // s -> t
                              onTapX: (sx) {
                                double bestDt = 1e9, bestT = time;
                                for (final p in points) {
                                  final d = (p.s - sx).abs();
                                  if (d < bestDt) {
                                    bestDt = d;
                                    bestT = p.time;
                                  }
                                }
                                onSeekTime(bestT);
                              },
                              cursorX: (() {
                                double sx = 0;
                                for (int i = 0; i < points.length - 1; i++) {
                                  final a = points[i], b = points[i + 1];
                                  if (time >= a.time && time <= b.time) {
                                    final r =
                                        (time - a.time) / (b.time - a.time);
                                    sx = a.s + (b.s - a.s) * r;
                                    break;
                                  }
                                }
                                return sx;
                              })(),
                              symmetricY: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChart extends StatelessWidget {
  final String labelLeft;
  final String domainLabel;
  final double domainMin;
  final double domainMax;
  final List<Offset> samples; // x=domain, y=value
  final double? cursorX;
  final bool symmetricY;
  final ValueChanged<double>? onTapX;
  const _MiniChart({
    required this.labelLeft,
    required this.domainLabel,
    required this.domainMin,
    required this.domainMax,
    required this.samples,
    this.cursorX,
    this.onTapX,
    this.symmetricY = false,
  });

  @override
  Widget build(BuildContext context) {
    final chart = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        if (onTapX == null) return;
        final w = context.size!.width;
        final plotW = w - _ChartPainter._padL - _ChartPainter._padR;
        final xLocal =
            (d.localPosition.dx - _ChartPainter._padL).clamp(0.0, plotW);
        final t = domainMin + (xLocal / plotW) * (domainMax - domainMin);
        onTapX!(t);
      },
      child: CustomPaint(
        painter: _ChartPainter(
          samples: samples,
          labelLeft: labelLeft,
          domainLabel: domainLabel,
          domainMin: domainMin,
          domainMax: domainMax,
          cursorX: cursorX,
          symmetricY: symmetricY,
        ),
      ),
    );

    return SizedBox.expand(child: chart);
  }
}

class _ChartPainter extends CustomPainter {
  final List<Offset> samples;
  final String labelLeft;
  final String domainLabel;
  final double domainMin;
  final double domainMax;
  final double? cursorX;
  final bool symmetricY;
  static const _padL = 48.0, _padR = 16.0, _padT = 8.0, _padB = 22.0;

  _ChartPainter({
    required this.samples,
    required this.labelLeft,
    required this.domainLabel,
    required this.domainMin,
    required this.domainMax,
    required this.cursorX,
    required this.symmetricY,
  });

  late Rect _plot;

  @override
  void paint(Canvas canvas, Size size) {
    _plot = Rect.fromLTWH(
        _padL, _padT, size.width - _padL - _padR, size.height - _padT - _padB);

    final axis = Paint()
      ..color = const Color(0xFF3A4A5A)
      ..strokeWidth = 1;
    canvas.drawRect(_plot, Paint()..color = const Color(0x11111111));
    for (int i = 0; i <= 4; i++) {
      final x = _plot.left + _plot.width * i / 4;
      canvas.drawLine(Offset(x, _plot.bottom), Offset(x, _plot.top),
          axis..color = const Color(0x223A4A5A));
    }
    for (int i = 0; i <= 4; i++) {
      final y = _plot.top + _plot.height * i / 4;
      canvas.drawLine(Offset(_plot.left, y), Offset(_plot.right, y),
          axis..color = const Color(0x223A4A5A));
    }

    void tp(String s, Offset p, {double fs = 11, Color c = Colors.white}) {
      final t = TextPainter(
          text: TextSpan(text: s, style: TextStyle(fontSize: fs, color: c)),
          textDirection: TextDirection.ltr)
        ..layout();
      t.paint(canvas, p);
    }

    tp(labelLeft, Offset(4, _plot.top - 2));
    tp(domainLabel, Offset(_plot.left + _plot.width / 2 - 12, _plot.bottom + 2),
        fs: 10, c: const Color(0xFFB0BEC5));

    if (samples.isEmpty) return;

    double minY = samples.first.dy, maxY = samples.first.dy;
    for (final s in samples) {
      if (s.dy < minY) minY = s.dy;
      if (s.dy > maxY) maxY = s.dy;
    }
    if (symmetricY) {
      final a = math.max(maxY.abs(), minY.abs());
      minY = -a;
      maxY = a;
    }
    if ((maxY - minY).abs() < 1e-9) {
      maxY += 1;
      minY -= 1;
    }

    Offset map(Offset d) {
      final x = _plot.left +
          (d.dx - domainMin) / (domainMax - domainMin) * _plot.width;
      final y = _plot.bottom - (d.dy - minY) / (maxY - minY) * _plot.height;
      return Offset(x, y);
    }

    final p = Path();
    for (int i = 0; i < samples.length; i++) {
      final m = map(samples[i]);
      if (i == 0) {
        p.moveTo(m.dx, m.dy);
      } else {
        p.lineTo(m.dx, m.dy);
      }
    }
    canvas.drawPath(
        p,
        Paint()
          ..color = AppColors.path
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    if (cursorX != null) {
      final cx = _plot.left +
          (cursorX! - domainMin) / (domainMax - domainMin) * _plot.width;
      canvas.drawLine(
          Offset(cx, _plot.bottom),
          Offset(cx, _plot.top),
          Paint()
            ..color = const Color(0x55FFFFFF)
            ..strokeWidth = 1.5);
    }

    for (int i = 0; i <= 4; i++) {
      final xVal = domainMin + (domainMax - domainMin) * i / 4;
      final x = _plot.left + _plot.width * i / 4 - 10;
      tp(xVal.toStringAsFixed(2), Offset(x, _plot.bottom + 4),
          fs: 10, c: const Color(0xFF90A4AE));
    }
    for (int i = 0; i <= 4; i++) {
      final yVal = maxY - (maxY - minY) * i / 4;
      final y = _plot.top + _plot.height * i / 4 - 6;
      tp(yVal.toStringAsFixed(2), Offset(6, y),
          fs: 10, c: const Color(0xFF90A4AE));
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) {
    return old.samples != samples ||
        old.cursorX != cursorX ||
        old.domainMin != domainMin ||
        old.domainMax != domainMax ||
        old.symmetricY != symmetricY;
  }
}
