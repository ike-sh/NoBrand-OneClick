#!/usr/bin/env python3
"""Keep rc.4 freeze tests meaningful by running against their exact historical tree."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
BASE='d409f313519674da78bc80dd9dac573ad152c24b'
with tempfile.TemporaryDirectory(prefix='nb-historical-') as d:
    root=Path(d)
    gitdir=subprocess.check_output(['git','rev-parse','--absolute-git-dir'],cwd=ROOT,text=True).strip()
    source=subprocess.Popen(['git','archive',BASE],cwd=ROOT,stdout=subprocess.PIPE)
    subprocess.run(['tar','-x','-C',str(root)],stdin=source.stdout,check=True)
    source.stdout.close()
    if source.wait(): raise SystemExit('historical archive failed')
    (root/'.git').write_text('gitdir: '+gitdir+'\n')
    print('[RUN] retained rc.4 freeze/diagnostics tests on historical commit '+BASE,flush=True)
    result=subprocess.run(['python3',str(root/'tests/helpers/test_splicore_qualification.py')],cwd=root,
                          env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1'))
    raise SystemExit(result.returncode)
