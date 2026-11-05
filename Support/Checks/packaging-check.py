#!/usr/bin/env python3
"""Run real packaging scripts with disposable tools; never sign or submit anything."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

repo = Path(__file__).resolve().parents[2]
shim = '''#!/usr/bin/env python3
import os, sys
from pathlib import Path
cmd = Path(sys.argv[0]).name
args = sys.argv[1:]
failure = os.environ.get("FIXTURE_FAILURE", "")
with Path("fixture-tools.log").open("a") as log: log.write(cmd + " " + " ".join(args) + "\\n")
if failure == cmd or (cmd == "xcrun" and args[0] == failure) or (failure == "verify" and cmd == "codesign" and "--verify" in args):
    sys.exit(41)
if cmd == "security":
    print('1) FIXTURE "Developer ID Application: Disposable Fixture"')
elif cmd == "swift":
    for path in [".build/arm64-apple-macosx/release/Cairn", ".build/apple/Products/Release/Cairn"]:
        p = Path(path); p.parent.mkdir(parents=True, exist_ok=True); p.write_text("new executable")
elif cmd == "codesign" and "--entitlements" in args and "-d" in args:
    if failure == "entitlements-read": sys.exit(42)
    if failure == "unsafe-entitlement": print("<key>com.apple.security.get-task-allow</key><true/>")
elif cmd == "codesign" and "--verbose=2" in args and "-d" in args:
    print("flags=none" if failure == "missing-runtime" else "flags=runtime", file=sys.stderr)
elif cmd == "ditto":
    Path(args[-1]).write_text("new archive")
'''

with tempfile.TemporaryDirectory(prefix="cairn-packaging-") as temporary:
    root = Path(temporary)
    tools = root / "tools"
    tools.mkdir()
    for name in ["swift", "security", "codesign", "xcrun", "ditto", "spctl"]:
        path = tools / name
        path.write_text(shim)
        path.chmod(0o755)
    for script in ["build_local.sh", "build_release.sh"]:
        failures = ["", "swift", "codesign", "verify", "missing-icon"]
        if script == "build_release.sh":
            failures += ["notarytool", "stapler", "spctl", "entitlements-read", "unsafe-entitlement", "missing-runtime"]
        for failure in failures:
            work = root / (script + "-" + (failure or "success"))
            work.mkdir()
            shutil.copy(repo / script, work / script)
            resources = work / "Cairn/Resources"
            resources.mkdir(parents=True)
            for asset in ["Cairn.icns", "CairnMark.png"]:
                if failure != "missing-icon" or asset != "Cairn.icns":
                    (resources / asset).write_text("approved fixture asset")
            (work / "Cairn/Info.plist").write_text("fixture plist")
            (work / "Cairn/Cairn-dist.entitlements").write_text("fixture entitlements")
            previous = work / "dist/Cairn.app/Contents/MacOS/Cairn"
            previous.parent.mkdir(parents=True)
            previous.write_text("previous executable")
            archive = work / "dist/Cairn.zip"
            archive.write_text("previous archive")
            # Earlier builds, oldest first: five finished, one failed two days
            # ago, one failed (or still running) just now, and one finished
            # build whose app is open.
            prefix = "local" if script == "build_local.sh" else "release"
            now = time.time()
            earlier = {}
            for index, (name, incomplete, age) in enumerate([
                ("running", False, 9), ("old1", False, 8), ("old2", False, 7), ("old3", False, 6),
                ("old4", False, 5), ("old5", False, 4), ("failed-old", True, 3 * 86_400), ("failed-new", True, 60),
            ]):
                folder = work / "dist" / f"{prefix}.{name}"
                executable = folder / "Cairn.app/Contents/MacOS/Cairn"
                executable.parent.mkdir(parents=True)
                executable.write_text("earlier executable")
                stamp = now - (3 * 86_400 if name == "failed-old" else 3_600 - index * 60)
                if incomplete:
                    (folder / "INCOMPLETE").touch()
                    os.utime(folder / "INCOMPLETE", (stamp, stamp))
                os.utime(folder, (stamp, stamp))
                earlier[name] = folder
            running = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(120)",
                                        str(earlier["running"] / "Cairn.app/Contents/MacOS/Cairn")])
            try:
                env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"], ARCH="arm64", FIXTURE_FAILURE=failure)
                result = subprocess.run(["bash", script], cwd=work, env=env, capture_output=True, text=True)
            finally:
                running.terminate(); running.wait()
            assert (result.returncode != 0) == bool(failure), result.stdout + result.stderr
            if failure in ["entitlements-read", "unsafe-entitlement", "missing-runtime"]:
                assert "notarytool" not in (work / "fixture-tools.log").read_text()
            assert previous.read_text() == "previous executable"
            assert archive.read_text() == "previous archive"
            outputs = [path for path in (work / "dist").glob(prefix + ".*") if path not in earlier.values()]
            assert len(outputs) == 1
            assert (outputs[0] / "INCOMPLETE").exists() == bool(failure)
            remaining = {name for name, folder in earlier.items() if folder.exists()}
            if failure:
                assert remaining == set(earlier), remaining
            else:
                assert (outputs[0] / "Cairn.app/Contents/MacOS/Cairn").read_text() == "new executable"
                if script == "build_release.sh":
                    assert (outputs[0] / "Cairn.zip").exists()
                # This build plus the two newest finished ones stay, the failed
                # build from just now stays, the open app stays; the rest go.
                assert remaining == {"old5", "old4", "failed-new", "running"}, (remaining, result.stdout)
            print(f"PASS {script}: {failure or 'success'} preserves prior app/archive; completion marker is correct; "
                  + ("keeps every earlier build" if failure else "keeps the newest builds and any open app"))
