
import 'package:flutter/material.dart';
import '../../domain/models/constraints.dart';

class ConstraintsPanel extends StatefulWidget {
  final Constraints constraints;
  final void Function(Constraints) onApply;
  const ConstraintsPanel({super.key, required this.constraints, required this.onApply});

  @override
  State<ConstraintsPanel> createState() => _ConstraintsPanelState();
}

class _ConstraintsPanelState extends State<ConstraintsPanel> {
  late final Map<String, TextEditingController> c;

  @override
  void initState() {
    super.initState();
    final s = widget.constraints;
    c = {
      "vMax": TextEditingController(text: s.vMax.toStringAsFixed(2)),
      "vMin": TextEditingController(text: s.vMin.toStringAsFixed(2)),
      "aMax": TextEditingController(text: s.aMax.toStringAsFixed(2)),
      "aMin": TextEditingController(text: s.aMin.toStringAsFixed(2)),
      "L": TextEditingController(text: s.robotLength.toStringAsFixed(3)),
      "W": TextEditingController(text: s.robotWidth.toStringAsFixed(3)),
      "r": TextEditingController(text: s.wheelRadius.toStringAsFixed(3)),
      "TW": TextEditingController(text: s.trackWidth.toStringAsFixed(3)),
      "WB": TextEditingController(text: s.wheelBase.toStringAsFixed(3)),
      "vWheel": TextEditingController(text: s.wheelSpeedMax.toStringAsFixed(2)),
      "wMax": TextEditingController(text: s.yawRateMax.toStringAsFixed(2)),
      "alphaMax": TextEditingController(text: s.yawAccelMax.toStringAsFixed(1)),
      "mu": TextEditingController(text: s.mu.toStringAsFixed(2)),
      "g": TextEditingController(text: s.g.toStringAsFixed(5)),
      "vStart": TextEditingController(text: s.vStart.toStringAsFixed(2)),
      "vEnd": TextEditingController(text: s.vEnd.toStringAsFixed(2)),
    };
  }

  @override
  void dispose() {
    for (final e in c.values) { e.dispose(); }
    super.dispose();
  }

  Widget _num(String label, String key, {String? suffix}) {
    return Expanded(child: TextField(
      controller: c[key],
      keyboardType: TextInputType.number,
      decoration: InputDecoration(isDense: true, labelText: label, suffixText: suffix),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("限制 / 幾何（Swerve）", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Row(children: [_num("v_max", "vMax", suffix:"m/s"), const SizedBox(width:8), _num("v_min", "vMin", suffix:"m/s")]),
        const SizedBox(height:6),
        Row(children: [_num("a_max", "aMax", suffix:"m/s²"), const SizedBox(width:8), _num("a_min", "aMin", suffix:"m/s²")]),
        const SizedBox(height:6),
        Row(children: [_num("長", "L", suffix:"m"), const SizedBox(width:8), _num("寬", "W", suffix:"m"), const SizedBox(width:8), _num("輪半徑", "r", suffix:"m")]),
        const SizedBox(height:6),
        Row(children: [_num("TrackWidth", "TW", suffix:"m"), const SizedBox(width:8), _num("WheelBase", "WB", suffix:"m")]),
        const SizedBox(height:6),
        Row(children: [_num("Wheel v_max", "vWheel", suffix:"m/s"), const SizedBox(width:8), _num("ω_max", "wMax", suffix:"rad/s"), const SizedBox(width:8), _num("α_max", "alphaMax", suffix:"rad/s²")]),
        const SizedBox(height:6),
        Row(children: [_num("μ", "mu", suffix:"-"), const SizedBox(width:8), _num("g", "g", suffix:"m/s²")]),
        const SizedBox(height:6),
        Row(children: [_num("v_start", "vStart", suffix:"m/s"), const SizedBox(width:8), _num("v_end", "vEnd", suffix:"m/s")]),
        const SizedBox(height:8),
        Row(children:[
          const Spacer(),
          FilledButton.icon(
            onPressed: () {
              final s = widget.constraints;
              final d = Constraints(
                vMax: double.tryParse(c["vMax"]!.text) ?? s.vMax,
                vMin: double.tryParse(c["vMin"]!.text) ?? s.vMin,
                aMax: double.tryParse(c["aMax"]!.text) ?? s.aMax,
                aMin: double.tryParse(c["aMin"]!.text) ?? s.aMin,
                robotLength: double.tryParse(c["L"]!.text) ?? s.robotLength,
                robotWidth: double.tryParse(c["W"]!.text) ?? s.robotWidth,
                wheelRadius: double.tryParse(c["r"]!.text) ?? s.wheelRadius,
                trackWidth: double.tryParse(c["TW"]!.text) ?? s.trackWidth,
                wheelBase: double.tryParse(c["WB"]!.text) ?? s.wheelBase,
                wheelSpeedMax: double.tryParse(c["vWheel"]!.text) ?? s.wheelSpeedMax,
                yawRateMax: double.tryParse(c["wMax"]!.text) ?? s.yawRateMax,
                yawAccelMax: double.tryParse(c["alphaMax"]!.text) ?? s.yawAccelMax,
                mu: double.tryParse(c["mu"]!.text) ?? s.mu,
                g: double.tryParse(c["g"]!.text) ?? s.g,
                vStart: double.tryParse(c["vStart"]!.text) ?? s.vStart,
                vEnd: double.tryParse(c["vEnd"]!.text) ?? s.vEnd,
              );
              widget.onApply(d);
            },
            icon: const Icon(Icons.save),
            label: const Text("套用"),
          ),
        ]),
        const Divider(),
      ],
    );
  }
}
