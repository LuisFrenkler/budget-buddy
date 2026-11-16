// Text colors reach WCAG AA (4.5:1) on every background they sit on, in the
// light and the dark theme. Large display numbers (glow) need 3:1.
import 'package:budget_buddy/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _ratio(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

void main() {
  for (final dark in [false, true]) {
    test('contrast in the ${dark ? 'dark' : 'light'} theme', () {
      ThemeController.isDark.value = dark;
      final backgrounds = {'bg': AppColors.bg, 'surface': AppColors.surface, 'surfaceAlt': AppColors.surfaceAlt};
      final texts = {
        'text': AppColors.text,
        'textDim': AppColors.textDim,
        'positiveText': AppColors.positiveText,
        'errorText': AppColors.errorText,
        'warningText': AppColors.warningText,
        'brandText': AppColors.brandText,
      };
      for (final t in texts.entries) {
        for (final b in backgrounds.entries) {
          expect(_ratio(t.value, b.value), greaterThanOrEqualTo(4.5), reason: '${t.key} on ${b.key}');
        }
      }
      for (final b in backgrounds.entries) {
        expect(_ratio(AppColors.glow, b.value), greaterThanOrEqualTo(3), reason: 'glow on ${b.key}');
      }
      // text on the copper and on the primary button
      expect(_ratio(Colors.white, AppColors.brand), greaterThanOrEqualTo(4.5));
      expect(_ratio(AppColors.onPrimary, AppColors.primary), greaterThanOrEqualTo(4.5));
    });
  }
}
