#!/usr/bin/env python3
"""Wraps German UI texts in Dart files with tr() (see lib/l10n/l10n.dart).

  python3 tool/l10n_wrap.py lib/screens/foo.dart ...   wrap texts in place
  python3 tool/l10n_wrap.py --missing                   list tr() texts without English

Interpolation becomes placeholders: 'Noch $n Tage' -> tr('Noch {n} Tage', {'n': n}).
Literals it cannot convert safely are printed as SKIP for a manual look.
Review every diff: a text that is data (a stored category, a map key) must
not be wrapped.
"""
import re
import sys
import glob

UI = re.compile(r"[A-Za-zÄÖÜäöüß]{2,}")
GERMAN_HINT = re.compile(r"[äöüßÄÖÜ]|[A-Za-z]+ [A-Za-z]|\b[A-ZÄÖÜ][a-zäöüß]{2,}")


def scan(src):
    """Yields (start, end, quote) of every top-level string literal."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            i = src.find('\n', i)
            i = n if i < 0 else i
            continue
        if src.startswith('/*', i):
            i = src.find('*/', i) + 2
            continue
        raw = c == 'r' and i + 1 < n and src[i + 1] in '\'"' and not (src[i - 1].isalnum() or src[i - 1] == '_')
        if c in '\'"' or raw:
            start = i
            if raw:
                i += 1
            q = src[i] * 3 if src.startswith(src[i] * 3, i) else src[i]
            i = skip_string(src, i + len(q), q, raw)
            yield start, i, q
            continue
        i += 1


def skip_string(src, i, q, raw):
    n = len(src)
    while i < n:
        if src.startswith(q, i):
            return i + len(q)
        c = src[i]
        if c == '\\' and not raw:
            i += 2
            continue
        if c == '$' and not raw and src.startswith('${', i):
            i = skip_braces(src, i + 2)
            continue
        i += 1
    return n


def skip_braces(src, i):
    depth = 1
    while depth:
        c = src[i]
        if c in '\'"':
            q = src[i] * 3 if src.startswith(src[i] * 3, i) else src[i]
            i = skip_string(src, i + len(q), q, False)
            continue
        depth += c == '{'
        depth -= c == '}'
        i += 1
    return i


def groups(src):
    """Adjacent literals ('a' 'b') form one text."""
    lits = list(scan(src))
    out, k = [], 0
    while k < len(lits):
        g = [lits[k]]
        while k + 1 < len(lits) and src[lits[k][1]:lits[k + 1][0]].strip() == '':
            k += 1
            g.append(lits[k])
        out.append(g)
        k += 1
    return out


def body(src, lit):
    s, e, q = lit
    return src[s + len(q):e - len(q)]


SKIP_BEFORE = re.compile(
    r"(import|export|part|case|==|!=|\.get\(|\.put\(|\.delete\(|Hive\.box\(|openBox\(|Key\(|containsKey\(|"
    r"(?<=[\w)\]])\[|debugPrint\(|print\(|tr\(|RegExp\(|fontFamily:|semanticsIdentifier:|restorationId:|\.startsWith\(|"
    r"\.endsWith\(|\.contains\(|split\(|replaceAll\(|Uri\.parse\(|\bid:|payload:|channel\w*:|'\w+':)\s*$")
SKIP_AFTER = re.compile(r"^(:|\s*==|\s*!=)")


def convert(text):
    """German literal body -> (tr literal body, args) or None if too complex."""
    args, out, i = [], [], 0
    while i < len(text):
        c = text[i]
        if c == '\\':
            out.append(text[i:i + 2])
            i += 2
            continue
        if c == '$':
            if text.startswith('${', i):
                j = skip_braces(text, i + 2)
                expr = text[i + 2:j - 1].strip()
                i = j
            else:
                m = re.match(r"\$([A-Za-z_]\w*)", text[i:])
                if not m:
                    return None
                expr = m.group(1)
                i += m.end()
            if '\n' in expr:
                return None
            if "'" in expr or '"' in expr:
                expr = wrap_expr(expr)  # n == 1 ? 'Tag' : 'Tage' -> tr('Tag') : tr('Tage')
                if expr is None:
                    return None
            name = placeholder(expr, [a for a, _ in args])
            args.append((name, expr))
            out.append('{' + name + '}')
            continue
        if c in '{}':
            return None  # a literal brace would look like a placeholder
        out.append(c)
        i += 1
    return ''.join(out), args


def wrap_expr(expr):
    """Wraps the texts inside an interpolated expression, None if unsure."""
    edits = []
    for g in groups(expr):
        if len(g) > 1 or g[0][2] != "'" or expr[g[0][0]] == 'r':
            return None
        text = body(expr, g[0])
        if not UI.search(text) or not GERMAN_HINT.search(re.sub(r"\$\{[^}]*\}|\$\w+", '', text)):
            continue
        if SKIP_BEFORE.search(expr[:g[0][0]]) or SKIP_AFTER.match(expr[g[0][1]:g[0][1] + 4]):
            continue
        conv = convert(text)
        if conv is None:
            return None
        lit, args = conv
        new = "tr('" + lit + "'" + (', {' + ', '.join(f"'{a}': {x}" for a, x in args) + '}' if args else '') + ')'
        edits.append((g[0][0], g[0][1], new))
    for st, en, new in reversed(edits):
        expr = expr[:st] + new + expr[en:]
    return expr


def placeholder(expr, taken):
    """A readable name for ${expr}: 'g.name' -> name, 'list.length' -> list, else x."""
    parts = re.fullmatch(r"[A-Za-z_][\w!.]*", expr) and [p.strip('!') for p in expr.split('.')]
    if parts and parts[-1] in ('value', 'length') and len(parts) > 1:
        parts = parts[:-1]
    base = parts[-1].lstrip('_') if parts else 'x'
    if not base or len(base) > 14:
        base = 'x'
    name, k = base, 2
    while name in taken:
        name, k = f"{base}{k}", k + 1
    return name


def wrap_file(path):
    src = open(path, encoding='utf-8').read()
    edits = []
    for g in groups(src):
        s, e = g[0][0], g[-1][1]
        if any(lit[2] in ("'''", '"""') or src[lit[0]] == 'r' for lit in g):
            continue
        text = ''.join(body(src, lit) for lit in g)
        plain = re.sub(r"\$\{[^}]*\}|\$\w+", '', text)
        if not UI.search(plain) or not GERMAN_HINT.search(plain):
            continue
        if re.search(r"://|@\w|^/|\.dart$|^[a-z_]+(\.[a-z_]+)+$", plain.strip()):
            continue
        if plain == text and re.fullmatch(r"[a-z_][\w-]*", text):
            continue  # an identifier, not a text
        line_start = src.rfind('\n', 0, s) + 1
        line_end = src.find('\n', e)
        if 'l10n: data' in src[line_start:line_end] or re.search(r"_has\(\w+, \[", src[line_start:s]):
            continue  # a stored value or a search keyword, not a text
        before = src[line_start:s]
        if SKIP_BEFORE.search(before) or SKIP_AFTER.match(src[e:e + 4]) or before.lstrip().startswith(('//', '///')):
            continue
        conv = convert(text)
        line = src.count('\n', 0, s) + 1
        if conv is None:
            print(f"SKIP {path}:{line}: {text[:70]}")
            continue
        lit, args = conv
        q = g[0][2] if all(x[2] == g[0][2] for x in g) else "'"
        if q == '"':
            lit = lit.replace('\\"', '"').replace("'", "\\'")
        new = "tr('" + lit + "'"
        if args:
            new += ', {' + ', '.join(f"'{a}': {x}" for a, x in args) + '}'
        new += ')'
        edits.append((s, e, new))
    for s, e, new in reversed(edits):
        src = src[:s] + new + src[e:]
    if edits:
        depth = path.count('/') - 1
        imp = "import '" + '../' * depth + "l10n/l10n.dart';\n"
        if 'l10n/l10n.dart' not in src:
            m = list(re.finditer(r"^import .*;\n", src, re.M))
            at = m[-1].end() if m else 0
            src = src[:at] + imp + src[at:]
        open(path, 'w', encoding='utf-8').write(src)
    print(f"{path}: {len(edits)} wrapped")


TR = re.compile(r"\btr\(\s*'((?:[^'\\\n]|\\.)*)'")


def missing():
    have = set()
    en = open('lib/l10n/en.dart', encoding='utf-8').read()
    for m in re.finditer(r"^\s*'((?:[^'\\\n]|\\.)*)':", en, re.M):
        have.add(m.group(1))
    seen = []
    for f in sorted(glob.glob('lib/**/*.dart', recursive=True)):
        for m in TR.finditer(open(f, encoding='utf-8').read()):
            k = m.group(1)
            if k not in have and k not in seen:
                seen.append(k)
    for k in seen:
        print(f"  '{k}': '',")
    print(len(seen), 'missing', file=sys.stderr)


if __name__ == '__main__':
    if sys.argv[1:] == ['--missing']:
        missing()
    else:
        for p in sys.argv[1:]:
            wrap_file(p)
