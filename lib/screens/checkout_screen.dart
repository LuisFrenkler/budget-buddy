import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/account_service.dart';
import '../services/backend_service.dart';
import '../services/plus_service.dart';
import '../services/store_purchases.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';
import '../legal/legal_texts.dart';
import 'about_screen.dart';
import 'auth_screens.dart';

// Checkout for Plus: what it costs and when, the payment method, a promo
// code, then a welcome page. Returns true when Plus was started.
//
// Signed in with the server reachable, payment happens on the server's
// payment page (Stripe Checkout): the app opens it, waits until the server
// confirms Plus and never touches card or bank details. Otherwise the local
// test mode below runs and charges nothing.
Future<bool> showCheckout(BuildContext context, PlusPlan plan) async {
  final ok = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => PaymentScreen(plan: plan)),
  );
  return ok == true;
}

// The same page without the price part, to change the payment method later.
Future<bool> changePaymentMethod(BuildContext context) async {
  final ok = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => const PaymentScreen()),
  );
  return ok == true;
}

// What the platform offers: the stores take care of payment in the apps,
// the web checkout offers the usual methods.
List<PayMethod> availableMethods() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) return [PayMethod.appStore];
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return [PayMethod.googlePlay];
  final apple = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;
  return [
    apple ? PayMethod.applePay : PayMethod.googlePay,
    PayMethod.paypal,
    PayMethod.card,
    PayMethod.sepa,
    PayMethod.klarna,
    apple ? PayMethod.googlePay : PayMethod.applePay,
  ];
}

class PaymentScreen extends StatefulWidget {
  final PlusPlan? plan; // null: only change the payment method
  const PaymentScreen({super.key, this.plan});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late PlusPlan? _plan = widget.plan;
  late final List<PayMethod> _methods = availableMethods();
  late PayMethod _method = PlusService.subscription.value?.method ?? _methods.first;

  final _cardNumber = TextEditingController();
  final _expiry = TextEditingController();
  final _cvc = TextEditingController();
  final _holder = TextEditingController();
  final _iban = TextEditingController();
  final _paypal = TextEditingController(text: AccountService.current.value?.email ?? '');
  final _promo = TextEditingController();

  bool _mandate = false;
  bool _showErrors = false;
  bool _promoOpen = false;
  String? _promoApplied;
  String? _promoError;
  bool _busy = false;

  // 'live' or 'demo' when the purchase runs on the server, null for the local test mode
  String? _billing;
  // the server's payment page is open and we wait for the confirmation
  String? _payUrl;
  Timer? _poll;

  bool get _checkout => widget.plan != null;
  // in the iPhone and Android app Plus is bought through the store
  bool get _inStore => _checkout && StorePurchases.supported;
  bool get _server => _checkout && !_inStore && _billing != null;
  // the server is being asked whether it takes payments
  bool _asking = false;
  // the local test form exists for development only: a release never unlocks
  // Plus for free or asks for card details it can't use
  bool get _blocked => _checkout && !_inStore && !_server && kReleaseMode;

  @override
  void initState() {
    super.initState();
    if (!_methods.contains(_method)) _method = _methods.first;
    _holder.text = AccountService.current.value?.name ?? '';
    if (_inStore) {
      // the store's own prices replace ours once they are loaded
      StorePurchases.loadProducts().then((_) {
        if (mounted) setState(() {});
      });
    } else if (_checkout && AccountService.token != null) {
      _asking = true;
      _askServer();
    }
  }

  Future<void> _askServer() async {
    final health = await BackendService.health();
    if (!mounted) return;
    setState(() {
      _asking = false;
      if (health?['billing'] != null) _billing = '${health!['billing']}';
    });
  }

