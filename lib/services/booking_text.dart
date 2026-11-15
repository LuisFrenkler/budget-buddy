// Bank booking texts in plain words. Banks write „PP.8231.PP . NETFLIX, Ihr
// Einkauf bei NETFLIX“, „Mandatsref. 4711 Gläubiger-ID DE98ZZZ…“ or
// „Abschluss per 30.09.“; this says what actually happened and what the
// person can do about it. Runs on the device, on the stored bank text.
import '../l10n/l10n.dart';
import '../utils/merchant.dart';

class BookingText {
  static final _rules = <(RegExp, String)>[
    (RegExp(r'paypal|\bpp\.\d+', caseSensitive: false),
        'Bezahlt über PayPal{x}. PayPal holt das Geld per Lastschrift von deinem Konto, den eigentlichen Kauf siehst du in der PayPal-App.'),
    (RegExp(r'klarna', caseSensitive: false),
        'Bezahlt über Klarna{x}, auf Rechnung oder in Raten. Offene Raten siehst du in der Klarna-App.'),
    (RegExp(r'sumup|zettle|izettle|\bsq \*|square', caseSensitive: false),
        'Kartenzahlung an einem kleinen Kartenterminal (SumUp, Zettle oder Square){x}. Der echte Laden steht meist direkt danach.'),
    (RegExp(r'amzn|amazon', caseSensitive: false),
        'Eine Amazon-Bestellung. „Mktp“ heißt Marketplace: Verkauft hat ein anderer Händler über Amazon.'),
    (RegExp(r'apple pay|google pay', caseSensitive: false),
        'Bezahlt mit dem Handy, technisch eine ganz normale Kartenzahlung.'),
    (RegExp(r'r[üu]cklastschrift|rueckbelastung|r[üu]ckbuchung', caseSensitive: false),
        'Eine Lastschrift ging zurück, meist weil das Konto nicht gedeckt war oder du widersprochen hast. Das kostet oft Gebühren; melde dich beim Händler, bevor er mahnt.'),
    (RegExp(r'inkasso|creditreform|intrum|riverty|pair finance|lowell|coeo', caseSensitive: false),
        'Eine Zahlung an ein Inkassobüro. Prüf, ob die Forderung stimmt und ob die Gebühren angemessen sind; die Verbraucherzentrale hilft dabei.'),
    (RegExp(r'mahngeb[üu]hr|mahnkosten|mahnung|s[äa]umniszuschlag', caseSensitive: false),
        'Eine Gebühr, weil eine Rechnung zu spät bezahlt wurde. Ein Dauerauftrag oder eine Erinnerung verhindert das nächste Mal.'),
    (RegExp(r'auslandseinsatz|fremdw[äa]hrung|currency|w[äa]hrungsumrechnung', caseSensitive: false),
        'Eine Gebühr der Bank für eine Zahlung in fremder Währung oder im Ausland. Eine Karte ohne Auslandsgebühr spart das.'),
    (RegExp(r'abschluss|rechnungsabschluss|entgeltabrechnung|kontof[üu]hrung|kontoentgelt', caseSensitive: false),
        'Der Kontoabschluss der Bank: Gebühren für das Konto und Zinsen, etwa für den Dispo, für den letzten Zeitraum.'),
    (RegExp(r'dispo|sollzins|[üu]berziehungszins', caseSensitive: false),
        'Zinsen dafür, dass das Konto im Minus war. Dispozinsen sind teuer; schon ein kleiner Puffer auf dem Konto vermeidet sie.'),
    (RegExp(r'dauerauftrag', caseSensitive: false),
        'Ein Dauerauftrag: eine Überweisung, die du selbst eingerichtet hast und die jeden Monat von allein läuft.'),
    (RegExp(r'bargeld|geldautomat|\bga\b|auszahlung atm|\batm\b', caseSensitive: false),
        'Bargeld am Automaten abgehoben. Wofür es ausgegeben wurde, weiß die App nicht.'),
    (RegExp(r'kartenzahlung|girocard|debitk|\bpos\b|visa|mastercard|\bec\b', caseSensitive: false),
        'Eine Zahlung mit deiner Karte, an der Kasse oder online{x}.'),
    (RegExp(r'mand(?:at|ant)(?:s|en)?[\s\-]*ref|gl[äa]ubiger[\s\-]?id|lastschrift|cdtr|\bmref\b', caseSensitive: false),
        'Eine SEPA-Lastschrift: {y} zieht das Geld mit deiner Erlaubnis ein. Du kannst sie bis zu 8 Wochen lang ohne Grund bei deiner Bank zurückholen.'),
  ];

