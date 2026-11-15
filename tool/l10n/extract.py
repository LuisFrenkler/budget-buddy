#!/usr/bin/env python3
"""Lists every German text the app translates, as written in the Dart source.

  python3 tool/l10n/extract.py            -> tool/l10n/keys.json
  python3 tool/l10n/extract.py --missing  -> keys without an entry in lib/l10n/en.dart

Keys are tr('…') first arguments (adjacent literals joined) plus the texts of
the const content classes (LifeStage, LifeStep, GlossaryTerm), which translate
through getters.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from wrap import scan  # noqa: E402

# texts that reach tr() through a variable: category names, intervals, types
DYNAMIC = ['Eine Gebühr, weil eine Rechnung zu spät bezahlt wurde. Ein Dauerauftrag oder eine Erinnerung verhindert das nächste Mal.', 'Eine Zahlung an ein Inkassobüro. Prüf, ob die Forderung stimmt und ob die Gebühren angemessen sind; die Verbraucherzentrale hilft dabei.', 'ausgeglichen', 'du bekommst {x}', 'du schuldest {x}', 'deinen Notgroschen', 'ob es passt', 'die Buchung', 'Bezahlt über PayPal{x}. PayPal holt das Geld per Lastschrift von deinem Konto, den eigentlichen Kauf siehst du in der PayPal-App.', 'Bezahlt über Klarna{x}, auf Rechnung oder in Raten. Offene Raten siehst du in der Klarna-App.', 'Kartenzahlung an einem kleinen Kartenterminal (SumUp, Zettle oder Square){x}. Der echte Laden steht meist direkt danach.', 'Eine Amazon-Bestellung. „Mktp“ heißt Marketplace: Verkauft hat ein anderer Händler über Amazon.', 'Bezahlt mit dem Handy, technisch eine ganz normale Kartenzahlung.', 'Eine Lastschrift ging zurück, meist weil das Konto nicht gedeckt war oder du widersprochen hast. Das kostet oft Gebühren; melde dich beim Händler, bevor er mahnt.', 'Eine Gebühr der Bank für eine Zahlung in fremder Währung oder im Ausland. Eine Karte ohne Auslandsgebühr spart das.', 'Der Kontoabschluss der Bank: Gebühren für das Konto und Zinsen, etwa für den Dispo, für den letzten Zeitraum.', 'Zinsen dafür, dass das Konto im Minus war. Dispozinsen sind teuer; schon ein kleiner Puffer auf dem Konto vermeidet sie.', 'Ein Dauerauftrag: eine Überweisung, die du selbst eingerichtet hast und die jeden Monat von allein läuft.', 'Bargeld am Automaten abgehoben. Wofür es ausgegeben wurde, weiß die App nicht.', 'Eine Zahlung mit deiner Karte, an der Kasse oder online{x}.', 'Eine SEPA-Lastschrift: {y} zieht das Geld mit deiner Erlaubnis ein. Du kannst sie bis zu 8 Wochen lang ohne Grund bei deiner Bank zurückholen.', 'deine Sparrate', 'die Gehaltsrechnung', 'deine Konten', 'deine Ausgaben', 'deine Einnahmen', 'deine Buchungen', 'die letzten Monate', 'deine Verträge', 'deinen Monat', 'deine Ziele', 'ein Szenario', 'einen Sparplan', 'die Rechnung', 'dein Budget', 'dein Sparziel', 'die Kündigung', 'die Kategorien', 'deine Erinnerung', 'ein Diagramm', 'deine Zahlen', 'deine Zahlen noch einmal', 'die Kündigungsfrist',
           'Lebensmittel', 'Transport', 'Unterhaltung', 'Wohnen', 'Kleidung', 'Gesundheit', 'Bildung',
           'Essen & Trinken', 'Sonstiges', 'Umbuchung', 'Gehalt', 'Nebenjob', 'Investition', 'Geschenk',
           '1T', '1J', 'Max', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember', 'Jan', 'Feb', 'Mär', 'Apr', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez', 'Essen gehen', 'Abos', 'Sport', 'Handy', 'Versicherung', 'Freizeit', 'Technik', 'Shopping', 'Zahl stimmt nicht', 'Hilft mir nicht', 'Zu lang', 'Falscher Ton', 'Anderes', 'Einmalig', 'Girokonto', 'Sparkonto', 'Bargeld', 'täglich', 'wöchentlich', 'monatlich', 'jährlich', 'Aktie', 'Krypto', 'mehr', 'weniger']

CONTENT = {'lib/services/life_stages.dart', 'lib/services/glossary.dart'}


def groups(src):
    lits = list(scan(src))
    out, cur = [], []
    for lit in lits:
        if cur and src[cur[-1][1]:lit[0]].strip() == '' and not lit[3] and not cur[-1][3]:
            cur.append(lit)
        else:
            if cur:
                out.append(cur)
            cur = [lit]
    if cur:
        out.append(cur)
    return out


def text_of(src, g):
    # the source text between the quotes, joined; interpolations kept as written
    return ''.join(src[a + 1:b - 1] for a, b, _, _ in g)


def keys_in(path):
    src = open(path).read()
    keys = []
    for g in groups(src):
        start = g[0][0]
        before = src[max(0, start - 30):start]
        if re.search(r'\btr\(\s*$', before):
            keys.append(text_of(src, g))
        elif path in CONTENT:
            t = text_of(src, g)
            line_start = src.rfind('\n', 0, start) + 1
            line = src[line_start:start]
            if re.fullmatch(r'[a-z0-9-]+', t) or 'also:' in line or 'import' in line or 'Key' in line:
                continue
            if re.search(r"(LifeStep|LifeStage)\(\s*$", before):  # the id
                continue
            if t == t.lower():  # keywords for matching questions, not shown
                continue
            if ' ' in t or re.match(r'[A-ZÄÖÜ]', t):
                keys.append(t)
    return keys


def all_keys():
    seen = {k: 'dynamic' for k in DYNAMIC}
    for root, _, files in os.walk('lib'):
        for f in sorted(files):
            p = os.path.join(root, f)
            if f.endswith('.dart') and '/l10n/' not in p:
                for k in keys_in(p):
                    seen.setdefault(k, p)
    return seen


def en_keys():
    src = open('lib/l10n/en.dart').read()
    out = set()
    for g in groups(src):
        a = g[-1][1]
        if src[a:a + 20].lstrip().startswith(':'):
            out.add(text_of(src, g))
    return out


if __name__ == '__main__':
    keys = all_keys()
    if '--missing' in sys.argv:
        have = en_keys()
        miss = [k for k in keys if k not in have]
        json.dump(miss, sys.stdout, ensure_ascii=False, indent=0)
        print(f'\n{len(miss)} missing of {len(keys)}', file=sys.stderr)
    else:
        json.dump(list(keys), open('tool/l10n/keys.json', 'w'), ensure_ascii=False, indent=0)
        print(f'{len(keys)} keys', file=sys.stderr)
