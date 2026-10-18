#!/usr/bin/env python3
"""FEAT-07/DOC-06: extracts ```dart blocks from docs and writes analyzable files.

Usage: snippets.py <out_dir> <markdown files...>
Each snippet becomes <out_dir>/s<NNN>.dart; an index maps file:line -> snippet file.
"""
import os, re, sys

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
index = []
n = 0
TOP = re.compile(r'^(import |export |part |library|class |abstract |sealed |final class|base class|mixin |enum |typedef |extension |void main|Future<void> main|@)', re.M)
for md in sys.argv[2:]:
    text = open(md).read()
    for m in re.finditer(r'```dart\n(.*?)```', text, re.S):
        n += 1
        line = text[:m.start()].count('\n') + 1
        code = m.group(1)
        imports = [l for l in code.split('\n') if l.startswith('import ')]
        body = '\n'.join(l for l in code.split('\n') if not l.startswith('import '))
        head = ["// ignore_for_file: type=lint, unused_local_variable, unused_import, unused_element",
                "import 'dart:async';",
                "import 'package:flutter/material.dart';",
                "import 'package:trooper_bloc/trooper_bloc.dart';",
                "import 'package:trooper_bloc/testing.dart';"] + imports
        if TOP.search(body):
            src = '\n'.join(head) + '\n' + body
        else:
            src = '\n'.join(head) + '\nFuture<void> _snippet() async {\n' + body + '\n}\n'
        name = f's{n:03d}.dart'
        open(os.path.join(out, name), 'w').write(src)
        index.append(f'{name}\t{md}:{line}')
open(os.path.join(out, 'INDEX.tsv'), 'w').write('\n'.join(index) + '\n')
print(n)
