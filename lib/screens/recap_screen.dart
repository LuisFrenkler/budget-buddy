import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/db.dart';
import '../services/recap_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/brand.dart';
import '../widgets/buddy_orb.dart';
import '../widgets/recap_story.dart';

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
        })
        ..forward();
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

  static const _gradients = [
    [Color(0xFF7C5CFF), Color(0xFF3B1FB8)],
    [Color(0xFFF472B6), Color(0xFF7C5CFF)],
    [Color(0xFF38BDF8), Color(0xFF5B3DF5)],
    [Color(0xFFFFB020), Color(0xFFF472B6)],
    [Color(0xFF2BD17E), Color(0xFF0E7490)],
    [Color(0xFFFF5D73), Color(0xFF7C5CFF)],
    [Color(0xFF7C5CFF), Color(0xFF16161E)],
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
    // the last card waits for the user
    if (i == _slides.length - 1) {
      _timer.value = 1;
    } else {
      _timer.forward(from: 0);
    }
  }

  void _next() => _go(_i + 1);

  Future<void> _share() async {
    final parts = [
      'Mein $_monthName mit BudgetBuddy:',
      if (r.savingsRate > 0) '💰 ${r.savingsRate} % gespart',
      if (r.topCategory != null) '📊 ${r.topCategoryShare} % für ${r.topCategory}',
      if (r.topMerchant != null && r.topMerchantVisits > 1) '📍 ${r.topMerchantVisits}× bei ${r.topMerchant}',
      'Und dein Monat? 👉 BudgetBuddy',
    ];
    final text = parts.join('\n');
    // the story waits while the share sheet is open
    _timer.stop();
    await showStoryShare(context, r, fallbackText: text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[_i % _gradients.length];
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => d.localPosition.dx < MediaQuery.of(context).size.width / 3 ? _go(_i - 1) : _next(),
        onLongPressStart: (_) => _timer.stop(),
        onLongPressEnd: (_) => _timer.forward(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
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
                Text('Dein $_monthName',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                const Spacer(),
                IconButton(
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
          child: Text(big,
              style: const TextStyle(
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
        kicker: 'Dein Rückblick',
        big: '$_monthName\nin Zahlen.',
        small: '${r.bookings} Buchungen. Mal sehen, was dahintersteckt.',
      );

  Widget _spent() {
    final change = r.expenseChange;
    return _card(
      kicker: 'Ausgegeben hast du',
      big: Money.format(r.expenses),
      small: change == null
          ? null
          : change == 0
              ? 'Genauso viel wie im $_prevName.'
              : change < 0
              ? '${-change} % weniger als im $_prevName. Stark! 💪'
              : '$change % mehr als im $_prevName.',
    );
  }

  Widget _category() => _card(
        top: Icon(Categories.icon(r.topCategory!), color: Colors.white, size: 56),
        kicker: 'Neben Miete & Abos ging am meisten an',
        big: r.topCategory!,
        small: '${Money.format(r.topCategoryCents)}, das sind ${r.topCategoryShare} % deiner Alltagsausgaben.',
      );

  Widget _merchant() => _card(
        top: const Text('📍', style: TextStyle(fontSize: 56)),
        kicker: 'Dein Lieblingsort',
        big: r.topMerchant!,
        small: '${r.topMerchantVisits}-mal warst du da, zusammen ${Money.format(r.topMerchantCents)}.',
      );

  Widget _savings() => r.saved >= 0
      ? _card(
          top: const Text('💰', style: TextStyle(fontSize: 56)),
          kicker: 'Gespart hast du',
          big: '${r.savingsRate} %',
          small: '${Money.format(r.saved)} sind übrig geblieben. ${r.savingsRate >= 20 ? 'Das ist richtig gut.' : 'Jeder Euro zählt.'}',
        )
      : _card(
          top: const Text('🫣', style: TextStyle(fontSize: 56)),
          kicker: 'Dieser Monat war teuer',
          big: '−${Money.format(-r.saved)}',
          small: 'Mehr ausgegeben als eingenommen. Buddy hilft dir, das im nächsten Monat zu drehen.',
        );

  Widget _priciest() => _card(
        top: const Text('🔥', style: TextStyle(fontSize: 56)),
        kicker: 'Dein teuerster Tag',
        big: Dates.long(r.priciestDay!).split(',').first,
        small: 'Am ${Dates.dayMonth(r.priciestDay!)} gingen ${Money.format(r.priciestDayCents)} raus, '
            'Miete und Abos nicht mitgezählt.',
      );

  Widget _outro() => _card(
        top: const BrandMark(size: 72),
        kicker: 'Das war dein',
        big: '$_monthName.',
        small: 'Teil deinen Monat als Story, ohne Beträge, nur Prozente.',
        bottom: Column(children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF16161E),
            ),
            onPressed: _share,
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Als Story teilen', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fertig', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

// Banner on the home screen once a month: "Dein September-Rückblick ist da".
class RecapBanner extends StatelessWidget {
  const RecapBanner({super.key});

  static Box get _settings => Hive.box('settings');

  @override
  Widget build(BuildContext context) {
    // listens itself: as a const child it is not rebuilt with the home screen
    return ValueListenableBuilder<Box>(
      valueListenable: _settings.listenable(),
      builder: (context, _, __) => _banner(context),
    );
  }

  Widget _banner(BuildContext context) {
    final month = RecapService.recapMonth(DateTime.now());
    final key = 'recapSeen_${month.year}_${month.month}';
    if (_settings.get(key) == true) return const SizedBox.shrink();
    final recap = RecapService.build(DB.getTx(), month);
    if (recap == null) return const SizedBox.shrink();
    final name = Dates.months[month.month - 1];

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Material(
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF7C5CFF), Color(0xFFF472B6)]),
          ),
          child: InkWell(
            onTap: () async {
              await _settings.put(key, true);
              if (context.mounted) {
                Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => RecapScreen(recap)));
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
              child: Row(children: [
                const Text('✨', style: TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Dein $name-Rückblick ist da',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('${recap.savingsRate > 0 ? '${recap.savingsRate} % gespart · ' : ''}jetzt ansehen',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Ausblenden',
                  icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.8), size: 20),
                  onPressed: () => _settings.put(key, true),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
