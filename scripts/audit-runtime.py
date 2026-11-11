#!/usr/bin/env python3
"""Fail closed on new external Xray server deployment in release inputs."""
import argparse
from pathlib import Path
import re

RULES = {
 'xray-release-download': r'(?i)(?:XTLS[/]Xray-core[/]releases|Xray-linux[^\s\x22\x27]*\.(?:zip|tar))',
 'xray-server-operation': r'(?i)\b(?:[A-Za-z_]*?(?:download|install|upgrade|start|restart|fallback)[A-Za-z_]*xray[A-Za-z_]*|[A-Za-z_]*xray[A-Za-z_]*(?:download|install|upgrade|start|restart|fallback)[A-Za-z_]*)\s*(?:\(|\s|$)',
 'xray-execution': r'(?im)^\s*(?:exec\s+|command\s+|[^\n]*[=;]\s*)?(?:[\x22\x27]?\$\{?NOBRAND_XRAY_BIN\}?|[\x22\x27]?[^\s\x22\x27]*/xray|xray)\b[^\n]*(?:run|version|start|test)',
 'xray-python-execution': r'(?i)(?:subprocess\.(?:Popen|run|call)|os\.exec[a-z]*)\([^\n]*[\x22\x27](?:[^\x22\x27]*/)?xray[\x22\x27]',
 'xray-service': r'(?i)(?:ExecStart|command|command_args)\s*=[^\n]*(?:XRAY|/xray\b)',
}


def violations(root):
    paths = sorted((root/'src').glob('*.sh')) + sorted((root/'runtime').glob('*.py'))
    paths += [p for pattern in ('*.sh','*.py') for p in (root/'scripts').glob(pattern) if p.name != 'audit-runtime.py']
    paths += [root/'install-nobrand.sh', root/'dist/install-nobrand.sh']
    found=[]
    for path in paths:
        if not path.is_file() or path.is_symlink():
            found.append((str(path.relative_to(root)), 0, 'unsafe-or-missing-release-input'));continue
        text=path.read_text()
        for rule, pattern in RULES.items():
            for match in re.finditer(pattern,text):
                found.append((str(path.relative_to(root)),text.count('\n',0,match.start())+1,rule))
    return found


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    args=parser.parse_args()
    bad=violations(args.root)
    for path,line,rule in bad: print(f'[FAIL] {rule}: {path}:{line}')
    if not bad: print('[PASS] all production proxies use Splicore; external Xray server operations=0')
    return 1 if bad else 0

if __name__=='__main__': raise SystemExit(main())
