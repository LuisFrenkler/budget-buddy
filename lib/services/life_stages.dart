// Lebenslagen instead of menus: the moments when money questions pile up.
// "Erster Job" is built out fully, the others are smaller starting points.
// Each step is a question Buddy talks through (with the person's numbers when
// signed in and the AI is on) and a short offline answer that is useful on
// its own, also before an account exists.
//
// Buddy prepares, the person decides: a step that creates something (a
// savings goal) ends in the usual confirm card.
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../l10n/l10n.dart';

// texts are German keys, shown in the app language
class LifeStep {
  final String id;
  final String _title;
  final String _subtitle;
  final String _prompt; // what goes into the chat
  final String _offline; // the answer without AI
  const LifeStep(this.id, this._title, this._subtitle, this._prompt, this._offline);
  String get title => tr(_title);
  String get subtitle => tr(_subtitle);
  String get prompt => tr(_prompt);
  String get offline => tr(_offline);
}

class LifeStage {
  final String id;
  final String _name;
  final String _tagline;
  final IconData icon;
  final List<LifeStep> steps;
  const LifeStage(this.id, this._name, this._tagline, this.icon, this.steps);
  String get name => tr(_name);
  String get tagline => tr(_tagline);
}

class LifeStages {
  static const stageKey = 'lifeStage';
  static const doneKey = 'lifeStageDone';

  static const firstJob = LifeStage('erster-job', 'Erster Job', 'Gehalt, Betriebsrente, Notgroschen, Sparrate',
      Icons.work_outline_rounded, [
    LifeStep(
      'gehalt',
      'Gehaltsabrechnung prüfen',
      'Stimmen Steuerklasse, Kasse und Abzüge?',
      'Hilf mir, meine erste Gehaltsabrechnung zu prüfen. Worauf muss ich achten?',
      'Zuerst die **Steuerklasse**: ledig ist Klasse I, sonst frag in der Personalabteilung. '
          'Steuer-ID und Krankenkasse müssen stimmen, die Sozialabgaben liegen grob bei einem Fünftel vom Brutto. '
          'Vermögenswirksame Leistungen oder Betriebsrente nur, wenn vereinbart, und das **Netto** muss genau so ankommen.\n\n'
          'Nächster Schritt: Schick mir ein Foto, dann gehe ich die Abrechnung mit dir durch.',
    ),
    LifeStep(
      'betriebsrente',
      'Betriebsrente klären',
      'Zuschuss vom Arbeitgeber mitnehmen',
      'Lohnt sich die Betriebsrente bei meinem ersten Job? Was sollte ich die Personalabteilung fragen?',
      'Bei der Betriebsrente fließt ein Teil des Bruttos über den Arbeitgeber in einen Vertrag. '
          'Spart er dabei Sozialabgaben, gibt er meist **15 Prozent** dazu, oft mehr. '
          'Frag nach Zuschuss, Kosten und was bei einem Jobwechsel passiert.\n\n'
          'Nächster Schritt: Mit den drei Antworten rechnen wir, ob es sich lohnt.',
    ),
    LifeStep(
      'notgroschen',
      'Notgroschen aufbauen',
      'Drei Monatsausgaben, sofort erreichbar',
      'Wie hoch sollte mein Notgroschen sein und wie baue ich ihn auf?',
      'Faustregel: **drei Monatsausgaben** auf dem Tagesgeld, bei 1.500 Euro Ausgaben also 4.500 Euro, und das vor jedem Investieren. '
          'Er fängt Waschmaschine, Umzug oder das Ende der Probezeit ab. Ein Dauerauftrag direkt nach dem Gehalt füllt ihn von allein.\n\n'
          'Nächster Schritt: Sag „Sparziel Notgroschen 4500“, dann lege ich das Ziel an, sobald du bestätigst.',
    ),
    LifeStep(
      'sparrate',
      'Sparrate festlegen',
      'Ein fester Betrag direkt nach dem Gehalt',
      'Wie viel sollte ich von meinem Gehalt jeden Monat sparen?',
      'Start mit **10 bis 20 Prozent** vom Netto, per Dauerauftrag am Zahltag. '
          'Erst den Notgroschen, dann einen breit gestreuten ETF-Sparplan. Lieber klein anfangen und jährlich erhöhen, und von einer Gehaltserhöhung die Hälfte in die Sparrate.\n\n'
          'Nächster Schritt: Mit Konto rechne ich aus deinen Ausgaben, was realistisch ist.',
    ),
    LifeStep(
      'steuer',
      'Steuererklärung im ersten Jahr',
      'Oft gibt es Geld zurück',
      'Lohnt sich für mich im ersten Jobjahr eine Steuererklärung?',
      'Im ersten Jahr lohnt sich die Steuererklärung oft, weil ohne volles Jahr meist zu viel Lohnsteuer abgezogen wurde. '
          'Fahrtkosten, Arbeitsmittel und ein Umzug für den Job zählen, und ELSTER ist kostenlos.\n\n'
          'Nächster Schritt: Belege für Arbeitsweg und Arbeitsmittel ab jetzt sammeln.',
    ),
  ]);

