#!/usr/bin/env python3
"""Wraps German user-facing string literals of a Dart file in tr(...).

  python3 tool/l10n/wrap.py lib/services/hints_service.dart [--dry]

Adjacent literals ('a ' 'b') are joined, interpolations become placeholders:
'Noch $n Tage, ${Money.format(x)}' -> tr('Noch {n} Tage, {x}', {'n': n, 'x': Money.format(x)}).
Skips literals that are ids, keys, regexes, imports, comparisons or already
inside tr(...). Review the diff afterwards; const contexts need a manual look.
"""
import re
import sys

GERMAN = re.compile(r"[äöüßÄÖÜ]|\b(in|neu|Neu|abgelaufen|Tagen|Jahr|Monaten|Wochen|Uhr|oder|ohne|aus|ab|An|Aus|du|dich|dir|dein|deine|deinen|deinem|ist|sind|und|nicht|noch|im|am|für|von|mit|zur|zum|bis|wird|kein|keine|Buddy|Konto|Monat|Tag|Tage|heute|morgen|gespeichert|Geld|Ziel|Budget|Ausgabe|Ausgaben|Einnahmen|Woche|Gehalt|jetzt|schon|alle|bitte|Bitte)\b")
# single words that are shown, not keys
SINGLE = {'heute', 'morgen', 'gestern', 'An', 'Aus', 'Heute', 'Morgen', 'Gestern', 'täglich', 'wöchentlich',
          'monatlich', 'jährlich', 'Sonstiges', 'Neu', 'Fertig', 'Weiter', 'Zurück', 'Abbrechen', 'Speichern'}
SKIP_BEFORE = re.compile(r"(RegExp\(\s*r?|tr\(\s*|==\s*|!=\s*|case\s+|import\s+|startsWith\(|contains\(|endsWith\(|get\(|put\(|\[\s*)$")


def scan(src):
    """Yields (start, end, parts) for single-quoted literals; parts are
    ('text', s) and ('expr', s) pieces."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if src.startswith('/*', i):
            j = src.find('*/', i)
            i = n if j < 0 else j + 2
            continue
        if c == '"':
            # skip double-quoted strings
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == '\\' else 1
            i = j + 1
            continue
        if c == "'" and not src.startswith("'''", i):
            raw = i > 0 and src[i - 1] == 'r' and (i < 2 or not (src[i - 2].isalnum() or src[i - 2] == '_'))
            start = i
            j = i + 1
            parts = []
            buf = ''
            while j < n and src[j] != "'":
                if src[j] == '\\' and not raw:
                    buf += src[j:j + 2]
                    j += 2
                elif src[j] == '$' and not raw:
                    if j + 1 < n and src[j + 1] == '{':
                        depth, k = 1, j + 2
                        while k < n and depth:
                            if src[k] == '{':
                                depth += 1
                            elif src[k] == '}':
                                depth -= 1
                            elif src[k] == "'":
                                k += 1
                                while k < n and src[k] != "'":
                                    k += 2 if src[k] == '\\' else 1
                            k += 1
                        if buf:
                            parts.append(('text', buf))
                            buf = ''
                        parts.append(('expr', src[j + 2:k - 1]))
                        j = k
                    else:
                        m = re.match(r'\$([A-Za-z_][A-Za-z0-9_]*)', src[j:])
                        if buf:
                            parts.append(('text', buf))
                            buf = ''
                        parts.append(('expr', m.group(1)))
                        j += len(m.group(0))
                else:
                    buf += src[j]
                    j += 1
            if buf:
                parts.append(('text', buf))
            yield start - (1 if raw else 0), j + 1, parts, raw
            i = j + 1
            continue
        i += 1


def name_for(expr, used):
    simple = re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', expr)
    base = expr if simple else None
    if base is None:
        m = re.search(r'([A-Za-z_][A-Za-z0-9_]*)\s*(\)|$)', expr)
        base = 'x'
    for cand in ([base] if base != 'x' else []) + ['x', 'y', 'z', 'a', 'b', 'c', 'd', 'e']:
        if cand not in used:
            return cand
    k = 1
    while f'v{k}' in used:
        k += 1
    return f'v{k}'


def convert(src):
    lits = list(scan(src))
    # join adjacent literals (only whitespace between)
    groups, cur = [], []
    for lit in lits:
        if cur and src[cur[-1][1]:lit[0]].strip() == '' and not lit[3] and not cur[-1][3]:
            cur.append(lit)
        else:
            if cur:
                groups.append(cur)
            cur = [lit]
    if cur:
        groups.append(cur)
    out, pos, count = [], 0, 0
    for g in groups:
        start, end = g[0][0], g[-1][1]
        if g[0][3]:
            continue
        parts = [p for lit in g for p in lit[2]]
        text = ''.join(t for k, t in parts if k == 'text')
        if not GERMAN.search(text):
            continue
        before = src[max(0, start - 40):start]
        if SKIP_BEFORE.search(before.rstrip(' ') if before.endswith(' ') else before):
            continue
        if re.search(r'^[\w./:-]+$', text) and text not in SINGLE:  # ids and keys
            continue
        used, args, key = set(), [], ''
        for k, t in parts:
            if k == 'text':
                key += t.replace('{', '(').replace('}', ')')
            else:
                nm = name_for(t.strip(), used)
                used.add(nm)
                inner, _ = convert(t.strip())
                args.append((nm, inner))
                key += '{' + nm + '}'
        call = "tr('" + key + "'"
        if args:
            call += ', {' + ', '.join(f"'{a}': {e}" for a, e in args) + '}'
        call += ')'
        out.append(src[pos:start])
        out.append(call)
        pos = end
        count += 1
    out.append(src[pos:])
    return ''.join(out), count


if __name__ == '__main__':
    path = sys.argv[1]
    src = open(path).read()
    new, n = convert(src)
    if '--dry' in sys.argv:
        import difflib
        sys.stdout.writelines(difflib.unified_diff(src.splitlines(True), new.splitlines(True), path, path, n=0))
    else:
        if "l10n/l10n.dart'" not in new:
            m = list(re.finditer(r"^import .*;\n", new, re.M))
            if m:
                rel = '../' * (path.count('/') - 1) + 'l10n/l10n.dart'
                new = new[:m[-1].end()] + f"import '{rel}';\n" + new[m[-1].end():]
        open(path, 'w').write(new)
    print(f'{path}: {n} wrapped', file=sys.stderr)
