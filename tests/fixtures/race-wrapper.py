#!/usr/bin/env python3
"""Inject at real command boundaries. Always record that the race fired."""
import os
import socket
import stat
from pathlib import Path
import subprocess
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ['RACE_TARGET'])
outside = Path(os.environ['RACE_OUTSIDE'])
marker = Path(os.environ['RACE_MARKER'])
mode = os.environ.get('RACE_MODE', '')
source = Path(os.path.realpath(args[-2])) if len(args) > 1 else Path('/')
target = Path(os.path.realpath(args[-1])) if args else Path('/')
runtime = root / 'modules/widgets/shortcuts'
real = os.environ['RACE_REAL_' + name.upper()]

def execute():
    return subprocess.run([real, *args]).returncode

def fired():
    marker.write_text(f'{name}: {source} -> {target}\n')

# Plant an adversarial node at CANDIDATE for the staging injection. Returns 0
# when the injection must be counted as fired, 1 when the environment denied it
# (mknod) and the case must be skipped via the absent marker.
def plant(candidate, kind):
    if kind == 'symlink':
        victim = outside / 'VICTIM'
        victim.write_text('sentinel\n')
        candidate.unlink(missing_ok=True)
        candidate.symlink_to(victim)
        return 0
    if kind == 'directory':
        candidate.unlink(missing_ok=True)
        candidate.mkdir()
        return 0
    if kind == 'fifo':
        candidate.unlink(missing_ok=True)
        os.mkfifo(candidate)
        return 0
    if kind == 'socket':
        candidate.unlink(missing_ok=True)
        # AF_UNIX bind() rejects paths around 108 bytes; the real directory
        # behind the recovery fd already exceeds it. Bind a single-character
        # socket beside it and symlink the long candidate name onto it: the
        # product still refuses (`-L`), and the test's stat() still resolves
        # the leaf to the socket node.
        short = candidate.parent / 's'
        short.unlink(missing_ok=True)
        sock = socket.socket(socket.AF_UNIX)
        sock.bind(str(short))
        sock.close()
        candidate.symlink_to(short.name)
        return 0
    if kind == 'device':
        try:
            candidate.unlink(missing_ok=True)
            os.mknod(candidate, stat.S_IFCHR | 0o600, os.makedev(1, 3))
            return 0
        except OSError:
            candidate.write_text('')   # denied; leave a regular, skip injection
            return 1
    raise RuntimeError(kind)

# The product generates a fresh candidate name (gen_candidate prints it WITHOUT
# creating) and immediately performs an exclusive `set -C; exec {fd}> "$candidate"`
# open. Replacing the generator with a planted node, before that open, makes the
# exclusive open collide (EEXIST) on every retry and abort the install without
# the installer ever truncating or following the planted node.
if name == 'gen_candidate' and mode.startswith('staging-'):
    tx_dir = args[0]                       # /proc/<install>/fd/<n>, verbatim
    leaf = '.%s.install.cr1seed' % args[1]
    kind = mode[len('staging-'):]
    if mode == 'staging-prepfail':
        # No adversarial node: the failure is injected later at the final
        # chmod. Expose a genuinely fresh (unoccupied) candidate name.
        sys.stdout.write('%s/%s\n' % (tx_dir, leaf))
        sys.stdout.flush()
        sys.exit(0)
    already = marker.exists()
    if not already:
        real_dir = Path(os.path.realpath(tx_dir))
        planted = real_dir / leaf
        if kind == 'regular-replacement':
            # CR-001 original class: an inode A already occupies the name and a
            # concurrent actor replaces it with a brand-new regular inode B.
            planted.write_bytes(b'')
            a_ref = os.stat(planted)
            planted.unlink()
            planted.write_text('sentinel\n')
            b_ref = os.stat(planted)
            fired()
            with marker.open('a') as fh:
                fh.write('replacement-a=%d %d\n' % (a_ref.st_dev, a_ref.st_ino))
                fh.write('replacement-b=%d %d\n' % (b_ref.st_dev, b_ref.st_ino))
        elif plant(planted, kind) == 0:
            fired()
    sys.stdout.write('%s/%s\n' % (tx_dir, leaf))
    sys.stdout.flush()
    sys.exit(0)

# The final chmod is part of the single verified preparation. Failing it once
# must close the descriptor and abort before any staging is published.
if name == 'chmod' and mode == 'staging-prepfail' and not marker.exists():
    fired()
    sys.exit(71)

publishing = name == 'ln' and '/install.' in str(source) and target.parent == runtime
restoring = name == 'ln' and '/uninstall.' in str(source) and target.parent == runtime
if not marker.exists():
    if (publishing and mode.startswith('publish-')) or (restoring and mode.startswith('restore-')):
        kind = mode.split('-')[-1]
        if kind == 'directory': target.mkdir()
        elif kind == 'symlink': target.symlink_to(outside, target_is_directory=True)
        elif kind == 'regular': target.write_text('concurrent destination\n')
        else: raise RuntimeError(mode)
        fired()
    elif publishing and mode in ['swap-widgets', 'swap-shortcuts']:
        folder = runtime.parent if mode == 'swap-widgets' else runtime
        folder.rename(folder.with_name(folder.name + '.saved'))
        folder.symlink_to(outside, target_is_directory=True)
        fired()
    elif name == 'git' and mode in ['swap-modules', 'swap-services'] and 'apply' in args and '--check' not in args and '--numstat' not in args:
        folder = root / ('modules' if mode == 'swap-modules' else 'modules/services')
        folder.rename(folder.with_name(folder.name + '.saved'))
        folder.symlink_to(outside, target_is_directory=True)
        fired()
    elif name == 'cmp' and mode.startswith('fd-') and '/uninstall.' in str(target):
        wanted = os.environ.get('RACE_FILE', 'ShortcutsOverlay.qml')
        if target.name == wanted:
            counter = marker.with_suffix('.count')
            count = int(counter.read_text()) + 1 if counter.exists() else 1
            counter.write_text(str(count))
            # First comparison is after rename. Second is after final verify.
            if count == 2:
                rc = execute()
                if rc == 0:
                    fd = int(os.environ['RACE_FD'])
                    value = b'late concurrent edit through retained FD\n'
                    os.lseek(fd, 0, os.SEEK_SET)
                    os.write(fd, value)
                    os.ftruncate(fd, len(value))
                    fired()
                sys.exit(rc)
sys.exit(execute())