  static const moving = LifeStage('umzug', 'Umzug', 'Kaution, Umzugskosten, Verträge', Icons.local_shipping_outlined, [
    LifeStep(
      'kaution',
      'Kaution einplanen',
      'Höchstens drei Kaltmieten',
      'Wie viel Geld brauche ich für die Kaution und den Umzug?',
      'Die Kaution ist höchstens **drei Monatskaltmieten** und darf in drei Raten gezahlt werden. '
          'Dazu oft doppelte Miete, Transporter und Möbel, also ein Umzugsbudget, nicht den Notgroschen leeren.\n\n'
          'Nächster Schritt: Sag „Sparziel Umzug 2000“, dann lege ich es an, sobald du bestätigst.',
    ),
    LifeStep(
      'vertraege',
      'Verträge ummelden',
      'Strom, Internet, Versicherungen',
      'Welche Verträge muss ich beim Umzug ummelden oder kündigen?',
      'Strom und Internet ummelden, oft mit Sonderkündigung, und Haftpflicht und Hausrat die neue Adresse und Wohnfläche geben. '
          'Rundfunkbeitrag, Bank und Arbeitgeber brauchen nur die neue Adresse.\n\n'
          'Nächster Schritt: Unter Verträge zeige ich, was regelmäßig abgeht.',
    ),
  ]);

  static const together = LifeStage('zusammenziehen', 'Zusammenziehen', 'Kosten fair teilen',
      Icons.favorite_border_rounded, [
    LifeStep(
      'teilen',
      'Kosten fair aufteilen',
      'Hälfte oder nach Einkommen',
      'Wie teilen wir gemeinsame Kosten fair auf, wenn wir zusammenziehen?',
      '**Halbe-halbe** passt bei ähnlichem Einkommen. Bei großem Unterschied trägt, wer mehr verdient, anteilig mehr, das fühlt sich oft fairer an.\n\n'
          'Nächster Schritt: Unter Geteilt eine Gruppe anlegen, dann rechne ich mit, wer wem was schuldet.',
    ),
    LifeStep(
      'konto',
      'Gemeinsames Konto?',
      'Für Miete und Einkäufe',
      'Brauchen wir ein Gemeinschaftskonto, wenn wir zusammenziehen?',
      'Ein Gemeinschaftskonto für Miete, Strom und Einkäufe hält den Rest getrennt. '
          'Jeder zahlt einen festen Betrag ein.\n\n'
          'Nächster Schritt: Gemeinsame Kosten und Monatsbetrag festlegen.',
    ),
  ]);

