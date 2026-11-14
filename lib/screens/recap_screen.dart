import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/recap_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/brand.dart';
import '../widgets/buddy_orb.dart';
import '../widgets/recap_story.dart';
import '../l10n/l10n.dart';

// The month as a story: a few full-screen cards that turn by themselves,
// tap right for the next, left for the previous, and a share at the end.
class RecapScreen extends StatefulWidget {
  final MonthRecap recap;
  const RecapScreen(this.recap, {super.key});

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> with SingleTickerProviderStateMixin {
  static const _seconds = 5;
  late final AnimationController _timer =
      AnimationController(vsync: this, duration: const Duration(seconds: _seconds))
        ..addStatusListener((s) {
          // the last card waits for the user instead of closing itself
          if (s == AnimationStatus.completed && _i < _slides.length - 1) _next();
        });

  // with a screen reader or reduced motion the cards wait for the user
  bool _auto = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _auto = !media.accessibleNavigation && !media.disableAnimations;
    if (_auto && !_timer.isAnimating && _timer.value == 0) _timer.forward();
  }
  int _i = 0;

  MonthRecap get r => widget.recap;
  String get _monthName => Dates.months[r.month.month - 1];
  String get _prevName => Dates.months[(r.month.month + 10) % 12];

  late final List<Widget Function()> _slides = [
    _intro,
    _spent,
    if (r.topCategory != null) _category,
    if (r.topMerchant != null && r.topMerchantVisits > 1) _merchant,
    _savings,
    if (r.priciestDay != null) _priciest,
    _outro,
  ];

