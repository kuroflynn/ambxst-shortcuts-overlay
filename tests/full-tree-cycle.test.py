#!/usr/bin/env python3
"""Full Ambxst 1.2.6 archive cycle. The supplied repository is read ONLY."""
from pathlib import Path
import io, json, os, subprocess, sys, tarfile, tempfile
project = Path(__file__).resolve().parents[1]
if len(sys.argv) != 2:
    raise SystemExit('Usage: python3 tests/full-tree-cycle.test.py /absolute/path/to/ambxst-git')
external = Path(sys.argv[1]).resolve(strict=True)
commit = subprocess.check_output(['git','-C',str(external),'rev-parse','1.2.6^{commit}'],text=True).strip()
assert commit == '54f90d63d139e410d8987d21805fac4659c1ba77'
archive = subprocess.check_output(['git','-C',str(external),'archive','1.2.6'])
def tree(root):
    result={}
    for f in root.rglob('*'):
        rel=f.relative_to(root)
        if '.git' in rel.parts: continue
        result[str(rel)] = ('link',os.readlink(f)) if f.is_symlink() else ('dir',) if f.is_dir() else ('file',f.read_bytes())
    return result
records=[]
with tempfile.TemporaryDirectory(prefix='ambxst-full-cycle-',dir='/tmp') as directory:
    target=Path(directory)/'ambxst';target.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
        stream.extractall(target,filter='data')
    subprocess.run(['git','-C',str(target),'init','-q'],check=True)
    before=tree(target)
    for script in ['verify.sh','install.sh','verify.sh','install.sh','uninstall.sh','verify.sh','uninstall.sh']:
        result=subprocess.run([str(project/'scripts'/script),str(target)],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
        records.append({'command':[script,str(target)],'exit':result.returncode,'output':result.stdout})
        assert result.returncode==0, result.stdout
    after=tree(target)
    assert all(after.get(name)==value for name,value in before.items()), 'Original bytes/type changed'
    extras=set(after)-set(before)
    recovery=target/'.ambxst-shortcuts-recovery'
    installs=list(recovery.glob('install.*'));uninstalls=list(recovery.glob('uninstall.*'))
    assert len(installs)==len(uninstalls)==1
    expected={'.ambxst-shortcuts-recovery'}
    for folder in installs+uninstalls:
        expected.add(str(folder.relative_to(target)))
        for name in ['ShortcutsOverlay.qml','ShortcutData.js']:
            f=folder/name;expected.add(str(f.relative_to(target)))
            assert not f.is_symlink() and f.read_bytes()==(project/'src/modules/widgets/shortcuts'/name).read_bytes()
    assert extras==expected, extras
    assert list(Path(directory).iterdir())==[target], 'Unexpected files outside target'
    print(json.dumps({'tag':'1.2.6','commit':commit,'original_files_byte_identical':sum(v[0]=='file' for v in before.values()),
        'cycle_steps':len(records),'documented_recovery_entries':sorted(extras),'commands':records},indent=2))