  static const pension2027 = LifeStage('vorsorge-2027', 'Altersvorsorgedepot', 'Neu ab 2027, früh vorbereiten',
      Icons.savings_outlined, [
    LifeStep(
      'was',
      'Was ist das?',
      'Gefördert für die Rente sparen',
      'Was ist das Altersvorsorgedepot und lohnt es sich für mich?',
      'Geplantes, staatlich gefördertes Depot — Start laut Plan **1. Januar 2027**. Details können sich noch ändern.\n\n'
          'Nächster Schritt: Mit „Vorsorge einrichten“ die Rentenlücke grob rechnen.',
    ),
    LifeStep(
      'luecke',
      'Rentenlücke berechnen',
      'Wie viel fehlt im Alter?',
      'Vorsorge einrichten',
      'Mit „Vorsorge einrichten“ rechne ich aus Alter, Netto und Wunschrente eine grobe Lücke. '
          'Orientierung, keine Rentenberatung.',
    ),
  ]);

  static const all = [firstJob, moving, together, pension2027];

  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  static LifeStage? byId(String? id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  static LifeStage? get current => byId(_box?.get(stageKey) as String?);

  static Future<void> choose(LifeStage? stage) async {
    if (stage == null) {
      await _box?.delete(stageKey);
    } else {
      await _box?.put(stageKey, stage.id);
    }
  }

  static Set<String> done() => ((_box?.get(doneKey) as List?) ?? const []).cast<String>().toSet();

  static bool isDone(LifeStage stage, LifeStep step) => done().contains('${stage.id}/${step.id}');

  static Future<void> setDone(LifeStage stage, LifeStep step, bool value) async {
    final set = done();
    final key = '${stage.id}/${step.id}';
    value ? set.add(key) : set.remove(key);
    await _box?.put(doneKey, set.toList());
  }

  static int progress(LifeStage stage) => stage.steps.where((s) => isDone(stage, s)).length;

  // for the AI summary: which stage and what is still open
  static Map<String, dynamic>? snapshot() {
    final s = current;
    if (s == null) return null;
    return {
      'name': s.name,
      'erledigt': [for (final step in s.steps) if (isDone(s, step)) step.title],
      'offen': [for (final step in s.steps) if (!isDone(s, step)) step.title],
    };
  }

  // a question that fits one of the steps (used by the offline and guest answers)
  static LifeStep? stepFor(String question) {
    final q = question.toLowerCase();
    for (final stage in all) {
      for (final step in stage.steps) {
        if (step.prompt.toLowerCase() == q) return step;
      }
    }
    const hints = <String, List<String>>{
      'gehalt': ['gehaltsabrechnung', 'lohnabrechnung', 'abrechnung prüfen', 'steuerklasse', 'payslip', 'tax class'],
      'betriebsrente': ['betriebsrente', 'bav', 'entgeltumwandlung', 'company pension'],
      'notgroschen': ['notgroschen', 'notreserve', 'rücklage', 'emergency fund'],
      'sparrate': ['wie viel sparen', 'wieviel sparen', 'sparrate', 'wie viel sollte ich', 'monatlich sparen', 'how much should i save', 'savings rate'],
      'steuer': ['steuererklärung', 'steuer zurück', 'elster', 'tax return'],
      'kaution': ['kaution', 'umzug kost', 'umziehen', 'deposit'],
      'vertraege': ['ummelden', 'verträge umzug', 'contracts when i move'],
      'teilen': ['zusammenziehen', 'kosten teilen', 'fair aufteilen', 'moving in together', 'split costs'],
      'konto': ['gemeinschaftskonto', 'gemeinsames konto', 'joint account'],
      'was': ['altersvorsorgedepot', 'retirement savings depot'],
    };
    for (final entry in hints.entries) {
      if (entry.value.any(q.contains)) {
        for (final stage in all) {
          for (final step in stage.steps) {
            if (step.id == entry.key) return step;
          }
        }
      }
    }
    return null;
  }
}
