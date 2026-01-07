import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui' as ui;

import '../../theme/spacex_theme.dart';
import '../../features/field/widgets/field_canvas.dart';
import '../../domain/models/field_config.dart';
import '../../domain/models/waypoint.dart';
import '../../domain/models/constraints.dart';
import '../../domain/algos/advanced_path_planner.dart'; // PathPoint
import '../panels/analyze_panel.dart'; // Will refactor this later, reusing for now

// Placeholder for Sidebar
import '../panels/constraints_panel.dart';
import '../panels/waypoints_panel.dart'; // Use legacy for now

class DashboardPage extends ConsumerStatefulWidget {
  final FieldConfig cfg;
  final List<Waypoint> waypoints;
  final Constraints cons;
  final List<PathPoint> plannedPathPoints;
  final List<Offset?> quadCtrls;
  final double currentTime;
  final bool isPlaying;
  final ui.Image? bgImage;

  // Callbacks
  final VoidCallback onMenuPressed; // To open drawer
  final ValueChanged<double> onSeekTime;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final ValueChanged<Constraints> onConstraintsChanged;
  final ValueChanged<List<Waypoint>> onWaypointsChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onSave;
  final VoidCallback onLoad;
  final VoidCallback onNewProject;
  final VoidCallback onRenameProject;
  final VoidCallback onDeleteProject;
  final GlobalKey<ScaffoldState> scaffoldKey;

