#!/usr/bin/env python3
"""Replay original QA command-boundary attacks with v0.1.1 path layout.
Historical files are read only. No old assertions are weakened in place.
"""
from pathlib import Path
import json, os, shutil
historical = Path(__file__).resolve().parents[1] / 'v0.1.0/shell-audit.py'
source = historical.read_text().split('# Existing fixtures plus independently checked failure points')[0]
# Path aliases and durable recovery are deliberate implementation changes.
source = source.replace("src=a[-2] if len(a)>1 else ''; last=a[-1] if a else ''", "src=os.path.realpath(a[-2]) if len(a)>1 else ''; last=os.path.realpath(a[-1]) if a else ''")
source = source.replace("'.install.' in src", "'/install.' in src")
source = source.replace('/.ambxst-shortcuts-uninstall.', '/.ambxst-shortcuts-recovery/uninstall.')
source = source.replace("for name in names:\n        f=dest/name", "for name in names + (['tests/hardening.test.js'] if full else []):\n        f=dest/name")
namespace={'__file__':str(historical),'__name__':'historical_replay'}
exec(compile(source,str(historical),'exec'),namespace)
new_case, command = namespace['new_case'], namespace['command']
results=[]
try:
    for name in ['publish-directory','publish-link','fd-write-uninstall-final','restore-directory','restore-link','modify-before-move']:
        full = name in ['publish-directory','publish-link','fd-write-uninstall-final']
        case, project, target, env = new_case('replay-'+name,full=full)
        fd=None
        if not name.startswith('publish'):
            assert command(project,target,env,'install.sh')['exit']==0
        if name=='fd-write-uninstall-final':
            fd=os.open(target/'modules/widgets/shortcuts/ShortcutsOverlay.qml',os.O_RDWR)
        try:
            result=command(project,target,env,'install.sh' if name.startswith('publish') else 'uninstall.sh',
                mode=name,verify='fail-final' if name.startswith('restore') else 'pass',fd=fd)
            assert list((case/'outside').iterdir()) == [case/'outside/sentinel']
            assert (case/'outside/sentinel').read_text()=='unrelated content\n'
            if fd is not None:
                assert result['exit']==0 and (case/'fired-cmp').exists(),result
                os.lseek(fd,0,0); value=os.read(fd,200)
                assert value==b'concurrent user edit through open fd\n'
                retained=list((target/'.ambxst-shortcuts-recovery').glob('uninstall.*/ShortcutsOverlay.qml'))
                assert len(retained)==1 and retained[0].read_bytes()==value
                assert retained[0].stat().st_ino==os.fstat(fd).st_ino and os.fstat(fd).st_nlink>=1
                result.update(retained_inode_links=os.fstat(fd).st_nlink,retained_content=value.decode())
            else:
                assert result['exit']!=0,result
                marker=case/('fired-mv' if name=='modify-before-move' else 'fired-ln')
                assert marker.exists(),'Original injection did not fire'
                path=target/'modules/widgets/shortcuts/ShortcutsOverlay.qml'
                if name.endswith('directory'): assert path.is_dir() and not list(path.iterdir())
                elif name.endswith('link'): assert path.is_symlink() and path.resolve()==case/'outside'
                else: assert (target/'modules/widgets/shortcuts/ShortcutData.js').read_text()=='concurrent user data\n'
            results.append({'original_case':name,'real_verify':full,'regression':'PASS','result':result})
        finally:
            if fd is not None: os.close(fd)
    print(json.dumps({'passed':len(results),'adaptations':['physical proc-fd aliases','durable recovery paths','include new pure parser test in full fixture'], 'cases':results},indent=2))
finally:
    shutil.rmtree(namespace['TEMP'])
