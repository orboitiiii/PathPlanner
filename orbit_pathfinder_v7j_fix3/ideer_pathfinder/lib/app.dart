// lib/app.dart
//
// 應用程式根 Widget
// 使用 Riverpod 提供全域狀態

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/spacex_theme.dart';

/// App 根 Widget
class PathfinderApp extends StatelessWidget {
  final Widget home;

  const PathfinderApp({
    super.key,
    required this.home,
  });

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'Orbit Pathfinder',
        theme: createSpaceXTheme(),
        home: home,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
