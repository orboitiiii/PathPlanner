import 'dart:ui';

/// 航點類型
/// - start: 起點（速度 = 0）
/// - pass: 必經點（速度 = 0，機器人會停車）
/// - passThrough: 通過點（速度 ≠ 0，機器人不停車直接通過）
/// - end: 終點（速度 = 0）
enum WaypointKind { start, pass, passThrough, end }

class Waypoint {
  double? thetaDeg; // degrees, 0:right, +90:up, -90:down, ±180:left
  Offset m; // position in meters
  final WaypointKind kind;
  String label;
  Waypoint(this.m, this.kind, this.label, {this.thetaDeg});
}