  static final _refs = RegExp(
      r'mand(?:at|ant)(?:s|en)?[\s\-]*ref|end[\s\-]?to[\s\-]?end|\beref\b|gl[äa]ubiger[\s\-]?id|\biban\b|\bbic\b|kundenreferenz',
      caseSensitive: false);
  static final _salary = RegExp(r'lohn|gehalt|bez[üu]ge|entgelt\s+\d|salary', caseSensitive: false);

  // a few plain sentences about one booking; empty when there is nothing to explain
  static List<String> explain({String? raw, String? note, required bool income}) {
    final text = '${raw ?? ''} ${note ?? ''}'.trim();
    if (text.isEmpty) return const [];
    final merchant = _merchant(raw, note);
    final out = <String>[];
    if (income) {
      if (_salary.hasMatch(text)) {
        out.add(tr('Dein Gehalt oder Lohn, überwiesen vom Arbeitgeber.'));
      } else if (RegExp(r'r[üu]ckzahlung|erstattung|gutschrift|refund', caseSensitive: false).hasMatch(text)) {
        out.add(tr('Geld zurück, zum Beispiel eine Erstattung oder Rücksendung.'));
      } else if (RegExp(r'paypal', caseSensitive: false).hasMatch(text)) {
        out.add(tr('Geld von PayPal auf dein Konto, etwa eine Rückzahlung oder ein Guthaben, das du abgebucht hast.'));
      }
    } else {
      var viaWallet = false;
      // a debt collector matters more than how it was paid
      final collector = _rules.indexWhere((r) => r.$2.startsWith('Eine Zahlung an ein Inkassobüro'));
      final order = [
        if (_rules[collector].$1.hasMatch(text)) collector,
        for (var i = 0; i < _rules.length; i++)
          if (i != collector) i
      ];
      for (final i in order) {
        final (re, sentence) = _rules[i];
        if (!re.hasMatch(text)) continue;
        if (i == collector) viaWallet = true;
        // PayPal and Klarna pull the debit themselves, their sentence says so
        if (i == _rules.length - 1 && viaWallet) continue;
        if (i <= 1) viaWallet = true;
        out.add(tr(sentence, {
          'x': merchant == null ? '' : tr(' an {m}', {'m': merchant}),
          'y': merchant ?? tr('Der Empfänger'),
        }));
        // one rail and one kind are enough (PayPal is also a Lastschrift)
        if (out.length >= 2) break;
      }
    }
    if (_refs.hasMatch(text)) {
      out.add(tr('Die langen Nummern (Mandatsreferenz, End-to-End-Referenz, Gläubiger-ID) sind Aktenzeichen für die Banken. Du brauchst sie nur, wenn du eine Lastschrift zurückholen oder reklamieren willst.'));
    }
    return out;
  }

  static String? _merchant(String? raw, String? note) {
    final n = note?.trim() ?? '';
    if (n.isNotEmpty && !Merchant.isSepaJunk(n) && n.toLowerCase() != 'bankbuchung') {
      final t = Merchant.tidy(n);
      if (t.isNotEmpty && !RegExp(r'^(paypal|klarna|sumup)', caseSensitive: false).hasMatch(t)) return t;
    }
    final r = raw?.trim() ?? '';
    if (r.isEmpty) return null;
    final t = Merchant.display(counterparty: '', purpose: r);
    return t == 'Bankbuchung' ? null : t;
  }
}
