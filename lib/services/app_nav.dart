// Where the agent can take the person: one name per place in the app.
// The agent (a tool call, a button under an answer) asks for a place; the
// shell listens and opens it. The names are German because the model reads
// and writes them; the server's tool schema has the same list.
import 'package:flutter/foundation.dart';

class AppNav {
  static const places = {
    'ueberblick', // tab: Überblick
    'konto', // tab: Konto, Umsätze
    'budgets', // tab: Konto, Budgets
    'analyse', // tab: Konto, Analyse
    'depot', // tab: Depot
    'agent', // tab: Ahead (the feed and the chat)
    'vertraege',
    'ziele',
    'steuer', // the tax page; [year] picks the year
    'steuer_check',
    'vorsorge',
    'vermoegen',
    'wochenbericht',
    'dauerauftraege',
    'gruppen',
    'bank',
    'daten',
    'profil',
    'benachrichtigungen',
    'garantie',
    'gedaechtnis',
    'protokoll',
    'plus',
    'einladen',
  };

  // the place asked for; the shell opens it and sets this back to null
  static final go = ValueNotifier<({String place, int? year})?>(null);

  // false when the place does not exist, so the agent can say so instead of pretending
  static bool open(String place, {int? year}) {
    if (!places.contains(place)) return false;
    go.value = (place: place, year: year);
    return true;
  }
}
