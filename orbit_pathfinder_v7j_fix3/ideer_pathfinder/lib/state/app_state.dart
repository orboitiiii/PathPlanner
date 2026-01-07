// lib/state/app_state.dart
//
// 全域應用狀態管理（使用 Riverpod v3）
// SpaceX Mission Control 風格架構

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/algos/advanced_path_planner.dart';
import '../domain/models/constraints.dart';
import '../domain/models/waypoint.dart';

// =================== 專案狀態 ===================

/// 單一專案資料
class ProjectData {
  final String id;
  final String name;
  final List<Waypoint> waypoints;
  final Constraints constraints;
  final List<Offset?> quadCtrls;

  const ProjectData({
    required this.id,
    required this.name,
    required this.waypoints,
    required this.constraints,
    required this.quadCtrls,
  });

  ProjectData copyWith({
    String? id,
    String? name,
    List<Waypoint>? waypoints,
    Constraints? constraints,
    List<Offset?>? quadCtrls,
  }) {
    return ProjectData(
      id: id ?? this.id,
      name: name ?? this.name,
      waypoints: waypoints ?? this.waypoints,
      constraints: constraints ?? this.constraints,
      quadCtrls: quadCtrls ?? this.quadCtrls,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'waypoints': waypoints.map(_waypointToJson).toList(),
        'constraints': _constraintsToJson(constraints),
        'quadCtrls': quadCtrls
            .map((o) => o == null ? null : {'x': o.dx, 'y': o.dy})
            .toList(),
      };

  factory ProjectData.fromJson(Map<String, dynamic> j) => ProjectData(
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

// JSON Serialization Helpers
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

/// 專案列表狀態
class ProjectsState {
  final List<ProjectData> projects;
  final String? activeProjectId;

  const ProjectsState({
    required this.projects,
    this.activeProjectId,
  });

  ProjectData? get activeProject {
    if (activeProjectId == null) return null;
    return projects.where((p) => p.id == activeProjectId).firstOrNull;
  }

  ProjectsState copyWith({
    List<ProjectData>? projects,
    String? activeProjectId,
  }) {
    return ProjectsState(
      projects: projects ?? this.projects,
      activeProjectId: activeProjectId ?? this.activeProjectId,
    );
  }
}

// =================== 播放狀態 ===================

class PlaybackState {
  final bool isPlaying;
  final double currentTime;
  final double totalTime;
  final List<PathPoint> pathPoints;

  const PlaybackState({
    this.isPlaying = false,
    this.currentTime = 0.0,
    this.totalTime = 0.0,
    this.pathPoints = const [],
  });

  PlaybackState copyWith({
    bool? isPlaying,
    double? currentTime,
    double? totalTime,
    List<PathPoint>? pathPoints,
  }) {
    return PlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      currentTime: currentTime ?? this.currentTime,
      totalTime: totalTime ?? this.totalTime,
      pathPoints: pathPoints ?? this.pathPoints,
    );
  }
}

// =================== 視圖狀態 ===================

enum LayerMode { solid, speed, accel, curvature, safety }

class ViewState {
  final LayerMode layerMode;
  final double zoomLevel;
  final Offset panOffset;

  const ViewState({
    this.layerMode = LayerMode.solid,
    this.zoomLevel = 1.0,
    this.panOffset = Offset.zero,
  });

  ViewState copyWith({
    LayerMode? layerMode,
    double? zoomLevel,
    Offset? panOffset,
  }) {
    return ViewState(
      layerMode: layerMode ?? this.layerMode,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      panOffset: panOffset ?? this.panOffset,
    );
  }
}

// =================== Providers (Riverpod v3 Notifier) ===================

/// 專案狀態 Provider
final projectsProvider =
    NotifierProvider<ProjectsNotifier, ProjectsState>(ProjectsNotifier.new);

class ProjectsNotifier extends Notifier<ProjectsState> {
  static const _prefsKey = 'projects_v1';

  @override
  ProjectsState build() => const ProjectsState(projects: []);

  Future<void> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) {
      // Create default project
      final defCons = Constraints();
      final defWps = [
        Waypoint(const Offset(2, 4), WaypointKind.start, "Start", thetaDeg: 0),
        Waypoint(const Offset(8, 4), WaypointKind.end, "End", thetaDeg: 0),
      ];
      final defCtrls = <Offset?>[
        (defWps[0].m + defWps[1].m) * 0.5 + const Offset(0, 0.1)
      ];
      final proj = ProjectData(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: "New Project",
        waypoints: defWps,
        constraints: defCons,
        quadCtrls: defCtrls,
      );
      state = ProjectsState(projects: [proj], activeProjectId: proj.id);
      saveProjects();
    } else {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final list = (decoded['items'] as List)
            .map((e) => ProjectData.fromJson(e))
            .toList();
        final selIdx = (decoded['selected'] as int?) ?? 0;

        if (list.isEmpty) throw Exception("Empty list");

        // Find ID by index or default to first
        final safeIdx = selIdx.clamp(0, list.length - 1);
        state =
            ProjectsState(projects: list, activeProjectId: list[safeIdx].id);
      } catch (_) {
        // Fallback or create default
        final defCons = Constraints();
        final defWps = [
          Waypoint(const Offset(2, 4), WaypointKind.start, "Start",
              thetaDeg: 0),
          Waypoint(const Offset(8, 4), WaypointKind.end, "End", thetaDeg: 0),
        ];
        final defCtrls = [
          (defWps[0].m + defWps[1].m) * 0.5 + const Offset(0, 0.1)
        ];
        final proj = ProjectData(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: "New Project",
          waypoints: defWps,
          constraints: defCons,
          quadCtrls: defCtrls,
        );
        state = ProjectsState(projects: [proj], activeProjectId: proj.id);
        saveProjects();
      }
    }
  }

  Future<void> saveProjects() async {
    final prefs = await SharedPreferences.getInstance();
    int selIdx = 0;
    if (state.activeProjectId != null) {
      selIdx = state.projects.indexWhere((p) => p.id == state.activeProjectId);
      if (selIdx < 0) selIdx = 0;
    }

    final payload = jsonEncode({
      'selected': selIdx,
      'items': state.projects.map((p) => p.toJson()).toList(),
    });
    await prefs.setString(_prefsKey, payload);
  }

  void updateCurrentProject({
    List<Waypoint>? waypoints,
    Constraints? constraints,
    List<Offset?>? quadCtrls,
  }) {
    final active = state.activeProject;
    if (active == null) return;
    updateProject(active.copyWith(
      waypoints: waypoints,
      constraints: constraints,
      quadCtrls: quadCtrls,
    ));
  }

  void setProjects(List<ProjectData> projects) {
    state = state.copyWith(projects: projects);
    saveProjects();
  }

  void setActiveProject(String? id) {
    state = state.copyWith(activeProjectId: id);
    saveProjects();
  }

  void addProject(ProjectData project) {
    state = state.copyWith(
      projects: [...state.projects, project],
      activeProjectId: project.id,
    );
    saveProjects();
  }

  void updateProject(ProjectData project) {
    state = state.copyWith(
      projects:
          state.projects.map((p) => p.id == project.id ? project : p).toList(),
    );
    saveProjects();
  }

  void deleteProject(String id) {
    final newProjects = state.projects.where((p) => p.id != id).toList();
    state = state.copyWith(
      projects: newProjects,
      activeProjectId: newProjects.isNotEmpty ? newProjects.first.id : null,
    );
    saveProjects();
  }

  void updateWaypoints(List<Waypoint> waypoints) {
    updateCurrentProject(waypoints: waypoints);
  }

  void updateConstraints(Constraints constraints) {
    updateCurrentProject(constraints: constraints);
  }
}

