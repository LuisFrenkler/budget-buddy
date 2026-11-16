// Picks the first testers from the waitlist and writes their invitations.
//
//   ssh root@SERVER "cd /opt/ahead/deploy && docker compose exec -T server cat /app/.data/growth.json" > growth.json
//   dart run bin/testers.dart growth.json 20
//
// Writes build/testers/testers.csv (email, language, place, friends) and one
// invitation text per language. Send them yourself, e.g. as BCC; the test
// links (TestFlight, Play internal testing, web app) go into the texts below.
import 'dart:io';

import '../lib/growth.dart';

const _invite = {
  'de': '''Betreff: Du bist dabei: Ahead testen

Hey,

du stehst weit vorne auf der Warteliste von Ahead, darum bist du einer der Ersten, die Buddy testen.

So geht's:
iPhone: TESTFLIGHT_LINK
Android: PLAY_LINK
Im Browser: WEB_LINK

Was wir uns wünschen: Nutz Ahead zwei Wochen lang ganz normal und frag Buddy alles, was dir zu Geld einfällt. Passt eine Antwort nicht, tipp auf den Daumen nach unten. Genau daraus lernt Buddy.

Nach zwei Wochen schicken wir dir fünf kurze Fragen. Danke, dass du dabei bist!

Luis von Ahead''',
  'en': '''Subject: You're in: test Ahead

Hey,

you're near the top of the Ahead waitlist, so you're one of the first to try Buddy.

How to start:
iPhone: TESTFLIGHT_LINK
Android: PLAY_LINK
In the browser: WEB_LINK

What we'd love: use Ahead normally for two weeks and ask Buddy anything about money. If an answer is off, tap thumbs down. That's exactly how Buddy learns.

After two weeks we'll send you five short questions. Thanks for being part of it!

Luis from Ahead''',
};

// the five questions after two weeks
const _survey = {
  'de': '''1. Wie oft hast du Buddy in den zwei Wochen gefragt? (nie, 1–3 Mal, öfter)
2. Welche Antwort hat dir am meisten geholfen?
3. Wo lag Buddy daneben?
4. Wie sehr würdest du Ahead vermissen, wenn es weg wäre? (gar nicht, etwas, sehr)
5. Was fehlt dir am meisten?''',
  'en': '''1. How often did you ask Buddy in these two weeks? (never, 1–3 times, more)
2. Which answer helped you most?
3. Where was Buddy off?
4. How much would you miss Ahead if it were gone? (not at all, a bit, a lot)
5. What do you miss most?''',
};

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Pfad zu growth.json fehlt');
    exit(64);
  }
  final n = args.length > 1 ? int.tryParse(args[1]) ?? 20 : 20;
  final growth = Growth(File(args[0]));
  await growth.load();
  final front = growth.front(n);
  final dir = Directory('build/testers')..createSync(recursive: true);
  final csv = StringBuffer('email,sprache,platz,freunde\n');
  for (final t in front) {
    csv.writeln('${t['email']},${t['lang']},${t['position']},${t['friends']}');
  }
  File('${dir.path}/testers.csv').writeAsStringSync(csv.toString());
  for (final lang in ['de', 'en']) {
    File('${dir.path}/einladung_$lang.txt').writeAsStringSync(_invite[lang]!);
    File('${dir.path}/umfrage_$lang.txt').writeAsStringSync(_survey[lang]!);
  }
  final en = front.where((t) => t['lang'] == 'en').length;
  stdout.writeln('${front.length} Tester (${front.length - en} Deutsch, $en Englisch) in ${dir.path}/testers.csv');
}