  const DashboardPage({
    super.key,
    required this.scaffoldKey, // Add this
    required this.cfg,
    required this.waypoints,
    required this.cons,
    required this.plannedPathPoints,
    required this.quadCtrls,
    required this.currentTime,
    required this.isPlaying,
    this.bgImage,
    required this.onMenuPressed,
    required this.onSeekTime,
    required this.onPlayPause,
    required this.onStop,
    required this.onConstraintsChanged,
    required this.onWaypointsChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
    required this.onLoad,
    required this.onNewProject,
    required this.onRenameProject,
    required this.onDeleteProject,
  });

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: widget.scaffoldKey,
      backgroundColor: SpaceXColors.background,
      appBar: _buildAppBar(),
      drawer: _buildDrawer(), // The "Menu" requested
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            // Top Section: Field (Left) + Main Chart (Right)
            Expanded(
              flex: 6,
              child: Row(
                children: [
                  // Field Panel
                  Expanded(
                    flex: 4,
                    child: _DashboardPanel(
                      title: "FIELD VIEW",
                      child: FieldCanvas(
                        cfg: widget.cfg,
                        waypoints: widget.waypoints,
                        plannedPathPoints: widget.plannedPathPoints,
                        quadCtrls: widget.quadCtrls,
                        cons: widget.cons,
                        bgImage: widget.bgImage,
                        onChanged: widget.onWaypointsChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Main Chart Panel
                  Expanded(
                    flex: 6,
                    child: _DashboardPanel(
                      title: "VELOCITY / ACCEL",
                      child: AnalyzePanel(
                        // We will reuse AnalyzePanel logic but maybe need to tweak it to fit
                        points: widget.plannedPathPoints,
                        cons: widget.cons,
                        time: widget.currentTime,
                        onSeekTime: widget.onSeekTime,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Bottom Section: Secondary Charts
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Expanded(
                    child: _DashboardPanel(
                      title: "EVENTS",
                      child: Center(
                          child: Text("Event Timeline (TODO)",
                              style: TextStyle(color: SpaceXColors.textMuted))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DashboardPanel(
                      title: "OTHER METRICS",
                      child: Center(
                          child: Text("Voltage / Current (Simulated)",
                              style: TextStyle(color: SpaceXColors.textMuted))),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom Control Bar (Timeline)
            const SizedBox(height: 8),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: SpaceXColors.surface,
      title: const Text("IDEER DASHBOARD", style: TextStyle(letterSpacing: 2)),
      centerTitle: true,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.menu),
        onPressed: widget.onMenuPressed,
      ),
      actions: [
        IconButton(icon: const Icon(Icons.undo), onPressed: widget.onUndo),
        IconButton(icon: const Icon(Icons.redo), onPressed: widget.onRedo),
        IconButton(icon: const Icon(Icons.save), onPressed: widget.onSave),
        IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed:
                widget.onLoad), // Just a placeholder for project mgmt logic
      ],
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: SpaceXColors.surfaceElevated,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: SpaceXColors.surface),
            child: Center(
                child: Text("CONFIGURATION",
                    style: TextStyle(
                        color: SpaceXColors.primary,
                        fontSize: 18,
                        letterSpacing: 2))),
          ),
          // Project Management Section
          ListTile(
            leading: const Icon(Icons.create_new_folder,
                color: SpaceXColors.textSecondary),
            title: const Text("New Project",
                style: TextStyle(color: SpaceXColors.textPrimary)),
            onTap: widget.onNewProject,
          ),
          ListTile(
            leading: const Icon(Icons.edit, color: SpaceXColors.textSecondary),
            title: const Text("Rename Project",
                style: TextStyle(color: SpaceXColors.textPrimary)),
            onTap: widget.onRenameProject,
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: SpaceXColors.error),
            title: const Text("Delete Project",
                style: TextStyle(color: SpaceXColors.textPrimary)),
            onTap: widget.onDeleteProject,
          ),
          const Divider(color: SpaceXColors.border),

          ExpansionTile(
            title: const Text("Robot Config",
                style: TextStyle(color: SpaceXColors.textPrimary)),
            leading: const Icon(Icons.settings, color: SpaceXColors.primary),
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ConstraintsPanel(
                  constraints: widget.cons,
                  onApply: widget.onConstraintsChanged,
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text("Waypoints",
                style: TextStyle(color: SpaceXColors.textPrimary)),
            leading: const Icon(Icons.map, color: SpaceXColors.primary),
            initiallyExpanded: true,
            children: [
              SizedBox(
                height: 400,
                child: SingleChildScrollView(
                  child: WaypointsPanel(
                    cfg: widget.cfg,
                    waypoints: widget.waypoints,
                    onAddPass: () {
                      // We need to add a pass point. Assuming callback needs to trigger setState in parent
                      // But wait, WaypointsPanel in main.dart calls `_addWaypoint`.
                      // DashboardPage doesn't have `_addWaypoint` logic.
                      // It delegates to `onWaypointsChanged`, but WaypointsPanel expects specific function signatures.
                      // FOR NOW: We will modify WaypointsPanel to handle its own logic OR we bridge it here.
                      // Actually, we should refactor WaypointsPanel to just emit "OnChanged" entire list?
                      // The current WaypointsPanel has `onAddPass`, `onUpdateStart` etc.
                      // We need to pass these through from DashboardPage props.
                      // Let's assume we add them to DashboardPage props in next step if checking fails.
                      // OR, simpler: We construct the logic here? No, main.dart has the logic.
                      // We will rely on `onWaypointsChanged` to handle everything? No, `WaypointsPanel` is granular.
                      // Let's add the specific callbacks to DashboardPage.
                    },
                    onAddPassThrough: () {},
                    onUpdateStart: (x, y, h) {},
                    onUpdateEnd: (x, y, h) {},
                    onUpdatePass: (i, x, y, h) {},
                    onDeletePass: (i) {},
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: SpaceXColors.surface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(widget.isPlaying ? Icons.pause : Icons.play_arrow),
            color: SpaceXColors.primary,
            onPressed: widget.onPlayPause,
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            color: SpaceXColors.error,
            onPressed: widget.onStop,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("TIME ${_fmtTime(widget.currentTime)}",
                    style: const TextStyle(
                        color: SpaceXColors.textSecondary,
                        fontSize: 10,
                        fontFamily: 'monospace')),
                LinearProgressIndicator(
                  value: (widget.plannedPathPoints.isNotEmpty)
                      ? (widget.currentTime /
                              widget.plannedPathPoints.last.time)
                          .clamp(0.0, 1.0)
                      : 0.0,
                  backgroundColor: SpaceXColors.background,
                  color: SpaceXColors.primary,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  String _fmtTime(double t) {
    final m = (t / 60).floor();
    final s = (t % 60);
    return "${m.toString().padLeft(2, '0')}:${s.toStringAsFixed(2).padLeft(5, '0')}";
  }
}

class _DashboardPanel extends StatelessWidget {
  final String title;
  final Widget child;
  const _DashboardPanel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SpaceXColors.surface,
        border: Border.all(color: SpaceXColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: SpaceXColors.border)),
            ),
            child: Text(title,
                style: const TextStyle(
                    color: SpaceXColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
