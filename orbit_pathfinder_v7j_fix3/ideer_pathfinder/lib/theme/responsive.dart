// lib/theme/responsive.dart
//
// 響應式佈局系統
// 支援不同螢幕尺寸的自適應佈局

import 'package:flutter/material.dart';

/// 斷點定義
class Breakpoints {
  static const double compact = 600; // 手機
  static const double medium = 840; // 平板直向
  static const double expanded = 1200; // 平板橫向/小桌面
  static const double large = 1600; // 大桌面
}

/// 螢幕尺寸類型
enum ScreenSize { compact, medium, expanded, large }

/// 響應式佈局輔助類
class ResponsiveLayout {
  final BuildContext context;

  ResponsiveLayout(this.context);

  double get width => MediaQuery.of(context).size.width;
  double get height => MediaQuery.of(context).size.height;

  ScreenSize get screenSize {
    if (width < Breakpoints.compact) return ScreenSize.compact;
    if (width < Breakpoints.medium) return ScreenSize.medium;
    if (width < Breakpoints.expanded) return ScreenSize.expanded;
    return ScreenSize.large;
  }

  bool get isCompact => screenSize == ScreenSize.compact;
  bool get isMedium => screenSize == ScreenSize.medium;
  bool get isExpanded => screenSize == ScreenSize.expanded;
  bool get isLarge => screenSize == ScreenSize.large;

  /// 左側面板寬度
  double get leftPanelWidth {
    switch (screenSize) {
      case ScreenSize.compact:
        return 0; // 隱藏面板
      case ScreenSize.medium:
        return 280;
      case ScreenSize.expanded:
        return 320;
      case ScreenSize.large:
        return 360;
    }
  }

  /// 是否顯示左側面板
  bool get showLeftPanel => !isCompact;

  /// 是否使用底部導航欄
  bool get useBottomNav => isCompact;

  /// 標題字體大小
  double get headlineFontSize {
    switch (screenSize) {
      case ScreenSize.compact:
        return 18;
      case ScreenSize.medium:
        return 20;
      case ScreenSize.expanded:
      case ScreenSize.large:
        return 24;
    }
  }

  /// 遙測欄高度
  double get telemetryBarHeight {
    switch (screenSize) {
      case ScreenSize.compact:
        return 100;
      case ScreenSize.medium:
        return 120;
      case ScreenSize.expanded:
      case ScreenSize.large:
        return 140;
    }
  }
}

/// 響應式佈局 Builder Widget
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, ResponsiveLayout layout) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return builder(context, ResponsiveLayout(context));
      },
    );
  }
}

/// 間距常數
class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const EdgeInsets panelPadding = EdgeInsets.all(lg);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets inputPadding =
      EdgeInsets.symmetric(horizontal: md, vertical: sm);
}

/// 動畫常數
class Durations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
}

/// 圓角常數
class Radii {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
}
