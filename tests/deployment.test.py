#!/usr/bin/env python3
"""Permanent deterministic regressions for QA-001/002/003/008; /tmp only."""
import hashlib
import fcntl
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
REAL = {n: shutil.which(n) for n in ['git', 'ln', 'mv', 'cmp', 'mktemp', 'chmod']}
REAL['gen_candidate'] = str(PROJECT / 'scripts/gen_candidate')
count = 0

def run(args, env=None, fds=()):
    r = subprocess.run([str(a) for a in args], env=env, pass_fds=fds,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=45)
    return r.returncode, r.stdout

def snapshot(root):
    result = {}
    for f in sorted(root.rglob('*')):
        key = str(f.relative_to(root))
        if '.git' in f.relative_to(root).parts: continue
        result[key] = ('link', os.readlink(f)) if f.is_symlink() else ('dir',) if f.is_dir() else ('file', hashlib.sha256(f.read_bytes()).hexdigest())
    return result

class Case:
    def __init__(self, parent, name):
        self.base = parent / name; self.base.mkdir()
        self.project = self.base / 'project'; self.project.mkdir()
        for folder in ['scripts', 'tests', 'src', 'patches']:
            shutil.copytree(PROJECT / folder, self.project / folder, ignore=shutil.ignore_patterns('__pycache__'))
        for name in ['AGENTS.md', 'REQUIREMENTS.md', 'README.md', 'CHANGELOG.md', 'ambxst-shortcuts-overlay.code-workspace']:
            shutil.copy2(PROJECT / name, self.project / name)
        self.target = self.base / 'target'; self.target.mkdir()
        self.outside = self.base / 'outside'; self.outside.mkdir()
        (self.outside / 'sentinel').write_text('untouched\n')
        # Same patch-preimage fixture contract as transactional-scripts.test.sh.
        files = {}; current = None; active = False
        for line in (PROJECT / 'patches/ambxst-integration.patch').read_text().splitlines():
            if line.startswith('diff --git '): current = line.split()[2][2:]; files[current] = []; active = False
            elif line.startswith('@@ '):
                start = int(line.split()[1][1:].split(',')[0]); active = True
                while len(files[current]) < start - 1: files[current].append('// fixture padding')
            elif active and line[:1] in [' ', '-']: files[current].append(line[1:])
        for name, lines in files.items():
            f = self.target / name; f.parent.mkdir(parents=True, exist_ok=True); f.write_text('\n'.join(lines)+'\n')
        (self.target / 'modules/widgets').mkdir()
        assert run([REAL['git'], '-C', self.target, 'init', '-q'])[0] == 0
        self.marker = self.base / 'race-fired'
        binary = self.base / 'bin'; binary.mkdir()
        for name in REAL:
            shutil.copy2(PROJECT / 'tests/fixtures/race-wrapper.py', binary / name)
            (binary / name).chmod(0o755)
        self.env = os.environ.copy()
        self.env.update({'PATH':str(binary)+os.pathsep+self.env['PATH'], 'RACE_TARGET':str(self.target),
                         'RACE_OUTSIDE':str(self.outside), 'RACE_MARKER':str(self.marker),
                         **{'RACE_REAL_'+k.upper():v for k,v in REAL.items()}})
        self.clean = snapshot(self.target)
        self.outside_clean = snapshot(self.outside)

    def command(self, script, mode='', fds=()):
        env = self.env.copy(); env['RACE_MODE'] = mode
        return run([self.project / 'scripts' / script, self.target], env, fds)

    def install(self):
        rc, log = self.command('install.sh'); assert rc == 0, log

    def fail_final_verify(self):
        # Actual verify still runs, including all its checks, before injection.
        real = self.project / 'scripts/verify-real.sh'
        (self.project / 'scripts/verify.sh').rename(real)
        state = self.base / 'verify-count'
        wrapper = self.project / 'scripts/verify.sh'
        wrapper.write_text('#!/usr/bin/env bash\nset -eu\n' +
                           '"$(dirname -- "$0")/verify-real.sh" "$@"\n' +
                           f'count=0; [[ ! -f "{state}" ]] || read -r count < "{state}"\n' +
                           f'count=$((count+1)); printf "%s\\n" "$count" > "{state}"\n' +
                           'if ((count==2)); then printf "Final verify failure injected\\n" >&2; exit 97; fi\n')
        wrapper.chmod(0o755)

    def check_outside(self):
        assert snapshot(self.outside) == self.outside_clean, 'write escaped the target'

    def check_retired(self):
        current = snapshot(self.target)
        assert all(current.get(k) == v for k,v in self.clean.items()), 'original tree changed'
        extras = set(current) - set(self.clean)
        assert all(k == '.ambxst-shortcuts-recovery' or k.startswith('.ambxst-shortcuts-recovery/') for k in extras), extras
        assert all(current[k][0] != 'link' for k in extras)

