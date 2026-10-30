#!/usr/bin/env python3
"""Apply one native calendar deadline, then exit. No polling or resident process."""
from pathlib import Path
from datetime import datetime, timedelta
import argparse
import fcntl
import os
import plistlib
import subprocess
from renew_phone import DEFAULT_HOME, UTC, date, now, read_json

LABEL = "local.snapbridge.renewal"


def calendar_fields(deadline):
    # launchd has minute precision. Rounding down can run just before the
    # 48-hour threshold and leave the next matching calendar date a year away.
    if deadline.second or deadline.microsecond:
        deadline = deadline.replace(second=0, microsecond=0) + timedelta(minutes=1)
    local = deadline.astimezone()
    return dict(Month=local.month, Day=local.day, Hour=local.hour, Minute=local.minute)


def job(home, deadline):
    # LaunchServices assigns the signed app's saved Local Network permission.
    # Direct launchd exec can lose that attribution after a helper rebuild.
    # -g/-j keep focus and windows unchanged; -n preserves an open setup window.
    app = home / "SnapBridge Renewal.app"
    return dict(Label=LABEL, ProgramArguments=["/usr/bin/open", "-g", "-j", "-W", "-n", str(app),
                                              "--args", "--run-renewal", "--home", str(home)],
                AssociatedBundleIdentifiers=["local.snapbridge.renewal"],
                WorkingDirectory=str(home), StartCalendarInterval=calendar_fields(deadline),
                RunAtLoad=False, ProcessType="Background", Nice=10,
                LowPriorityIO=True, StandardOutPath="/dev/null",
                StandardErrorPath=str(home / "launchd-error.log"))


def control(*args):
    return subprocess.run(["/bin/launchctl", *args], capture_output=True, text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=DEFAULT_HOME)
    args = parser.parse_args()
    home = args.home.expanduser().resolve()
    with (home / "schedule.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        requests = list((home / "ScheduleRequests").glob("*.request"))
        state = read_json(home / "state.json")
        domain = "gui/" + str(os.getuid())
        service = domain + "/" + LABEL
        path = Path.home() / "Library/LaunchAgents" / (LABEL + ".plist")
        if not state.get("next_run"):
            control("bootout", service)
        else:
            deadline = date(state["next_run"])
            # A past deadline is resumed once at login, rather than waiting a year.
            planned = max(deadline, now() + timedelta(minutes=2))
            data = plistlib.dumps(job(home, planned), sort_keys=False)
            loaded = control("print", service)
            if not path.exists() or path.read_bytes() != data or loaded.returncode:
                temp = path.with_suffix(".tmp")
                temp.write_bytes(data); temp.chmod(0o644); temp.replace(path)
                control("bootout", service)
                result = control("bootstrap", domain, str(path))
                if result.returncode:
                    raise RuntimeError("Cannot register the renewal calendar: " + result.stderr[-400:])
            if deadline <= now():
                result = control("kickstart", service)
                if result.returncode:
                    raise RuntimeError("Cannot start the due renewal: " + result.stderr[-400:])
        # Only acknowledge requests read at entry; a concurrent new request survives.
        for request in requests:
            request.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
