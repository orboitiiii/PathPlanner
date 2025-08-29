import 'dart:ui';

enum WaypointKind { start, pass, end }

class Waypoint {
  double? thetaDeg; // degrees, 0:right, +90:up, -90:down, ±180:left
  Offset m; // position in meters
  final WaypointKind kind;
  String label;
  Waypoint(this.m, this.kind, this.label, {this.thetaDeg});
}
