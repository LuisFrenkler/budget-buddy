import 'package:flutter/material.dart';
import '../services/demo_data.dart';
import '../utils/theme.dart';

// Three-slide intro shown once on the first launch.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinish;
  const OnboardingScreen({super.key, required this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _Slide(
      icon: Icons.account_balance_wallet,
      gradient: AppColors.heroGreen,
      title: 'Behalte deine Finanzen im Griff',
      text: 'Erfasse Einnahmen und Ausgaben in Sekunden – übersichtlich und auf Deutsch.',
    ),
    _Slide(
      icon: Icons.pie_chart,
      gradient: AppColors.heroGreen,
      title: 'Verstehe, wohin dein Geld fließt',
      text: 'Budgets, Statistiken und ein klarer Monatsüberblick mit Diagrammen.',
    ),
    _Slide(
      icon: Icons.trending_up,
      gradient: AppColors.heroBlue,
      title: 'Lass dein Geld wachsen',
      text: 'Verfolge dein Depot und automatisiere wiederkehrende Buchungen.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _pages.length - 1;

  bool _loadingDemo = false;

  // fills the app with sample data, then enters it
  Future<void> _startWithDemo() async {
    setState(() => _loadingDemo = true);
    await DemoData.load();
    widget.onFinish();
  }

  void _next() {
    if (_isLast) {
      widget.onFinish();
    } else {
      _controller.nextPage(
          duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // skip button
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: widget.onFinish,
                  child: Text('Überspringen', style: TextStyle(color: AppColors.textDim)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _pages[i],
              ),
            ),
            // dots indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? AppColors.primary : AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loadingDemo ? null : _next,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: Text(_isLast ? 'Los geht\'s' : 'Weiter'),
                ),
              ),
            ),
            // try the app with sample data instead of starting empty
            SizedBox(
              height: 48,
              child: AnimatedOpacity(
                opacity: _isLast ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: TextButton(
                  onPressed: _isLast && !_loadingDemo ? _startWithDemo : null,
                  child: Text(_loadingDemo ? 'Wird geladen …' : 'Mit Beispieldaten starten'),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  final IconData icon;
  final List<Color> gradient;
  final String title;
  final String text;
  const _Slide({required this.icon, required this.gradient, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Icon(icon, size: 64, color: Colors.white),
          ),
          const SizedBox(height: 40),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.textDim, height: 1.5)),
        ],
      ),
    );
  }
}