  // a release on the web without a reachable server: say what is missing
  Widget _unavailable() {
    final signedIn = AccountService.token != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(signedIn ? Icons.cloud_off_rounded : Icons.person_outline_rounded, size: 48, color: AppColors.textDim),
          const SizedBox(height: 16),
          Text(signedIn ? 'Gerade nicht erreichbar' : 'Erst ein Konto',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
              signedIn
                  ? 'Die Zahlung läuft über unseren Server, der gerade nicht antwortet. Versuch es gleich noch einmal.'
                  : 'Plus gehört zu deinem Konto, damit du es auf jedem Gerät behältst und jederzeit kündigen kannst.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, height: 1.4)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: signedIn
                ? () {
                    setState(() => _asking = true);
                    _askServer();
                  }
                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
            child: Text(signedIn ? 'Erneut versuchen' : 'Konto erstellen'),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final c in [_cardNumber, _expiry, _cvc, _holder, _iban, _paypal, _promo]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _extraDays => _promoApplied == null ? 0 : PlusService.promoDays(_promoApplied!) ?? 0;

  DateTime get _trialEnd => DateTime.now().add(Duration(days: PlusService.trialDays + _extraDays));

  // per field: the error text, or null when the input is fine
  String? get _cardNumberError => PaymentChecks.cardNumber(_cardNumber.text) ? null : 'Kartennummer prüfen';
  String? get _expiryError => PaymentChecks.expiry(_expiry.text) ? null : 'MM/JJ';
  String? get _cvcError => PaymentChecks.cvc(_cvc.text) ? null : '3–4 Ziffern';
  String? get _holderError => _holder.text.trim().length < 3 ? 'Name des Kontoinhabers' : null;
  String? get _ibanError => PaymentChecks.iban(_iban.text) ? null : 'Diese IBAN stimmt nicht';
  String? get _paypalError => PaymentChecks.email(_paypal.text) ? null : 'E-Mail deines PayPal-Kontos';

  bool get _valid => switch (_method) {
        PayMethod.card => _cardNumberError == null && _expiryError == null && _cvcError == null,
        PayMethod.sepa => _holderError == null && _ibanError == null && _mandate,
        PayMethod.paypal => _paypalError == null,
        _ => true,
      };

  // what is shown later as the payment method
  String get _detail => switch (_method) {
        PayMethod.card =>
          '${PaymentChecks.cardBrand(_cardNumber.text)} •••• ${PaymentChecks.digits(_cardNumber.text).substring(PaymentChecks.digits(_cardNumber.text).length - 4)}',
        PayMethod.sepa => 'Lastschrift ${PaymentChecks.maskIban(_iban.text)}',
        PayMethod.paypal => 'PayPal · ${_paypal.text.trim()}',
        _ => '',
      };

  void _applyPromo() {
    final code = _promo.text.trim().toUpperCase();
    if (PlusService.promoDays(code) == null) {
      setState(() => _promoError = 'Diesen Code kennen wir nicht');
      return;
    }
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    setState(() {
      _promoApplied = code;
      _promoError = null;
    });
  }

  Future<void> _submit() async {
    if (_inStore) return _buyInStore();
    if (_server) return _payOnServer();
    if (!_valid) {
      HapticFeedback.heavyImpact();
      setState(() => _showErrors = true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    // a moment for the "secure connection" feel; nothing is charged in test mode
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    if (_checkout) {
      final sub = await PlusService.start(
          plan: _plan!, method: _method, methodDetail: _detail, extraDays: _extraDays);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      await Navigator.push(context, PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, a, __) => FadeTransition(opacity: a, child: _Welcome(sub: sub)),
      ));
    } else {
      await PlusService.changeMethod(_method, _detail);
      HapticFeedback.mediumImpact();
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _payOnServer() async {
    setState(() => _busy = true);
    try {
      final url = await BackendService.plusCheckout(_plan == PlusPlan.yearly ? 'yearly' : 'monthly',
          promo: _promoApplied);
      if (!mounted) return;
      setState(() => _payUrl = url);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _poll?.cancel();
      final started = DateTime.now();
      _poll = Timer.periodic(const Duration(seconds: 2), (timer) async {
        if (_payUrl == null || DateTime.now().difference(started).inMinutes >= 15) {
          timer.cancel();
          if (mounted) setState(() => _payUrl = null);
          return;
        }
        try {
          final plus = await BackendService.plusStatus();
          if (plus == null) return;
          timer.cancel();
          await PlusService.applyServer(plus);
          await _welcome(PlusService.subscription.value!);
        } catch (_) {
          // a hiccup while polling; the next tick tries again
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(duration: const Duration(milliseconds: 3500), content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // the store's purchase sheet; Plus comes once the server has confirmed it
  Future<void> _buyInStore() async {
    setState(() => _busy = true);
    try {
      final result = await StorePurchases.buy(_plan!);
      if (!mounted) return;
      setState(() => _busy = false);
      switch (result) {
        case StoreResult.done:
          return _welcome(PlusService.subscription.value!);
        case StoreResult.pending:
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              duration: Duration(milliseconds: 4500),
              content: Text('Der Kauf wartet noch auf eine Bestätigung. Plus kommt, sobald sie da ist.')));
        case StoreResult.cancelled:
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(duration: const Duration(milliseconds: 4500), content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _welcome(Subscription sub) async {
    HapticFeedback.heavyImpact();
    if (!mounted) return;
    setState(() => _payUrl = null);
    await Navigator.push(context, PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, a, __) => FadeTransition(opacity: a, child: _Welcome(sub: sub)),
    ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final title = Text(_checkout ? 'Plus starten' : 'Zahlungsmethode');
    // no test form flashing up while the server is asked
    if (_asking) {
      return Scaffold(appBar: AppBar(title: title), body: const Center(child: CircularProgressIndicator()));
    }
    if (_blocked) return Scaffold(appBar: AppBar(title: title), body: _unavailable());
    return Scaffold(
      appBar: AppBar(title: title),
      body: Stack(children: [
        Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                if (_inStore)
                  const SizedBox.shrink()
                else if (!_server)
                  _testModeBanner()
                else if (_billing == 'demo')
                  _demoBanner(),
                if (_checkout) ...[
                  const SizedBox(height: 16),
                  _planSwitch(),
                  const SizedBox(height: 16),
                  _timeline(),
                ],
                if (_server)
                  _serverMethods()
                else ...[
                  _label(_methods.length == 1 ? 'Bezahlt wird über' : 'Wie möchtest du zahlen?'),
                  for (final m in _methods) _methodTile(m),
                  if (_inStore) _storeNote(),
                ],
                // in the stores codes are redeemed there (Apple offer codes, Google promo codes)
                if (_checkout && !_inStore) ...[if (_server) const SizedBox(height: 8), _promoSection()],
              ],
            ),
          ),
          _bottomBar(),
        ]),
        if (_busy) _processing(),
        if (_payUrl != null) _waiting(),
      ]),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10, left: 4),
        child: Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold)),
      );

  Widget _testModeBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Icon(Icons.science_rounded, color: AppColors.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Testmodus: Es wird nichts abgebucht und nichts an einen Zahlungsanbieter gesendet.',
                style: TextStyle(fontSize: 12.5, color: AppColors.text)),
          ),
        ]),
      );

  // the trial only once per store account; the store shows the exact terms
  Widget _storeNote() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
        child: _note(
          Icons.info_outline_rounded,
          'Den Gratis-Zeitraum gibt es einmal pro '
          '${StorePurchases.platform == 'apple' ? 'Apple-ID' : 'Google-Konto'}. '
          'Die genauen Bedingungen zeigt dir der ${StorePurchases.storeName} vor dem Kauf.',
        ),
      );

