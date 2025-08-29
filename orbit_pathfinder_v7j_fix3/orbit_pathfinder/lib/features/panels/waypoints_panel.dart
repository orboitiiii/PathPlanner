
import 'package:flutter/material.dart';
import '../../domain/models/field_config.dart';
import '../../domain/models/waypoint.dart';

class WaypointsPanel extends StatefulWidget {
  final FieldConfig cfg;
  final List<Waypoint> waypoints;
  final VoidCallback onAddPass;
  final void Function(double x, double y, double? thetaDeg) onUpdateStart;
  final void Function(double x, double y, double? thetaDeg) onUpdateEnd;
  final void Function(int passIdx, double x, double y, double? thetaDeg) onUpdatePass;
  final void Function(int passIdx) onDeletePass;
  const WaypointsPanel({
    super.key,
    required this.cfg,
    required this.waypoints,
    required this.onAddPass,
    required this.onUpdateStart,
    required this.onUpdateEnd,
    required this.onUpdatePass,
    required this.onDeletePass,
  });

  @override
  State<WaypointsPanel> createState() => _WaypointsPanelState();
}

class _WaypointsPanelState extends State<WaypointsPanel> {
  late TextEditingController sx, sy, st, ex, ey, et;
  final List<TextEditingController> pxs = [];
  final List<TextEditingController> pys = [];
  final List<TextEditingController> pts = [];

  @override
  void initState() {
    super.initState();
    _initOrUpdateControllers(fullRebuild: true);
  }

  @override
  void didUpdateWidget(covariant WaypointsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waypoints != widget.waypoints) {
      _initOrUpdateControllers(fullRebuild: false);
      setState((){});
    }
  }

  void _initOrUpdateControllers({required bool fullRebuild}) {
    final sM = widget.waypoints.first.m;
    final eM = widget.waypoints.last.m;
    final sT = widget.waypoints.first.thetaDeg ?? 0.0;
    final eT = widget.waypoints.last.thetaDeg ?? 0.0;
    if (fullRebuild) {
      sx = TextEditingController(text: sM.dx.toStringAsFixed(3));
      sy = TextEditingController(text: sM.dy.toStringAsFixed(3));
      st = TextEditingController(text: sT.toStringAsFixed(1));
      ex = TextEditingController(text: eM.dx.toStringAsFixed(3));
      ey = TextEditingController(text: eM.dy.toStringAsFixed(3));
      et = TextEditingController(text: eT.toStringAsFixed(1));
    } else {
      sx.text = sM.dx.toStringAsFixed(3);
      sy.text = sM.dy.toStringAsFixed(3);
      st.text = sT.toStringAsFixed(1);
      ex.text = eM.dx.toStringAsFixed(3);
      ey.text = eM.dy.toStringAsFixed(3);
      et.text = eT.toStringAsFixed(1);
    }
    final passes = widget.waypoints.where((w)=>w.kind==WaypointKind.pass).toList();
    if (pxs.length < passes.length) {
      for (int i=pxs.length;i<passes.length;i++) {
        final p = passes[i].m;
        pxs.add(TextEditingController(text: p.dx.toStringAsFixed(3)));
        pys.add(TextEditingController(text: p.dy.toStringAsFixed(3)));
        pts.add(TextEditingController(text: (passes[i].thetaDeg ?? 0.0).toStringAsFixed(1)));
      }
    } else if (pxs.length > passes.length) {
      for (int i = pxs.length - 1; i >= passes.length; i--) {
        pxs[i].dispose(); pys[i].dispose(); pts[i].dispose();
        pxs.removeLast(); pys.removeLast(); pts.removeLast();
      }
    }
    for (int i=0;i<passes.length;i++) {
      final p = passes[i].m;
      pxs[i].text = p.dx.toStringAsFixed(3);
      pys[i].text = p.dy.toStringAsFixed(3);
      pts[i].text = (passes[i].thetaDeg ?? 0.0).toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    sx.dispose(); sy.dispose(); st.dispose();
    ex.dispose(); ey.dispose(); et.dispose();
    for (final c in pxs) c.dispose();
    for (final c in pys) c.dispose();
    for (final c in pts) c.dispose();
    super.dispose();
  }

  Widget _xytheta(String title, TextEditingController cx, TextEditingController cy, TextEditingController ct, {void Function()? onDel}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) Text(title),
          Row(children: [
            Expanded(child: TextField(controller: cx, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, labelText: 'X (m)'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: cy, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, labelText: 'Y (m)'))),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: TextField(controller: ct, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, labelText: 'θ (deg)')),
            ),
            if (onDel != null) ...[const SizedBox(width: 8), IconButton(onPressed: onDel, icon: const Icon(Icons.delete_outline))],
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final passList = widget.waypoints.asMap().entries.where((e)=>e.value.kind==WaypointKind.pass).toList();
    final n = passList.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("起點 / 終點（輸入座標與角度，無法拖曳）", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        _xytheta("Start", sx, sy, st),
        Row(children: [
          const Spacer(),
          FilledButton.icon(onPressed: (){
            final x = double.tryParse(sx.text), y = double.tryParse(sy.text), t = double.tryParse(st.text);
            if (x!=null && y!=null) widget.onUpdateStart(x, y, t);
          }, icon: const Icon(Icons.save), label: const Text("套用起點")),
        ]),
        const SizedBox(height: 6),
        _xytheta("End", ex, ey, et),
        Row(children: [
          const Spacer(),
          FilledButton.icon(onPressed: (){
            final x = double.tryParse(ex.text), y = double.tryParse(ey.text), t = double.tryParse(et.text);
            if (x!=null && y!=null) widget.onUpdateEnd(x, y, t);
          }, icon: const Icon(Icons.save), label: const Text("套用終點")),
        ]),
        const Divider(height: 20),
        Row(children: [
          const Text("必經點", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          IconButton(onPressed: widget.onAddPass, icon: const Icon(Icons.add_circle_outline)),
        ]),
        const SizedBox(height: 6),
        ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: n,
            itemBuilder: (context, i) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.waypoints[1+i].label, style: const TextStyle(color: Colors.white70)),
                  _xytheta("", pxs[i], pys[i], pts[i], onDel: ()=>widget.onDeletePass(i)),
                  Row(children: [
                    const Spacer(),
                    TextButton.icon(onPressed: (){
                      final x = double.tryParse(pxs[i].text);
                      final y = double.tryParse(pys[i].text);
                      final t = double.tryParse(pts[i].text);
                      if (x!=null && y!=null) widget.onUpdatePass(i, x, y, t);
                    }, icon: const Icon(Icons.save_as), label: const Text("套用座標/角度")),
                  ]),
                  const Divider(),
                ],
              );
            },
          ),
        ],
    );
  }
}
