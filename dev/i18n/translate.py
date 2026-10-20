"""Translate Russian config/script files to English using en.py + en_scripts.py.

Usage: python -I translate.py <source file> <output file>     translate one file
       python -I translate.py --check                           only validate the dictionaries

Every Russian span (spans.py) must have a translation or be in KEEP; otherwise nothing is written.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spans import SPAN, tokens  # noqa: E402
import en  # noqa: E402
import en_scripts  # noqa: E402

B = chr(92)
EN = dict(en.EN)
for k, v in en_scripts.EN.items():
    if k in EN and EN[k] != v:
        raise SystemExit(f'conflicting translations for: {k}')
    EN[k] = v
KEEP = en.KEEP
CYR = re.compile('[А-Яа-яЁё]')
SUBEXPR = re.compile(re.escape('$(') + '[^ «»“”]*')   # $(...) code islands must survive word for word


def problems(ru, tr):
    out = []
    for ch in ("'", '"', '`', B):
        if ch in tr:
            out.append(f'forbidden character {ch!r}')
    if CYR.search(tr):
        out.append('Cyrillic left in the translation')
    if tokens(ru) != tokens(tr):
        out.append(f'tokens differ: {tokens(ru)} vs {tokens(tr)}')
    for isl in SUBEXPR.findall(ru):
        if isl not in tr:
            out.append(f'code island lost: {isl}')
    for a, b in ('()', '[]', '{}'):
        if (ru.count(a), ru.count(b)) != (tr.count(a), tr.count(b)):
            out.append(f'bracket count differs for {a}{b}')
    if ru.endswith(' ') != tr.endswith(' ') or ru.startswith(' ') != tr.startswith(' '):
        out.append('leading/trailing space differs')
    return out


def check():
    bad = 0
    for ru, tr in EN.items():
        for p in problems(ru, tr):
            print(f'  {ru!r}: {p}')
            bad += 1
    return bad


def translate(text):
    missing = []

    def sub(m):
        s = m.group()
        if s in KEEP:
            return s
        if s not in EN:
            missing.append(s)
            return s
        return EN[s]

    out = SPAN.sub(sub, text)
    # Russian quotes outside the translated spans -> English ones
    out = out.replace('«', '“').replace('»', '”').replace('45-th second', '45th second')
    left = [m.group() for m in SPAN.finditer(out) if m.group() not in KEEP]
    return out, missing, left


if __name__ == '__main__':
    if sys.argv[1] == '--check':
        n = check()
        print('dictionary entries:', len(EN), 'problems:', n)
        sys.exit(1 if n else 0)
    src, dst = sys.argv[1], sys.argv[2]
    raw = open(src, 'rb').read()
    bom = raw.startswith(b'\xef\xbb\xbf')
    text = raw.decode('utf-8-sig')
    out, missing, left = translate(text)
    if missing or left:
        for s in sorted(set(missing)):
            print('  missing:', repr(s))
        for s in sorted(set(left) - set(missing)):
            print('  left:', repr(s))
        raise SystemExit(f'{src}: {len(set(missing))} untranslated spans')
    if dst.lower().endswith('.ps1'):
        # PowerShell treats “ ” as ordinary double quotes - inside strings they would end the string
        out = out.replace('“', '‹').replace('”', '›')
    open(dst, 'wb').write((b'\xef\xbb\xbf' if bom else b'') + out.encode('utf-8'))