  Widget _demoBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Icon(Icons.science_rounded, color: AppColors.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Demo-Zahlung über den Server: Es wird nichts abgebucht.',
                style: TextStyle(fontSize: 12.5, color: AppColors.text)),
          ),
        ]),
      );

  // with the server the method is picked on the payment page itself
  Widget _serverMethods() {
    final shown = availableMethods().where((m) => m != PayMethod.appStore && m != PayMethod.googlePlay).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('So kannst du zahlen'),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in shown) SizedBox(height: 28, child: FittedBox(child: MethodLogo(m))),
          ]),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lock_rounded, size: 16, color: AppColors.positive),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Du wählst im nächsten Schritt auf der sicheren Zahlungsseite von Stripe. '
                'BudgetBuddy sieht deine Karten- und Kontodaten nie.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.4),
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }

  Widget _waiting() => Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.6),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const BuddyOrb(size: 56, active: true),
              const SizedBox(height: 16),
              const Text('Zahlung im neuen Fenster abschließen',
                  textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Text('Sobald sie bestätigt ist, geht es hier von selbst weiter.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      _poll?.cancel();
                      setState(() => _payUrl = null);
                    },
                    child: const Text('Abbrechen'),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: () => launchUrl(Uri.parse(_payUrl!), mode: LaunchMode.externalApplication),
                    child: const Text('Erneut öffnen'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      );

  Widget _planSwitch() {
    Widget option(PlusPlan p) {
      final selected = _plan == p;
      final yearly = p == PlusPlan.yearly;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _plan = p);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(yearly ? 'Jährlich' : 'Monatlich', style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (yearly)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.positive, borderRadius: BorderRadius.circular(999)),
                    child: const Text('−33 %',
                        style: TextStyle(color: Colors.black, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(PlusService.price(p),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(yearly ? 'im Jahr · ${PlusService.yearlyPerMonth}/Monat' : 'im Monat',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ]),
          ),
        ),
      );
    }

    return Row(children: [option(PlusPlan.yearly), const SizedBox(width: 10), option(PlusPlan.monthly)]);
  }

  // when what happens: builds trust that nothing is charged by surprise
  Widget _timeline() {
    final price = '${PlusService.price(_plan!)} ${_plan == PlusPlan.yearly ? 'im Jahr' : 'im Monat'}';
    final lastFree = _trialEnd.subtract(const Duration(days: 1));
    Widget step(IconData icon, Color color, String when, String what, {bool last = false}) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: color),
              ),
              if (!last) Expanded(child: Container(width: 2, color: AppColors.border)),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : 16, top: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(when, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(what, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ]),
              ),
            ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
      // the store said the free week was used already: paid from today
      child: _inStore && StorePurchases.trial[_plan] == false
          ? Column(children: [
              Row(children: [
                const Text('Heute fällig', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(PlusService.price(_plan!), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
              Divider(height: 24, color: AppColors.border),
              step(Icons.lock_open_rounded, AppColors.positive, 'Heute',
                  'Alles von Plus ist sofort freigeschaltet. Den Gratis-Test hattest du schon.'),
              step(Icons.autorenew_rounded, AppColors.textDim, 'Danach', '$price, bis du kündigst', last: true),
            ])
          : Column(children: [
        Row(children: [
          const Text('Heute fällig', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(Money.raw(0), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
        Divider(height: 24, color: AppColors.border),
        step(Icons.lock_open_rounded, AppColors.positive, 'Heute',
            'Alles von Plus ist sofort freigeschaltet.'),
        step(Icons.event_available_rounded, AppColors.primary, 'Bis ${Dates.dayMonth(lastFree)}',
            'Gratis testen. Kündigst du vorher, zahlst du nichts.'),
        step(Icons.payments_rounded, AppColors.textDim, 'Ab ${Dates.full(_trialEnd)}', price, last: true),
        if (_promoApplied != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: AppColors.positive.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.redeem_rounded, color: AppColors.positive, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$_promoApplied: $_extraDays Tage extra gratis',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _methodTile(PayMethod m) {
    final selected = _method == m;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Column(children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _method = m;
                _showErrors = false;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                MethodLogo(m),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(_hint(m), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                  ]),
                ),
                Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: selected ? AppColors.primary : AppColors.textDim),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: selected ? _form(m) : const SizedBox(width: double.infinity),
          ),
        ]),
      ),
    );
  }

  String _hint(PayMethod m) => switch (m) {
        PayMethod.appStore => 'Mit deiner Apple-ID, kündbar in den Einstellungen',
        PayMethod.googlePlay => 'Mit deinem Google-Konto, kündbar im Play Store',
        PayMethod.applePay => 'Mit Face ID oder Touch ID bestätigen',
        PayMethod.googlePay => 'Mit deinem Google-Konto bestätigen',
        PayMethod.paypal => 'Schnell und mit Käuferschutz',
        PayMethod.card => 'Visa, Mastercard, American Express',
        PayMethod.sepa => 'Bequem vom Girokonto',
        PayMethod.klarna => 'Später bezahlen, 30 Tage Zahlungsziel',
      };

  Widget _form(PayMethod m) {
    final fields = switch (m) {
      PayMethod.card => [
          _field(_cardNumber, 'Kartennummer', '1234 5678 9012 3456',
              error: _cardNumberError,
              keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(19), _GroupFormatter(4)],
              suffix: _cardNumber.text.length >= 2
                  ? Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(PaymentChecks.cardBrand(_cardNumber.text),
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                    )
                  : null),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: _field(_expiry, 'Gültig bis', 'MM/JJ',
                  error: _expiryError,
                  keyboard: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4), _ExpiryFormatter()]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(_cvc, 'Prüfnummer', 'CVC',
                  error: _cvcError,
                  keyboard: TextInputType.number,
                  obscure: true,
                  formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)]),
            ),
          ]),
        ],
      PayMethod.sepa => [
          _field(_holder, 'Kontoinhaber', 'Vor- und Nachname', error: _holderError, keyboard: TextInputType.name),
          const SizedBox(height: 10),
          _field(_iban, 'IBAN', 'DE00 0000 0000 0000 0000 00',
              error: _ibanError,
              formatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(34),
                _GroupFormatter(4, upper: true),
              ]),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => setState(() => _mandate = !_mandate),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(value: _mandate, onChanged: (v) => setState(() => _mandate = v == true)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Ich ermächtige BudgetBuddy, Zahlungen von meinem Konto per Lastschrift einzuziehen '
                    '(SEPA-Lastschriftmandat). Ich kann innerhalb von acht Wochen die Erstattung verlangen.',
                    style: TextStyle(
                        fontSize: 12,
                        color: _showErrors && !_mandate ? AppColors.errorText : AppColors.textDim),
                  ),
                ),
              ),
            ]),
          ),
        ],
      PayMethod.paypal => [
          _field(_paypal, 'PayPal-E-Mail', 'du@beispiel.de', error: _paypalError, keyboard: TextInputType.emailAddress),
          const SizedBox(height: 8),
          _note(Icons.open_in_new_rounded, 'Zum Bestätigen wirst du kurz zu PayPal weitergeleitet.'),
        ],
      PayMethod.klarna => [
          _note(Icons.schedule_rounded, 'Klarna schickt dir nach dem Test eine Rechnung. Du hast 30 Tage Zeit.'),
        ],
      PayMethod.applePay || PayMethod.googlePay => [
          _note(Icons.fingerprint_rounded, 'Beim Start fragt dein Gerät nach der Bestätigung. Keine Kartendaten nötig.'),
        ],
      PayMethod.appStore || PayMethod.googlePlay => [
          _note(Icons.verified_user_rounded, 'Abrechnung, Kündigung und Erstattung laufen über den Store.'),
        ],
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: fields),
    );
  }

  Widget _note(IconData icon, String text) => Row(children: [
        Icon(icon, size: 16, color: AppColors.textDim),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 12.5))),
      ]);

  Widget _field(TextEditingController c, String label, String hint,
      {String? error,
      TextInputType? keyboard,
      List<TextInputFormatter>? formatters,
      Widget? suffix,
      bool obscure = false}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      inputFormatters: formatters,
      obscureText: obscure,
      autocorrect: false,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: _showErrors ? error : null,
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }

  Widget _promoSection() {
    if (_promoApplied != null) return const SizedBox.shrink();
    if (!_promoOpen) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _promoOpen = true),
          icon: const Icon(Icons.redeem_rounded, size: 18),
          label: const Text('Gutscheincode einlösen'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: _promo,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _applyPromo(),
            decoration: InputDecoration(labelText: 'Gutscheincode', errorText: _promoError),
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            onPressed: _applyPromo,
            child: const Text('Einlösen'),
          ),
        ),
      ]),
    );
  }

  Widget _bottomBar() {
    final label = !_checkout
        ? 'Zahlungsmethode speichern'
        : _inStore
            ? 'Weiter mit ${StorePurchases.storeName}'
            : _server
            ? 'Weiter zur Zahlung'
            : switch (_method) {
            PayMethod.applePay => 'Mit Apple Pay gratis starten',
            PayMethod.googlePay => 'Mit Google Pay gratis starten',
            PayMethod.paypal => 'Weiter mit PayPal',
            _ => '${PlusService.trialDays + _extraDays} Tage gratis starten',
          };
    // Apple's rule: a white Apple Pay button on dark backgrounds, black on light
    final wallet = !_server && _method == PayMethod.applePay;
    final dark = ThemeController.isDark.value;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            backgroundColor: wallet ? (dark ? Colors.white : Colors.black) : null,
            foregroundColor: wallet ? (dark ? Colors.black : Colors.white) : null,
          ),
          onPressed: _busy ? null : _submit,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (wallet) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.apple, size: 20)),
            if (!wallet) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.lock_rounded, size: 18)),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        ),
        if (_checkout) ...[
          const SizedBox(height: 8),
          Text(
            _inStore
                ? 'Verlängert sich automatisch, bis du kündigst. Kündigen geht jederzeit in den Abos '
                    '${StorePurchases.platform == 'apple' ? 'deiner Apple-ID' : 'bei Google Play'}. '
                    'Mit dem Start akzeptierst du die Nutzungsbedingungen.'
                : 'Verlängert sich automatisch, bis du kündigst. Kündigen geht jederzeit unter Profil › Mein Abo. '
                    'Mit dem Start akzeptierst du die Nutzungsbedingungen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textDim, fontSize: 11),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final doc in [LegalTexts.terms, LegalTexts.privacy, LegalTexts.withdrawal])
              TextButton(
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    textStyle: const TextStyle(fontSize: 11.5)),
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => LegalDocScreen(doc: doc))),
                child: Text(doc.title == 'Nutzungsbedingungen' ? 'AGB' : doc.title.replaceAll('erklärung', '')),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _processing() => Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.6),
          alignment: Alignment.center,
          child: Container(
            width: 240,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const BuddyOrb(size: 56, active: true),
              const SizedBox(height: 16),
              Text(_server ? 'Zahlungsseite wird geöffnet …' : _checkout ? 'Plus wird freigeschaltet …' : 'Wird gespeichert …',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.lock_rounded, size: 13, color: AppColors.textDim),
                const SizedBox(width: 4),
                Text('Verschlüsselte Verbindung', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ]),
            ]),
          ),
        ),
      );
}

