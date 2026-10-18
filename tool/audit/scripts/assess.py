#!/usr/bin/env python3
"""Edits docs/audit/criteria.yaml without reformatting it.

  assess.py set <CRITERION> <met|partial|not_met|na> [--ci] [--evidence E] [--note N] [--findings F-001,F-002]
  assess.py finding <F-ID> <P0..P3> <CRITERION> <freeze:yes|no> [--closed]
"""
import argparse
import json
import re
import sys

PATH = 'docs/audit/criteria.yaml'


def q(value):
    return json.dumps(value, ensure_ascii=False)


def set_criterion(text, a):
    pattern = re.compile(
        r'(      - id: ' + re.escape(a.id) + r'\n        priority: [MSC]\n)'
        r'        status: .*\n        automated_in_ci: .*\n        evidence: .*\n'
        r'        findings: .*\n(        note: .*\n)?')
    if not pattern.search(text):
        sys.exit(f'criterion not found: {a.id}')
    findings = [f for f in (a.findings or '').split(',') if f]
    block = (f'        status: {a.status}\n'
             f'        automated_in_ci: {"true" if a.ci else "false"}\n'
             f'        evidence: {q(a.evidence) if a.evidence else "null"}\n'
             f'        findings: [{", ".join(findings)}]\n')
    if a.note:
        block += f'        note: {q(a.note)}\n'
    return pattern.sub(lambda m: m.group(1) + block, text, count=1)


def add_finding(text, a):
    if re.search(r'^  - id: ' + re.escape(a.id) + r'$', text, re.M):
        sys.exit(f'finding exists: {a.id}')
    entry = (f'  - id: {a.id}\n    severity: {a.severity}\n    criterion: {a.criterion}\n'
             f'    freeze_relevant: {"true" if a.freeze == "yes" else "false"}\n'
             f'    status: {"closed" if a.closed else "open"}\n')
    if text.rstrip().endswith('findings: []'):
        return text.rstrip()[:-2].rstrip() + '\n' + entry
    return text.rstrip('\n') + '\n' + entry


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('set')
    s.add_argument('id')
    s.add_argument('status', choices=['met', 'partial', 'not_met', 'na'])
    s.add_argument('--ci', action='store_true')
    s.add_argument('--evidence')
    s.add_argument('--note')
    s.add_argument('--findings')
    f = sub.add_parser('finding')
    f.add_argument('id')
    f.add_argument('severity', choices=['P0', 'P1', 'P2', 'P3'])
    f.add_argument('criterion')
    f.add_argument('freeze', choices=['yes', 'no'])
    f.add_argument('--closed', action='store_true')
    a = p.parse_args()
    text = open(PATH, encoding='utf-8').read()
    text = set_criterion(text, a) if a.cmd == 'set' else add_finding(text, a)
    open(PATH, 'w', encoding='utf-8').write(text)


if __name__ == '__main__':
    main()
