"""Shared: find Russian text spans in source files (strings and comments alike).

Backslashes are built with chr(92) so no tool can mangle them while editing this file.
"""
import re

B = chr(92)
CYR = 'А-Яа-яЁё'
# A span starts with a Cyrillic letter and runs until a quote, backtick, backslash or line end;
# it ends on a letter, digit or closing punctuation.
STOP = "'" + '"' + '`' + B + 'n' + B + B
SPAN = re.compile('[' + CYR + '](?:[^' + STOP + ']*[' + CYR + 'A-Za-z0-9.…!?»)%:>' + B + ']])?')
# Things that must survive translation unchanged: $vars, ${vars}, @nss.vars, {0} format slots
TOKENS = re.compile(B + '$' + B + '{?[A-Za-z_][' + B + 'w:.]*' + B + '}?|@[A-Za-z_][' + B + 'w.]*|' + B + '{' + B + 'd+(?:[,:][^}]*)?' + B + '}')


def spans(text):
    return [m.group() for m in SPAN.finditer(text)]


def tokens(s):
    return sorted(TOKENS.findall(s))