// Small badge per payment method, in the colours people know from checkouts.
class MethodLogo extends StatelessWidget {
  final PayMethod method;
  const MethodLogo(this.method, {super.key});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Widget child) = switch (method) {
      PayMethod.applePay || PayMethod.appStore => (
          Colors.black,
          Colors.white,
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.apple, color: Colors.white, size: 15),
            Text(method == PayMethod.applePay ? 'Pay' : 'Store',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
          ])
        ),
      PayMethod.googlePay || PayMethod.googlePlay => (
          Colors.white,
          Colors.black,
          Text(method == PayMethod.googlePay ? 'G Pay' : 'G Play',
              style: const TextStyle(color: Color(0xFF3C4043), fontWeight: FontWeight.w800, fontSize: 12))
        ),
      PayMethod.paypal => (
          const Color(0xFF003087),
          Colors.white,
          const Text('PayPal',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: 11.5))
        ),
      PayMethod.card => (
          AppColors.primary.withValues(alpha: 0.15),
          AppColors.primary,
          const Icon(Icons.credit_card_rounded, color: AppColors.primary, size: 20)
        ),
      PayMethod.sepa => (
          const Color(0xFF1A4B9B),
          Colors.white,
          const Text('SEPA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))
        ),
      PayMethod.klarna => (
          const Color(0xFFFFB3C7),
          Colors.black,
          const Text('Klarna.', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12))
        ),
    };
    return Container(
      width: 52,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: bg == Colors.white ? Border.all(color: const Color(0xFFDADCE0)) : null,
      ),
      child: DefaultTextStyle.merge(style: TextStyle(color: fg), child: child),
    );
  }
}

