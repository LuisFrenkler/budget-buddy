// colors, theme, categories and badges
import 'package:flutter/material.dart';

// Reactive theme mode. Flip ThemeController.isDark to switch the whole app
// between dark and light; the MaterialApp listens and rebuilds.
class ThemeController {
  static final ValueNotifier<bool> isDark = ValueNotifier(true);
}

class AppColors {
  // brand colors — identical in both modes
  static const primary = Color(0xFF22C55E);
  static const primaryDark = Color(0xFF0E9F6E);
  static const accent = Color(0xFF34E89E);       // bright mint for highlights
  static const accentBlue = Color(0xFF0EA5E9);   // secondary accent (depot)
  static const error = Color(0xFFFF6B70);
  static const warning = Color(0xFFF59E0B);

  // hero gradients (brand, both modes)
  static const heroGreen = [Color(0xFF16D196), Color(0xFF22C55E), Color(0xFF0E9F6E)];
  static const heroBlue = [Color(0xFF0EA5E9), Color(0xFF22C55E)];

  // colors for pie chart
  static const chart = [
    Color(0xFF22C55E), // green
    Color(0xFF0EA5E9), // blue
    Color(0xFFF59E0B), // orange
    Color(0xFFFF6B70), // red
    Color(0xFF6366F1), // indigo
    Color(0xFF8B5CF6), // purple
  ];

  // neutral colors — resolved from the current theme mode
  static bool get _d => ThemeController.isDark.value;
  static Color get bg => _d ? const Color(0xFF0A0E14) : const Color(0xFFF4F6FA);
  static Color get surface => _d ? const Color(0xFF151C26) : const Color(0xFFFFFFFF);
  static Color get surfaceAlt => _d ? const Color(0xFF1B2430) : const Color(0xFFEAEEF4);
  static Color get text => _d ? const Color(0xFFFFFFFF) : const Color(0xFF0A0E14);
  static Color get textDim => _d ? const Color(0xFF8A94A6) : const Color(0xFF647084);
  static Color get border => _d ? const Color(0xFF222C38) : const Color(0xFFE2E8F0);
}

// app theme
class AppTheme {
  static ThemeData theme(bool dark) => ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: AppColors.bg,

    colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
      primary: AppColors.primary,
      surface: AppColors.surface,
      error: AppColors.error,
    ),

    // app bar
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      // large left-aligned titles on every screen
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
    ),
    
    // cards
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    // text fields
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),

    // buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),

    // floating action button
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),

    // floating snackbars above the navigation bar
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceAlt,
      contentTextStyle: TextStyle(color: AppColors.text, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),

    // bottom navigation (custom floating nav is used on the home screen)
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primary.withValues(alpha: 0.15),
      height: 65,
    ),
    
    // smoother, modern page transitions on every platform
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      TargetPlatform.linux: ZoomPageTransitionsBuilder(),
    }),

    useMaterial3: true,
  );
}

// categories for transactions
class Categories {
  // expense categories
  static const expense = [
    {'name': 'Lebensmittel', 'emoji': '🛒'},
    {'name': 'Transport', 'emoji': '🚗'},
    {'name': 'Unterhaltung', 'emoji': '🎬'},
    {'name': 'Wohnen', 'emoji': '🏠'},
    {'name': 'Kleidung', 'emoji': '👕'},
    {'name': 'Gesundheit', 'emoji': '💊'},
    {'name': 'Bildung', 'emoji': '📚'},
    {'name': 'Essen & Trinken', 'emoji': '🍽️'},
    {'name': 'Sonstiges', 'emoji': '📦'},
  ];
  
  // income categories
  static const income = [
    {'name': 'Gehalt', 'emoji': '💼'},
    {'name': 'Nebenjob', 'emoji': '🔧'},
    {'name': 'Investition', 'emoji': '📈'},
    {'name': 'Geschenk', 'emoji': '🎁'},
    {'name': 'Sonstiges', 'emoji': '💰'},
  ];
  
  // maps a category name to a representative icon
  static IconData icon(String c) {
    switch (c) {
      case 'Lebensmittel': return Icons.shopping_cart_rounded;
      case 'Transport': return Icons.directions_car_rounded;
      case 'Unterhaltung': return Icons.movie_rounded;
      case 'Wohnen': return Icons.home_rounded;
      case 'Kleidung': return Icons.checkroom_rounded;
      case 'Gesundheit': return Icons.favorite_rounded;
      case 'Bildung': return Icons.school_rounded;
      case 'Essen & Trinken': return Icons.restaurant_rounded;
      case 'Gehalt': return Icons.work_rounded;
      case 'Nebenjob': return Icons.handyman_rounded;
      case 'Investition': return Icons.trending_up_rounded;
      case 'Geschenk': return Icons.card_giftcard_rounded;
      default: return Icons.category_rounded;
    }
  }

  // all category names (for csv validation)
  static List<String> get all {
    final list = <String>[];
    for (var c in expense) {
      list.add(c['name']!);
    }
    for (var c in income) {
      list.add(c['name']!);
    }
    return list;
  }
}

// asset types for portfolio holdings
class AssetTypes {
  static const list = [
    {'name': 'Aktie', 'emoji': '📈'},
    {'name': 'ETF', 'emoji': '🧺'},
    {'name': 'Krypto', 'emoji': '🪙'},
    {'name': 'Sonstiges', 'emoji': '💎'},
  ];
}

// badges
class Badges {
  static const list = [
    {'id': 'first', 'name': 'Erster Schritt', 'desc': 'Erste Transaktion', 'emoji': '🎯'},
    {'id': 'saver', 'name': 'Sparfuchs', 'desc': '100€ gespart', 'emoji': '💰'},
    {'id': 'master', 'name': 'Datenmeister', 'desc': '50 Transaktionen', 'emoji': '📊'},
    {'id': 'week', 'name': 'Wochentracker', 'desc': '7 Tage getrackt', 'emoji': '📅'},
  ];
}
