// colors, theme, categories and badges
import 'package:flutter/material.dart';

// Reactive theme mode. Flip ThemeController.isDark to switch the whole app
// between dark and light; the MaterialApp listens and rebuilds.
class ThemeController {
  static final ValueNotifier<bool> isDark = ValueNotifier(true);
}

class AppColors {
  // brand: an electric violet for buttons, links, selection and the logo.
  // It never stands for "plus" or "minus"; those have their own colors.
  static const primary = Color(0xFF7C5CFF);
  static const primaryDeep = Color(0xFF5B3DF5);
  static const accentBlue = Color(0xFF38BDF8);   // secondary accent (depot)

  // meaning: money in and gains, money out and losses, attention
  static const positive = Color(0xFF2BD17E);
  static const error = Color(0xFFFF5D73);
  static const warning = Color(0xFFFFB020);

  // the same meaning for small text: on the light background the bright
  // fills are too faint to read (2:1), these reach 4.5:1
  static Color get positiveText => _d ? positive : const Color(0xFF0A7A43);
  static Color get errorText => _d ? error : const Color(0xFFC9283E);
  static Color get warningText => _d ? warning : const Color(0xFF9A5B00);

  // brand gradient for hero areas (onboarding, sign-in)
  static const heroBrand = [Color(0xFFA48BFF), Color(0xFF7C5CFF), Color(0xFF5B3DF5)];

  // categorical colors for charts, brand first
  static const chart = [
    Color(0xFF7C5CFF), // violet
    Color(0xFF38BDF8), // sky
    Color(0xFFFFB020), // amber
    Color(0xFFFF5D73), // rose
    Color(0xFF2BD17E), // green
    Color(0xFFF472B6), // pink
  ];

  // neutral colors, a calm graphite resolved from the current theme mode
  static bool get _d => ThemeController.isDark.value;
  static Color get bg => _d ? const Color(0xFF0B0B10) : const Color(0xFFF6F6F9);
  static Color get surface => _d ? const Color(0xFF16161E) : const Color(0xFFFFFFFF);
  static Color get surfaceAlt => _d ? const Color(0xFF1F1F2A) : const Color(0xFFEDEDF3);
  static Color get text => _d ? const Color(0xFFF7F7FA) : const Color(0xFF0B0B10);
  static Color get textDim => _d ? const Color(0xFF8C8CA1) : const Color(0xFF6A6A7D);
  static Color get border => _d ? const Color(0xFF26263A) : const Color(0xFFE3E3EC);
}

// app theme
class AppTheme {
  static ThemeData theme(bool dark) => ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: AppColors.bg,

    colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primary,
      secondaryContainer: AppColors.surfaceAlt,
      onSecondaryContainer: AppColors.text,
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
      // same type as the in-page titles ("Konto"): an explicit style here
      // does not inherit the theme font, so Inter is named again
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        color: AppColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w800,
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

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),

    // floating action button
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),

    // calm switches without the default outline
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : AppColors.textDim),
      // the off track gets an outline, so the switch reads as one on any card
      trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.primary : AppColors.surfaceAlt),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.transparent : AppColors.textDim.withValues(alpha: 0.5)),
    ),

    // floating snackbars above the navigation bar
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceAlt,
      contentTextStyle: TextStyle(color: AppColors.text, fontSize: 14),
      actionTextColor: AppColors.primary,
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

  // one colour per category, so lists and charts are easy to scan
  static Color color(String c) => switch (c) {
        'Lebensmittel' => const Color(0xFF22C55E),
        'Transport' => const Color(0xFF38BDF8),
        'Unterhaltung' => const Color(0xFFF472B6),
        'Wohnen' => const Color(0xFFF59E0B),
        'Kleidung' => const Color(0xFFA78BFA),
        'Gesundheit' => const Color(0xFFFF5D73),
        'Bildung' => const Color(0xFF6366F1),
        'Essen & Trinken' => const Color(0xFFFB923C),
        'Gehalt' => const Color(0xFF2BD17E),
        'Nebenjob' => const Color(0xFF14B8A6),
        'Investition' => const Color(0xFF38BDF8),
        'Geschenk' => const Color(0xFFF472B6),
        _ => const Color(0xFF94A3B8),
      };

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
