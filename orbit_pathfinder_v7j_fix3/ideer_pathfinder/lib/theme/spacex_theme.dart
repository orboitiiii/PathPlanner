// lib/theme/spacex_theme.dart
//
// SpaceX 風格主題系統
// 設計原則：深色背景、青色強調、Mission Control 風格

import 'package:flutter/material.dart';

/// SpaceX 風格色彩系統
class SpaceXColors {
  SpaceXColors._();

  // 主要背景色
  static const Color background = Color(0xFF0A0A0F);
  static const Color surface = Color(0xFF12141A);
  static const Color surfaceElevated = Color(0xFF1A1D24);
  static const Color surfaceAccent = Color(0xFF1E2128);

  // 強調色
  static const Color primary = Color(0xFF00D4FF); // SpaceX 青色
  static const Color primaryMuted = Color(0xFF007A94);
  static const Color secondary = Color(0xFF4CAF50); // 綠色（成功狀態）
  static const Color warning = Color(0xFFFF9800); // 橙色（警告）
  static const Color error = Color(0xFFE53935); // 紅色（錯誤）

  // 文字色
  static const Color textPrimary = Color(0xFFE8E8E8);
  static const Color textSecondary = Color(0xFFA0A0A0);
  static const Color textMuted = Color(0xFF606060);

  // 邊框和分隔線
  static const Color divider = Color(0xFF2A2D35);
  static const Color border = Color(0xFF3A3D45);

  // 航點色彩
  static const Color waypointStart = Color(0xFF00E676); // 綠色
  static const Color waypointEnd = Color(0xFFE53935); // 紅色
  static const Color waypointStop = Color(0xFFFFD54F); // 黃色（停車點）
  static const Color waypointPassThrough = Color(0xFF00BCD4); // 青色（過點不停）

  // 數值顯示
  static const Color positive = Color(0xFF4CAF50);
  static const Color neutral = Color(0xFF00D4FF);
  static const Color negative = Color(0xFFE53935);
}

/// SpaceX 風格主題資料
ThemeData createSpaceXTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: SpaceXColors.background,
    colorScheme: const ColorScheme.dark(
      primary: SpaceXColors.primary,
      secondary: SpaceXColors.secondary,
      surface: SpaceXColors.surface,
      error: SpaceXColors.error,
    ),
    cardTheme: CardTheme(
      color: SpaceXColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: SpaceXColors.border, width: 1),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: SpaceXColors.divider,
      thickness: 1,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: SpaceXColors.textPrimary,
        fontWeight: FontWeight.w300,
        letterSpacing: 2,
      ),
      headlineMedium: TextStyle(
        color: SpaceXColors.textPrimary,
        fontWeight: FontWeight.w400,
        letterSpacing: 1,
      ),
      titleLarge: TextStyle(
        color: SpaceXColors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      titleMedium: TextStyle(
        color: SpaceXColors.textSecondary,
        fontWeight: FontWeight.w400,
      ),
      bodyLarge: TextStyle(color: SpaceXColors.textPrimary),
      bodyMedium: TextStyle(color: SpaceXColors.textSecondary),
      labelLarge: TextStyle(
        color: SpaceXColors.primary,
        fontWeight: FontWeight.w500,
        letterSpacing: 1,
      ),
    ),
    iconTheme: const IconThemeData(color: SpaceXColors.textSecondary),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SpaceXColors.primary,
        foregroundColor: SpaceXColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SpaceXColors.primary,
        side: const BorderSide(color: SpaceXColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SpaceXColors.surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: SpaceXColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: SpaceXColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: SpaceXColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      isDense: true,
      labelStyle: const TextStyle(color: SpaceXColors.textMuted),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: SpaceXColors.primary,
      inactiveTrackColor: SpaceXColors.border,
      thumbColor: SpaceXColors.primary,
      overlayColor: SpaceXColors.primary.withValues(alpha: 0.2),
    ),
  );
}
