"""Single exec launcher: own one daemon and clear only a proven dead socket."""
import errno
import fcntl
import os
from pathlib import Path
import socket
import stat

generation = Path(__file__).resolve().parent
guard = os.open(str(generation / "daemon.lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
os.set_inheritable(guard, True)
control = generation / "control.sock"
try:
    before = control.lstat()
except FileNotFoundError:
    before = None
if before is not None:
    if not stat.S_ISSOCK(before.st_mode) or before.st_uid != os.geteuid():
        raise SystemExit("refuse foreign control socket entry")
    with socket.socket(socket.AF_UNIX) as probe:
        probe.settimeout(1)
        try:
            probe.connect(str(control))
        except OSError as error:
            if error.errno != errno.ECONNREFUSED:
                raise SystemExit("control socket is not proven stale")
        else:
            raise SystemExit("daemon is already active")
    after = control.lstat()
    if (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino):
        raise SystemExit("control socket changed during startup")
    control.unlink()
os.umask(0o077)
binary = str(generation / "splicore")
os.execv(binary, [binary, "run", "--config", str(generation / "bootstrap.yaml")])
