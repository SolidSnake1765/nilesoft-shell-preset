"""Static checks for Nilesoft Shell .nss files.

Usage: python -I nss_check.py <nilesoft dir>
Checks every imported file (and shell.nss): balanced (), {}, [] outside strings and comments,
unterminated strings, raw private-use glyph chars, @variables used inside strings that are
never declared, and literal program paths that do not exist.
"""
import os
import re
import sys

root = sys.argv[1]
shell = os.path.join(root, 'shell.nss')
imports = re.findall(r"^import\s+'([^']+)'", open(shell, encoding='utf-8-sig').read(), re.M)
files = [shell] + [os.path.join(root, p) for p in imports]

BUILTIN = {'sel', 'sys', 'app', 'user', 'path', 'str', 'io', 'reg', 'key', 'keys', 'wnd', 'window', 'this', 'msg', 'image', 'icon',
           'title', 'command', 'input', 'id', 'if', 'quote', 'package', 'color', 'regex', 'ini', 'len', 'eval', 'for', 'theme', 'tip',
           'mode', 'type', 'vis', 'sep', 'separator', 'menu', 'item', 'null', 'true', 'false', 'clipboard', 'env', 'char', 'cmd',
           'invoke', 'admin', 'pos', 'where', 'find', 'args', 'arg', 'expanded', 'checked', 'keys', 'image', 'tip', 'window',
           'sleep', 'shell', 'nil', 'print', 'auto', 'aliases', 'inherit', 'label'}


def scan(text):
    """Yield (kind, value, line) for strings and code chars; kinds: str, code."""
    i, n, line = 0, len(text), 1
    while i < n:
        c = text[i]
        if c == '\n':
            line += 1
        if text.startswith('//', i):
            j = text.find('\n', i)
            i = n if j < 0 else j
            continue
        if text.startswith('/*', i):
            j = text.find('*/', i + 2)
            if j < 0:
                yield ('err', 'unterminated /* comment', line)
                return
            line += text.count('\n', i, j)
            i = j + 2
            continue
        if c in ("'", '"', '`'):
            j = i + 1
            while j < n and text[j] != c:
                if c == '"' and text[j] == chr(92):
                    j += 1
                j += 1
            if j >= n:
                yield ('err', f'unterminated {c} string', line)
                return
            s = text[i + 1:j]
            yield ('str', s, line)
            line += s.count('\n')
            i = j + 1
            continue
        yield ('code', c, line)
        i += 1


declared = set()
texts = {}
for f in files:
    t = open(f, encoding='utf-8-sig').read()
    texts[f] = t
    declared |= set(re.findall(r'\$([A-Za-z_][A-Za-z0-9_]*)\s*=', t))

problems = 0
for f in files:
    t = texts[f]
    name = os.path.relpath(f, root)
    stack = []
    pairs = {')': '(', '}': '{', ']': '['}
    for kind, val, line in scan(t):
        if kind == 'err':
            print(f'{name}:{line}: {val}'); problems += 1
        elif kind == 'code':
            if val in '({[':
                stack.append((val, line))
            elif val in ')}]':
                if not stack or stack[-1][0] != pairs[val]:
                    print(f'{name}:{line}: unexpected {val!r}'); problems += 1
                else:
                    stack.pop()
        elif kind == 'str':
            for var in re.findall(r'@([A-Za-z_][A-Za-z0-9_]*)', val):
                if var not in declared and var not in BUILTIN and not var.startswith('ff_') is False:
                    pass
                if var not in declared and var not in BUILTIN:
                    print(f'{name}:{line}: @{var} used in a string but never declared'); problems += 1
            m = re.match(r'^([A-Za-z]:' + re.escape(chr(92)) + r'[^"*?<>|@]+' + r'\.(exe|dll|msc))$', val, re.I)
            if m and not os.path.exists(val):
                print(f'{name}:{line}: path does not exist: {val}'); problems += 1
    for c, line in stack:
        print(f'{name}:{line}: unclosed {c!r}'); problems += 1
    glyph = [i + 1 for i, l in enumerate(t.splitlines()) if any(0xE000 <= ord(ch) <= 0xF8FF for ch in l)]
    if glyph:
        print(f'{name}: raw glyph characters on lines {glyph}'); problems += 1
    # bare variable references in expressions, e.g. image=ev_exe, find=ff_video
    code_only = '\n'.join(l for l in t.splitlines() if not l.lstrip().startswith('//'))
    for m in re.finditer(r'(?:image|find|cmd|args|tip|title|vis|where)=([a-z_][a-z0-9_]*)\b(?![.(])', code_only):
        var = m.group(1)
        if var not in declared and var not in BUILTIN:
            ln = code_only.count('\n', 0, m.start()) + 1
            print(f'{name}:{ln}: bare identifier {var!r} is not a declared variable'); problems += 1
print('files checked:', len(files), 'problems:', problems)
