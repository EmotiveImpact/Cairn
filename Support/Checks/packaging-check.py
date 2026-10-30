#!/usr/bin/env python3
"""Run real packaging scripts with disposable tools; never sign or submit anything."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

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
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"], ARCH="arm64", FIXTURE_FAILURE=failure)
            result = subprocess.run(["bash", script], cwd=work, env=env, capture_output=True, text=True)
            assert (result.returncode != 0) == bool(failure), result.stdout + result.stderr
            if failure in ["entitlements-read", "unsafe-entitlement", "missing-runtime"]:
                assert "notarytool" not in (work / "fixture-tools.log").read_text()
            assert previous.read_text() == "previous executable"
            assert archive.read_text() == "previous archive"
            outputs = list((work / "dist").glob("local.*" if script == "build_local.sh" else "release.*"))
            assert len(outputs) == 1
            assert (outputs[0] / "INCOMPLETE").exists() == bool(failure)
            if not failure:
                assert (outputs[0] / "Cairn.app/Contents/MacOS/Cairn").read_text() == "new executable"
                if script == "build_release.sh":
                    assert (outputs[0] / "Cairn.zip").exists()
            print(f"PASS {script}: {failure or 'success'} preserves prior app/archive; completion marker is correct")
