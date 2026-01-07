// lib/features/panels/constraints_panel.dart
import 'package:flutter/material.dart';

import '../../domain/models/constraints.dart';

class ConstraintsPanel extends StatefulWidget {
  final Constraints constraints;
  final void Function(Constraints) onApply;
  const ConstraintsPanel(
      {super.key, required this.constraints, required this.onApply});

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
      "TW": TextEditingController(text: s.trackWidth.toStringAsFixed(3)),
      "WB": TextEditingController(text: s.wheelBase.toStringAsFixed(3)),
      "vWheel": TextEditingController(text: s.wheelSpeedMax.toStringAsFixed(2)),
      "wMax": TextEditingController(text: s.yawRateMax.toStringAsFixed(2)),
      "mu": TextEditingController(text: s.mu.toStringAsFixed(2)),
      "g": TextEditingController(text: s.g.toStringAsFixed(5)),
      "latSafe": TextEditingController(
          text: s.lateralAccelSafetyFactor.toStringAsFixed(2)),
    };
  }

  @override
  void dispose() {
    for (final e in c.values) {
      e.dispose();
    }
    super.dispose();
  }

  Widget _num(String label, String key, {String? suffix}) {
    return Expanded(
      child: TextField(
        controller: c[key],
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(
            isDense: true, labelText: label, suffixText: suffix),
      ),
    );
  }

  double _p(String k, double fallback, {double? min0}) {
    final v = double.tryParse(c[k]!.text) ?? fallback;
    return (min0 != null && v < min0) ? min0 : v;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("限制 / 幾何（Swerve）",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Row(children: [
          _num("v_max", "vMax", suffix: "m/s"),
          const SizedBox(width: 8),
          _num("v_min", "vMin", suffix: "m/s")
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _num("a_max", "aMax", suffix: "m/s²"),
          const SizedBox(width: 8),
          _num("a_min", "aMin", suffix: "m/s²")
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _num("TrackWidth", "TW", suffix: "m"),
          const SizedBox(width: 8),
          _num("WheelBase", "WB", suffix: "m")
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _num("Wheel v_max", "vWheel", suffix: "m/s"),
          const SizedBox(width: 8),
          _num("ω_max", "wMax", suffix: "rad/s")
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _num("μ", "mu", suffix: "-"),
          const SizedBox(width: 8),
          _num("g", "g", suffix: "m/s²")
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _num("向心加速安全係數", "latSafe", suffix: "-"),
          const Spacer(),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Spacer(),
          FilledButton.icon(
            onPressed: () {
              final s = widget.constraints;
              final d = Constraints(
                vMax: _p("vMax", s.vMax),
                vMin: _p("vMin", s.vMin),
                aMax: _p("aMax", s.aMax),
                aMin: _p("aMin", s.aMin),
                trackWidth: _p("TW", s.trackWidth),
                wheelBase: _p("WB", s.wheelBase),
                wheelSpeedMax: _p("vWheel", s.wheelSpeedMax),
                yawRateMax: _p("wMax", s.yawRateMax),
                mu: _p("mu", s.mu),
                g: _p("g", s.g),
                lateralAccelSafetyFactor:
                    _p("latSafe", s.lateralAccelSafetyFactor, min0: 0.1),
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
