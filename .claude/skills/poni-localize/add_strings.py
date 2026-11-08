#!/usr/bin/env python3
"""Adds English translations to Resources/en.lproj/Localizable.strings.

Usage: add_strings.py '{"Indonesian text %@": "English text %@", ...}'
Write each interpolation as %@. SwiftUI asks for %@ (text) or %lld (integers) and escapes a literal %
as %% once a string has interpolations, so every combination is written. Existing keys are left alone.
"""
import itertools, json, os, re, sys

path = os.path.join(os.path.dirname(__file__), '../../../Resources/en.lproj/Localizable.strings')

def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')

def variants(k, v):
    n = k.count('%@')
    assert v.count('%@') == n, f'placeholder count differs: {k!r} -> {v!r}'
    if n == 0:
        return [(k, v)]
    kk, vv = re.sub(r'%(?!@)', '%%', k), re.sub(r'%(?!@)', '%%', v)
    out = []
    for combo in itertools.product(['%@', '%lld'], repeat=n):
        a, b = kk, vv
        for c in combo:
            a = a.replace('%@', '\0' + c[1:], 1)
            b = b.replace('%@', '\0' + c[1:], 1)
        out.append((a.replace('\0', '%'), b.replace('\0', '%')))
    out.append((k, v))  # tr() / String(format:) on the plain form
    return out

pairs = json.loads(sys.argv[1])
text = open(path).read()
have = set(re.findall(r'^"((?:[^"\\]|\\.)*)" =', text, re.M))
added = []
for k, v in pairs.items():
    for a, b in variants(k, v):
        if esc(a) not in have:
            have.add(esc(a))
            added.append(f'"{esc(a)}" = "{esc(b)}";')
if added:
    open(path, 'a').write('\n'.join(added) + '\n')
print(f'{len(added)} entries added')
