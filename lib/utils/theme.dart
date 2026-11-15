// colors, theme, categories and badges
import 'package:flutter/material.dart';

// Reactive theme mode. Flip ThemeController.isDark to switch the whole app
// between dark and light; the MaterialApp listens and rebuilds.
class ThemeController {
  static final ValueNotifier<bool> isDark = ValueNotifier(true);
}

// Headlines and big numbers: Bricolage Grotesque, as on the landing page.
// Running text and controls stay Inter.
class AppFonts {
  static const display = 'Bricolage';
}

class AppColors {
  // brand: a deep copper, like the coin ring in the logo. Used sparingly:
  // logo, Buddy, the add button, shared stories. White text on it passes 4.5:1.
  static const brand = Color(0xFFB06030);
  static const brandDeep = Color(0xFF8A4520);

  // everything else that is "active" (buttons, selection, links, switches) is
  // neutral ink: white in dark mode, near-black in light mode; onPrimary is
  // the text on it. Plus and minus have their own colors.
  static Color get primary => text;
  static Color get onPrimary => bg;

  // meaning: money in and gains, money out and losses, attention
  static const positive = Color(0xFF2BD17E);
  static const error = Color(0xFFFF5D73);
  static const warning = Color(0xFFF2C230);

  // the same meaning for small text: on the light background the bright
  // fills are too faint to read (2:1), these reach 4.5:1
  static Color get positiveText => _d ? const Color(0xFF7BE0AD) : const Color(0xFF0A6B3C);
  static Color get errorText => _d ? error : const Color(0xFFC9283E);
  static Color get warningText => _d ? warning : const Color(0xFF7A6200);
  static Color get primaryText => text;
  // copper for small text (labels, numbered steps): the brand fill itself
  // reaches only 4:1 on the backgrounds, these reach 5:1 or more
  static Color get brandText => _d ? const Color(0xFFE0915C) : const Color(0xFF9A5028);

  // categorical colors for charts, brand first
  static const chart = [
    brand, // copper
    Color(0xFF38BDF8), // sky
    Color(0xFFF2C230), // yellow
    Color(0xFFFF5D73), // rose
    Color(0xFF2BD17E), // green
    Color(0xFFF472B6), // pink
  ];

  // two moods of one brand: "Glow" in light mode (warm paper, a peach glow)
  // and "Night" in dark mode (near black, copper glowing from above, glass)
  static bool get _d => ThemeController.isDark.value;
  static Color get bg => _d ? const Color(0xFF0C0A09) : const Color(0xFFFBF7F3);
  static Color get surface => _d ? const Color(0xFF181412) : const Color(0xFFFFFFFF);
  static Color get surfaceAlt => _d ? const Color(0xFF231E1A) : const Color(0xFFF3ECE6);
  static Color get text => _d ? const Color(0xFFF5EFEA) : const Color(0xFF17120E);
  static Color get textDim => _d ? const Color(0xFFA79C93) : const Color(0xFF6B625B);
  static Color get border => _d ? const Color(0xFF2C2522) : const Color(0xFFEFE8E2);

  // the warm highlight: big numbers, Buddy's emphasis, the glow
  static Color get glow => _d ? const Color(0xFFF4C7A1) : const Color(0xFFA4542A);
  static const peach = Color(0xFFF4C7A1);
  // hairline on glass cards in Night, a soft line in Glow
  static Color get hairline => _d ? const Color(0x1CFFFFFF) : const Color(0xFFEFE8E2);
}

// app theme
class AppTheme {
  static ThemeData theme(bool dark) => ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: AppColors.bg,

    colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
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
        fontFamily: AppFonts.display,
        color: AppColors.text,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
    ),
    
    // cards
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22), side: BorderSide(color: AppColors.hairline)),
    ),

    // text fields
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      // placeholders are light grey, never the color of typed text
      hintStyle: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w400),
      labelStyle: TextStyle(color: AppColors.textDim),
      floatingLabelStyle: TextStyle(color: AppColors.textDim),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.textDim, width: 1),
      ),
    ),

    // buttons
    // the main action is an ink pill (cream in Night); copper is kept for
    // Buddy himself: his orb, the send button, the next-step stamp
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.surfaceAlt,
        disabledForegroundColor: AppColors.textDim,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryText,
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.primary),

    // floating action button
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.brand,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),

    // calm switches without the default outline
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.onPrimary : AppColors.textDim),
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

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      modalBackgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      showDragHandle: true,
      dragHandleColor: AppColors.border,
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
    {'name': transfer, 'emoji': '🔁'},
  ];
  
  // income categories
  static const income = [
    {'name': 'Gehalt', 'emoji': '💼'},
    {'name': 'Nebenjob', 'emoji': '🔧'},
    {'name': 'Investition', 'emoji': '📈'},
    {'name': 'Geschenk', 'emoji': '🎁'},
    {'name': 'Sonstiges', 'emoji': '💰'},
    {'name': transfer, 'emoji': '🔁'},
  ];

  // money moved between the user's own accounts (savings, depot): it leaves
  // the Kontostand but is neither spending nor income
  static const transfer = 'Umbuchung';

  static bool counts(String category) => category != transfer;

  // a spending category with no income counterpart (not "Sonstiges"): money
  // coming in under it is a refund for something bought there
  static bool isExpenseOnly(String category) =>
      expense.any((c) => c['name'] == category) && !income.any((c) => c['name'] == category);
  
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
      case transfer: return Icons.swap_horiz_rounded;
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
