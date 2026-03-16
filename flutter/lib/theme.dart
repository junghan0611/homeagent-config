import 'package:flutter/material.dart';

/// 범용 IoT 앱 테마 — 회사명/브랜드명 없음
class AppTheme {
  // 브랜드 컬러
  static const orange = Color(0xFFFF6B35);
  static const blue = Color(0xFF1E88E5);
  static const green = Color(0xFF43A047);

  // 상태 컬러
  static const onColor = Color(0xFFFFA726); // 켜짐 (amber)
  static const offColor = Color(0xFF757575); // 꺼짐 (grey)
  static const errorColor = Color(0xFFEF5350); // 에러/오프라인
  static const openColor = Color(0xFFFFA726); // 열림 (contact)
  static const closedColor = Color(0xFF43A047); // 닫힘

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: orange,
        brightness: Brightness.dark,
        surface: const Color(0xFF1E1E1E),
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E1E1E),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF1A1A2E),
        indicatorColor: orange.withAlpha(40),
      ),
    );
  }

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: orange,
        brightness: Brightness.light,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF212121),
        elevation: 0,
      ),
    );
  }
}
