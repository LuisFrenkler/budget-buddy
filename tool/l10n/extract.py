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
DYNAMIC = ['Lebensmittel', 'Transport', 'Unterhaltung', 'Wohnen', 'Kleidung', 'Gesundheit', 'Bildung',
           'Essen & Trinken', 'Sonstiges', 'Umbuchung', 'Gehalt', 'Nebenjob', 'Investition', 'Geschenk',
           '1T', '1J', 'Max', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember', 'Jan', 'Feb', 'Mär', 'Apr', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez', 'Einmalig', 'Girokonto', 'Sparkonto', 'Bargeld', 'täglich', 'wöchentlich', 'monatlich', 'jährlich', 'Aktie', 'Krypto', 'mehr', 'weniger']

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