/// 播放狀態 Provider
final playbackProvider =
    NotifierProvider<PlaybackNotifier, PlaybackState>(PlaybackNotifier.new);

class PlaybackNotifier extends Notifier<PlaybackState> {
  @override
  PlaybackState build() => const PlaybackState();

  void setPathPoints(List<PathPoint> points) {
    final total = points.isNotEmpty ? points.last.time : 0.0;
    state = state.copyWith(
      pathPoints: points,
      totalTime: total,
      currentTime: state.currentTime.clamp(0.0, total),
    );
  }

  void play() => state = state.copyWith(isPlaying: true);
  void pause() => state = state.copyWith(isPlaying: false);
  void stop() => state = state.copyWith(isPlaying: false, currentTime: 0.0);

  void seek(double time) {
    state = state.copyWith(currentTime: time.clamp(0.0, state.totalTime));
  }

  void tick(double dt) {
    if (!state.isPlaying) return;
    final newTime = state.currentTime + dt;
    if (newTime >= state.totalTime) {
      state = state.copyWith(isPlaying: false, currentTime: state.totalTime);
    } else {
      state = state.copyWith(currentTime: newTime);
    }
  }
}

/// 視圖狀態 Provider
final viewProvider =
    NotifierProvider<ViewNotifier, ViewState>(ViewNotifier.new);

class ViewNotifier extends Notifier<ViewState> {
  @override
  ViewState build() => const ViewState();

  void setLayerMode(LayerMode mode) {
    state = state.copyWith(layerMode: mode);
  }

  void setZoom(double level) {
    state = state.copyWith(zoomLevel: level.clamp(0.5, 3.0));
  }

  void setPan(Offset offset) {
    state = state.copyWith(panOffset: offset);
  }
}

/// 當前插值的路徑點 Provider
final currentPathPointProvider = Provider<PathPoint?>((ref) {
  final playback = ref.watch(playbackProvider);
  if (playback.pathPoints.isEmpty) return null;

  final t = playback.currentTime;
  final points = playback.pathPoints;

  // 找到合適的插值區間
  if (t <= 0) return points.first;
  if (t >= playback.totalTime) return points.last;

  for (int i = 0; i < points.length - 1; i++) {
    if (points[i].time <= t && t <= points[i + 1].time) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final dt = p1.time - p0.time;
      if (dt < 1e-9) return p0;
      final ratio = (t - p0.time) / dt;
      return PathPoint(
        s: p0.s + (p1.s - p0.s) * ratio,
        time: t,
        position: Offset(
          p0.position.dx + (p1.position.dx - p0.position.dx) * ratio,
          p0.position.dy + (p1.position.dy - p0.position.dy) * ratio,
        ),
        velocity: p0.velocity + (p1.velocity - p0.velocity) * ratio,
        acceleration:
            p0.acceleration + (p1.acceleration - p0.acceleration) * ratio,
        heading: p0.heading + (p1.heading - p0.heading) * ratio,
        yaw: p0.yaw + (p1.yaw - p0.yaw) * ratio,
        yawRate: p0.yawRate + (p1.yawRate - p0.yawRate) * ratio,
        curvature: p0.curvature + (p1.curvature - p0.curvature) * ratio,
      );
    }
  }
  return points.last;
});
