#!/usr/bin/env python3
"""Writes lib/l10n/en.dart from tool/l10n/keys.json and translation files.

  python3 tool/l10n/build_en.py DIR

DIR holds index.json (number -> German, optional) and *.txt files with lines "index|English", index into keys.json, text
as Dart source (\\n for line breaks). Entries already in en.dart are kept;
new ones are added. Placeholders {x} must match the German key.
"""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from extract import groups, text_of  # noqa: E402


def existing():
    src = open('lib/l10n/en.dart').read()
    gs = groups(src)
    out = {}
    for i, g in enumerate(gs):
        a = g[-1][1]
        if src[a:a + 20].lstrip().startswith(':') and i + 1 < len(gs):
            out[text_of(src, g)] = text_of(src, gs[i + 1])
    return out


def dart(s):
    s = re.sub(r"(?<!\\)'", r"\\'", s)
    return re.sub(r"(?<!\\)\$", r"\\$", s)


if __name__ == '__main__':
    keys = json.load(open('tool/l10n/keys.json'))
    # the indices of a translation batch refer to the keys it was cut from
    index = os.path.join(sys.argv[1], 'index.json')
    numbered = json.load(open(index)) if os.path.exists(index) else {str(n): k for n, k in enumerate(keys)}
    table = existing()
    bad = []
    for f in sorted(glob.glob(os.path.join(sys.argv[1], '*.txt'))):
        for line in open(f).read().split('\n'):
            if not line.strip():
                continue
            i, en = line.split('|', 1)
            de = i[1:] if i.startswith('@') else numbered[i]
            if set(re.findall(r'\{\w+\}', de)) != set(re.findall(r'\{\w+\}', en)):
                bad.append((i, de, en))
            table[de] = dart(en)
    for b in bad:
        print('placeholders differ:', b, file=sys.stderr)
    order = {k: n for n, k in enumerate(keys)}
    lines = ['// English texts, keyed by the German original (see l10n.dart).',
             '// Generated entries come from tool/l10n/build_en.py; edit freely.',
             'const en = <String, String>{']
    for k in sorted(table, key=lambda k: order.get(k, -1)):
        lines.append(f"  '{k}': '{table[k]}',")
    lines.append('};\n')
    open('lib/l10n/en.dart', 'w').write('\n'.join(lines))
    print(f'{len(table)} entries, {len(bad)} placeholder problems', file=sys.stderr)
    sys.exit(1 if bad else 0)