// "1234567812345678" -> "1234 5678 1234 5678"
class _GroupFormatter extends TextInputFormatter {
  final int size;
  final bool upper;
  _GroupFormatter(this.size, {this.upper = false});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var raw = newValue.text.replaceAll(' ', '');
    if (upper) raw = raw.toUpperCase();
    final buf = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (i > 0 && i % size == 0) buf.write(' ');
      buf.write(raw[i]);
    }
    final text = buf.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

// "1228" -> "12/28"
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll('/', '');
    final text = raw.length > 2 ? '${raw.substring(0, 2)}/${raw.substring(2)}' : raw;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

// Shown once after the start: what is unlocked and when the first payment is.
class _Welcome extends StatefulWidget {
  final Subscription sub;
  const _Welcome({required this.sub});

  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.sub;
    final pop = CurvedAnimation(parent: _anim, curve: Curves.elasticOut);
    final fade = CurvedAnimation(parent: _anim, curve: const Interval(0.3, 1, curve: Curves.easeOut));
    return Scaffold(
      body: Stack(children: [
        Positioned(
          top: -160,
          left: -120,
          right: -120,
          child: Container(
            height: 480,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.primary.withValues(alpha: 0.5),
                AppColors.primary.withValues(alpha: 0),
              ]),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
            child: Column(children: [
              ScaleTransition(
                scale: pop,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        colors: AppColors.heroBrand, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 60),
                ),
              ),
              const SizedBox(height: 28),
              FadeTransition(
                opacity: fade,
                child: Column(children: [
                  const Text('Willkommen bei Plus',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                  const SizedBox(height: 10),
                  Text(
                    'Dein Gratis-Test läuft bis ${Dates.full(sub.trialEnds)}. '
                    'Bis dahin kostet es nichts, und du kannst jederzeit kündigen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textDim, fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  for (final (icon, text) in const [
                    (Icons.auto_awesome_rounded, 'Buddy beantwortet jetzt jede Frage'),
                    (Icons.document_scanner_rounded, 'Belege scannen ohne Limit'),
                    (Icons.flag_rounded, 'So viele Sparziele, wie du willst'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        Icon(icon, color: AppColors.primary, size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
                        const Icon(Icons.check_circle_rounded, color: AppColors.positive, size: 20),
                      ]),
                    ),
                ]),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: () => Navigator.pop(context),
                child: const Text("Los geht's", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