  // one calm, dark tone per page, white text stays readable on all
  static const _tones = [
    Color(0xFF7A3F1C),
    Color(0xFF1E3A5F),
    Color(0xFF0E5E6F),
    Color(0xFF2E2A5C),
    Color(0xFF1F5132),
    Color(0xFF5A1E3A),
    Color(0xFF1C1815),
  ];

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i < 0) return;
    if (i >= _slides.length) {
      Navigator.pop(context);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _i = i);
    // the last card waits for the user; without auto-advance the bar just fills
    if (i == _slides.length - 1 || !_auto) {
      _timer.value = 1;
    } else {
      _timer.forward(from: 0);
    }
  }

  void _next() => _go(_i + 1);

  Future<void> _share() async {
    final parts = [
      tr('Mein {monthName} mit Ahead:', {'monthName': _monthName}),
      if (r.savingsRate > 0) '${r.savingsRate} % gespart',
      if (r.topCategory != null) tr('{x} % für {topCategory}', {'x': r.topCategoryShare, 'topCategory': r.topCategory}),
      if (r.topMerchant != null && r.topMerchantVisits > 1) '${r.topMerchantVisits}× bei ${r.topMerchant}',
    ];
    final text = parts.join('\n');
    // the story waits while the share sheet is open
    _timer.stop();
    await showStoryShare(context, r, fallbackText: text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => d.localPosition.dx < MediaQuery.of(context).size.width / 3 ? _go(_i - 1) : _next(),
        onLongPressStart: (_) => _timer.stop(),
        onLongPressEnd: (_) => _timer.forward(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          color: _tones[_i % _tones.length],
          child: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: AnimatedBuilder(
                  animation: _timer,
                  builder: (_, __) => Row(children: [
                    for (int k = 0; k < _slides.length; k++)
                      Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: k < _i ? 1 : (k == _i ? _timer.value : 0),
                            child: Container(
                              decoration:
                                  BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
              Row(children: [
                const SizedBox(width: 16),
                const BrandMark(size: 24),
                const SizedBox(width: 8),
                Text(tr('Dein {monthName}', {'monthName': _monthName}),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                const Spacer(),
                if (!_auto) ...[
                  // without the timer: explicit buttons instead of invisible tap zones
                  IconButton(
                    tooltip: tr('Zurück'),
                    icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                    onPressed: _i > 0 ? () => _go(_i - 1) : null,
                  ),
                  IconButton(
                    tooltip: tr('Weiter'),
                    icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
                    onPressed: _next,
                  ),
                ],
                IconButton(
                  tooltip: tr('Schließen'),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
                  ),
                  child: KeyedSubtree(key: ValueKey(_i), child: _slides[_i]()),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // --- the cards ---

  Widget _card({String? kicker, required String big, String? small, Widget? top, Widget? bottom}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        if (top != null) ...[top, const SizedBox(height: 28)],
        if (kicker != null)
          Text(kicker,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 24, end: 0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
          // long merchant names or large system text shrink instead of overflowing
          child: Text(big,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: AppFonts.display, 
                  color: Colors.white, fontSize: 46, fontWeight: FontWeight.w800, letterSpacing: -1.6, height: 1.05)),
        ),
        if (small != null) ...[
          const SizedBox(height: 16),
          Text(small, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 18, height: 1.4)),
        ],
        if (bottom != null) ...[const SizedBox(height: 32), bottom],
      ]),
    );
  }

  Widget _intro() => _card(
        top: const BuddyOrb(size: 96),
        kicker: tr('Dein Rückblick'),
        big: tr('{monthName}\nin Zahlen.', {'monthName': _monthName}),
        small: tr('{bookings} Buchungen. Mal sehen, was dahintersteckt.', {'bookings': r.bookings}),
      );

  Widget _spent() {
    final change = r.expenseChange;
    return _card(
      kicker: tr('Ausgegeben hast du'),
      big: Money.format(r.expenses),
      small: change == null
          ? null
          : change == 0
              ? tr('Genauso viel wie im {prevName}.', {'prevName': _prevName})
              : change < 0
              ? tr('{x} % weniger als im {prevName}.', {'x': -change, 'prevName': _prevName})
              : tr('{change} % mehr als im {prevName}.', {'change': change, 'prevName': _prevName}),
    );
  }

  Widget _category() => _card(
        top: Icon(Categories.icon(r.topCategory!), color: Colors.white, size: 56),
        kicker: tr('Neben Miete & Abos ging am meisten an'),
        big: r.topCategory!,
        small: tr('{x}, das sind {x2} % deiner Alltagsausgaben.', {'x': Money.format(r.topCategoryCents), 'x2': r.topCategoryShare}),
      );

  Widget _merchant() => _card(
        top: const Icon(Icons.place_outlined, color: Colors.white, size: 56),
        kicker: tr('Dein Lieblingsort'),
        big: r.topMerchant!,
        small: tr('{x}-mal warst du da, zusammen {x2}.', {'x': r.topMerchantVisits, 'x2': Money.format(r.topMerchantCents)}),
      );

  Widget _savings() => r.saved >= 0
      ? _card(
          top: const Icon(Icons.savings_outlined, color: Colors.white, size: 56),
          kicker: tr('Gespart hast du'),
          big: '${r.savingsRate} %',
          small: tr('{x} sind übrig geblieben.', {'x': Money.format(r.saved)}),
        )
      : _card(
          top: const Icon(Icons.trending_down_rounded, color: Colors.white, size: 56),
          kicker: tr('Dieser Monat war teuer'),
          big: '−${Money.format(-r.saved)}',
          small: tr('Mehr ausgegeben als eingenommen.'),
        );

  Widget _priciest() => _card(
        top: const Icon(Icons.calendar_today_outlined, color: Colors.white, size: 56),
        kicker: tr('Dein teuerster Tag'),
        big: Dates.long(r.priciestDay!).split(',').first,
        small: tr('Am {x} gingen {x2} raus, Miete und Abos nicht mitgezählt.', {'x': Dates.dayMonth(r.priciestDay!), 'x2': Money.format(r.priciestDayCents)}),
      );

  Widget _outro() => _card(
        top: const BrandMark(size: 72),
        kicker: tr('Das war dein'),
        big: '$_monthName.',
        small: tr('Teil deinen Monat als Story, ohne Beträge, nur Prozente.'),
        bottom: Column(children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1C1815),
            ),
            onPressed: _share,
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(tr('Als Story teilen'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Fertig'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