def passed(name):
    global count
    count += 1; print(f'ok {count} - {name}', flush=True)

with tempfile.TemporaryDirectory(prefix='ambxst-regression-', dir='/tmp') as directory:
    base = Path(directory)
    case = Case(base, 'cooperative-lock')
    fd = os.open(case.target, os.O_RDONLY | os.O_DIRECTORY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for script in ['install.sh','uninstall.sh']:
            rc, log = case.command(script)
            assert rc != 0 and 'otro despliegue' in log, log
            assert snapshot(case.target) == case.clean
    finally: os.close(fd)
    case.check_outside(); passed('cooperating deployments refuse a held root lock without writes')
    case = Case(base, 'cycle')
    for script in ['verify.sh','install.sh','verify.sh','install.sh','uninstall.sh','verify.sh','uninstall.sh']:
        rc, log = case.command(script); assert rc == 0, log
    case.check_retired(); case.check_outside()
    recovery = case.target / '.ambxst-shortcuts-recovery'
    assert len(list(recovery.glob('install.*'))) == 1 and len(list(recovery.glob('uninstall.*'))) == 1
    passed('cycle is idempotent; only documented durable recovery remains')

    for filename in ['ShortcutsOverlay.qml','ShortcutData.js']:
        for timing in ['last-cmp','after-exit']:
            case = Case(base, 'fd-'+filename+'-'+timing); case.install()
            original = case.target / 'modules/widgets/shortcuts' / filename
            fd = os.open(original, os.O_RDWR)
            try:
                case.env.update({'RACE_FD':str(fd),'RACE_FILE':filename})
                rc, log = case.command('uninstall.sh', 'fd-late' if timing == 'last-cmp' else '', (fd,))
                assert rc == 0, log
                if timing == 'last-cmp': assert case.marker.exists(), 'injection never ran'
                else:
                    os.lseek(fd,0,0); os.write(fd,b'edit after process exit\n'); os.ftruncate(fd,24)
                paths = list((case.target / '.ambxst-shortcuts-recovery').glob('uninstall.*/'+filename))
                assert len(paths) == 1 and os.stat(paths[0]).st_ino == os.fstat(fd).st_ino
                os.lseek(fd,0,0); assert paths[0].read_bytes() == os.read(fd,100000)
                assert os.fstat(fd).st_nlink >= 1
                case.check_retired(); case.check_outside()
            finally: os.close(fd)
            passed(f'QA-001 {filename}: edit {timing} remains reachable')

    for kind in ['symlink','directory','fifo','socket','device']:
        case = Case(base, 'staging-'+kind)
        if kind == 'symlink':
            (case.outside / 'VICTIM').write_text('sentinel\n')
            case.outside_clean = snapshot(case.outside)
        rc, log = case.command('install.sh', 'staging-'+kind)
        if kind == 'device' and not case.marker.exists():
            passed('staging-device: mknod denied, injection skipped')
            continue
        assert rc != 0, log
        assert case.marker.exists(), f'injection never ran for staging-{kind}'
        assert not (case.target / 'modules/widgets/shortcuts/ShortcutsOverlay.qml').exists(), log
        assert not (case.target / 'modules/widgets/shortcuts/ShortcutData.js').exists(), log
        case.check_outside()
        candidates = list((case.target / '.ambxst-shortcuts-recovery').glob('install.*/.ShortcutsOverlay.qml.install.*'))
        assert len(candidates) == 1, candidates
        if kind == 'symlink':
            assert candidates[0].is_symlink(), candidates
            assert (case.outside / 'VICTIM').read_bytes() == b'sentinel\n'
        elif kind == 'directory':
            assert candidates[0].is_dir() and not list(candidates[0].iterdir()), candidates
        elif kind == 'fifo':
            assert stat.S_ISFIFO(os.stat(candidates[0]).st_mode), candidates
        elif kind == 'socket':
            assert stat.S_ISSOCK(os.stat(candidates[0]).st_mode), candidates
        passed(f'CR-001 staging-{kind}: create->open swap aborts with zero writes')

    case = Case(base, 'staging-regular-replacement')
    rc, log = case.command('install.sh', 'staging-regular-replacement')
    assert rc != 0, log
    assert case.marker.exists(), 'injection never ran for staging-regular-replacement'
    identity = dict(line.split('=', 1) for line in case.marker.read_text().splitlines() if '=' in line)
    assert 'replacement-a' in identity and 'replacement-b' in identity, identity
    assert identity['replacement-a'] != identity['replacement-b'], 'swap did not change the inode'
    b_dev, b_ino = (int(v) for v in identity['replacement-b'].split())
    candidates = list((case.target / '.ambxst-shortcuts-recovery').glob('install.*/.ShortcutsOverlay.qml.install.*'))
    assert len(candidates) == 1, candidates
    assert candidates[0].read_text() == 'sentinel\n', 'concurrent regular file was overwritten'
    assert os.stat(candidates[0]).st_dev == b_dev and os.stat(candidates[0]).st_ino == b_ino, 'candidate is not the concurrent inode'
    assert not (case.target / 'modules/widgets/shortcuts/ShortcutsOverlay.qml').exists(), 'overlay got published from the swap'
    assert not (case.target / 'modules/widgets/shortcuts/ShortcutData.js').exists(), log
    case.check_outside()
    passed('CR-001 staging-regular-replacement: a new regular inode at the name aborts and stays intact')

    case = Case(base, 'staging-prepfail')
    rc, log = case.command('install.sh', 'staging-prepfail')
    assert rc != 0 and case.marker.exists(), log
    assert not (case.target / 'modules/widgets/shortcuts/ShortcutsOverlay.qml').exists(), log
    case.check_outside()
    recovery = case.target / '.ambxst-shortcuts-recovery'
    candidates = list(recovery.glob('install.*/.ShortcutsOverlay.qml.install.*'))
    assert len(candidates) == 1, candidates
    assert not list(recovery.glob('install.*/ShortcutsOverlay.qml')), 'partial staging was published'
    prepared = (case.project / 'src/modules/widgets/shortcuts/ShortcutsOverlay.qml').read_bytes()
    assert candidates[0].read_bytes() == prepared, 'prepared content not preserved'
    assert stat.S_IMODE(os.stat(candidates[0]).st_mode) != 0o644
    passed('CR-001 staging-prepfail: a failed preparation aborts without publishing')

    case = Case(base, 'staging-identity')
    case.install()
    overlay = case.target / 'modules/widgets/shortcuts'
    staged_roots = list((case.target / '.ambxst-shortcuts-recovery').glob('install.*'))
    assert len(staged_roots) == 1
    for fname in ['ShortcutsOverlay.qml','ShortcutData.js']:
        published = os.stat(overlay / fname)
        prepared = os.stat(staged_roots[0] / fname)
        canonical = os.stat(case.project / 'src/modules/widgets/shortcuts' / fname)
        assert (published.st_dev, published.st_ino) == (prepared.st_dev, prepared.st_ino), fname
        assert (published.st_dev, published.st_ino) != (canonical.st_dev, canonical.st_ino), fname
        assert stat.S_IMODE(published.st_mode) == 0o644, (fname, oct(published.st_mode))
        assert published.st_nlink == 2, fname
        assert (overlay / fname).read_bytes() == (case.project / 'src/modules/widgets/shortcuts' / fname).read_bytes()
    strays = [p for p in case.target.rglob('*')
              if '.ambxst-shortcuts-recovery' not in p.parts
              and ('.install.' in p.name or p.name.startswith('.ambxst-shortcuts-'))]
    assert strays == [], strays
    case.check_outside()
    passed('CR-001 staging preserves device+inode identity and mode to published')

    for operation in ['publish','restore']:
        for kind in ['directory','symlink','regular']:
            mode = operation+'-'+kind; case = Case(base, mode)
            if operation == 'restore': case.install(); case.fail_final_verify()
            rc, log = case.command('install.sh' if operation == 'publish' else 'uninstall.sh', mode)
            assert rc != 0 and case.marker.exists(), log
            destination = case.target / 'modules/widgets/shortcuts/ShortcutsOverlay.qml'
            if kind == 'directory': assert destination.is_dir() and not list(destination.iterdir())
            elif kind == 'symlink': assert destination.is_symlink() and destination.resolve() == case.outside
            else: assert destination.read_text() == 'concurrent destination\n'
            case.check_outside()
            if operation == 'restore':
                paths = list((case.target / '.ambxst-shortcuts-recovery').glob('uninstall.*/ShortcutsOverlay.qml'))
                assert len(paths) == 1 and paths[0].read_bytes() == (PROJECT / 'src/modules/widgets/shortcuts/ShortcutsOverlay.qml').read_bytes()
                assert str(paths[0]) in log and 'rollback incompleto' in log
            passed(f'QA-002 {mode}: concurrent destination preserved, real ln rejects')

    for mode in ['swap-widgets','swap-shortcuts','swap-modules','swap-services']:
        case = Case(base,mode)
        if mode in ['swap-modules','swap-services']:
            # A valid outside preimage proves rejection is not just a missing file.
            shutil.copytree(case.target / ('modules' if mode == 'swap-modules' else 'modules/services'), case.outside, dirs_exist_ok=True)
            case.outside_clean = snapshot(case.outside)
        rc, log = case.command('install.sh',mode)
        assert rc != 0 and case.marker.exists(), log
        case.check_outside()
        assert 'Recuperación manual' in log or 'recuperación manual' in log, log
        passed(f'QA-003 {mode}: anchored operation does not follow replacement')

    for component in ['modules','modules/services','modules/widgets','modules/widgets/shortcuts','.ambxst-shortcuts-recovery']:
        for dangling in [False,True]:
            case = Case(base,'static-'+component.replace('/','-')+str(dangling))
            path = case.target / component
            if path.exists(): shutil.move(path, case.base / 'saved')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(case.outside / 'missing' if dangling else case.outside, target_is_directory=True)
            before = snapshot(case.target)
            for script in ['verify.sh','install.sh','uninstall.sh']:
                rc, log = case.command(script); assert rc != 0, log
                assert snapshot(case.target) == before
            case.check_outside(); passed(f'QA-003/008 rejects {component}, dangling={dangling}')

    for kind in ['symlink','dangling','directory','partial']:
        case = Case(base,'file-kind-'+kind); case.install()
        path = case.target / 'modules/widgets/shortcuts/ShortcutsOverlay.qml'; path.unlink()
        if kind == 'symlink': path.symlink_to(PROJECT / 'src/modules/widgets/shortcuts/ShortcutsOverlay.qml')
        elif kind == 'dangling': path.symlink_to(case.outside / 'missing')
        elif kind == 'directory': path.mkdir()
        before = snapshot(case.target)
        for script in ['verify.sh','install.sh','uninstall.sh']:
            rc, log = case.command(script); assert rc != 0, log
            assert snapshot(case.target) == before
        case.check_outside(); passed(f'QA-008 all entrypoints reject file {kind}')

print(f'OK: {count} deployment regressions; all mutations used /tmp.')
