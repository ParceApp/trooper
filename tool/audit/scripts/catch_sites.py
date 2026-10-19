#!/usr/bin/env python3
"""ERR-02 inventory: classifies every catch/catchError/.ignore() site in packages/*/lib."""
import collections, glob, re

def block_after(lines, i, col):
    """Returns the lines of the block that opens after column `col` on line i."""
    depth, body, started = 0, [], False
    for j in range(i, min(i + 40, len(lines))):
        t = lines[j][col:] if j == i else lines[j]
        for ch in t:
            if ch == '{': depth += 1; started = True
            elif ch == '}': depth -= 1
        body.append(t)
        if started and depth <= 0: break
    return body

def classify(b):
    code = [x.strip() for x in b if x.strip() and not x.strip().startswith('//')]
    text = '\n'.join(code)
    inner = re.sub(r'^.*?\{', '', text, count=1, flags=re.S).rsplit('}', 1)[0].strip()
    if re.search(r'\brethrow\b|\bthrow\b', text): return 'rethrow/throw'
    if re.search(r'emitError|completeError|addError|\.emit\(DataError|staleData', text): return '→ State'
    if re.search(r'telemetry\.emit|reportPersistenceError|discardStored', text): return '→ Telemetrie'
    if re.search(r'onSourceException|onAnyError|onError\?*\.call|reportError', text): return '→ Callback'
    if not inner or re.fullmatch(r'(return( null| false| true)?;|break;|continue;)?', inner): return 'verschluckt'
    if re.fullmatch(r'(storage\.delete\([^;]*\)\.ignore\(\);\s*)+', inner): return 'verschluckt (löscht L2-Eintrag)'
    return 'andere Behandlung'

rows = []
for f in sorted(glob.glob('packages/trooper*/lib/**/*.dart', recursive=True)):
    L = open(f).read().split('\n')
    for i, l in enumerate(L):
        s = l.strip()
        if s.startswith('//'): continue
        m = re.search(r'\bcatch\s*\(|catchError\(', l)
        if m:
            rows.append((f, i + 1, s[:90], classify(block_after(L, i, m.start()))))
        elif '.ignore()' in l:
            if re.search(r'storage\.(delete|write|clear)', l): c = 'verschluckt (Storage-Future)'
            elif re.search(r'result\.ignore', l): c = 'verschluckt (async Side-Effect)'
            elif re.search(r'cancel\(\)\.ignore', l): c = 'unkritisch (cancel)'
            else: c = '→ State (Fehler landet im Stream)'
            rows.append((f, i + 1, s[:90], c))

cnt = collections.Counter(r[3] for r in rows)
with open('docs/audit/raw/catch_sites.md', 'w') as o:
    o.write('# catch-, catchError- und .ignore()-Stellen (ERR-02)\n\n'
            'Erzeugt mit `tool/audit/scripts/catch_sites.py`; Stellen der Klasse „verschluckt“ manuell geprüft.\n\n')
    o.write('| Klasse | Anzahl |\n|---|---|\n' + ''.join(f'| {k} | {v} |\n' for k, v in cnt.most_common()) + '\n')
    o.write('| Ort | Code | Klasse |\n|---|---|---|\n')
    for f, n, s, c in rows:
        o.write(f"| `{f.replace('packages/', '')}:{n}` | `{s.replace('|', '¦')}` | {c} |\n")
print(len(rows), cnt.most_common())
for r in rows:
    if r[3].startswith('verschluckt') or r[3] == 'andere Behandlung':
        print(f"{r[0].replace('packages/', '')}:{r[1]} | {r[2][:60]} | {r[3]}")
