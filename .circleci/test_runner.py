"""Run existing MR Remote tests and convert their real output to JUnit.

Rust unit tests are discovered at Cargo target granularity (manifest atoms);
Flutter uses tracked *_test.dart files. No application code is changed.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
RUST_ATOMS = {
    "rust-core": "Cargo.toml",
    "rust-clipboard": "libs/clipboard/Cargo.toml",
}


def discover(suite):
    if suite in RUST_ATOMS:
        atom = RUST_ATOMS[suite]
        if not (ROOT / atom).is_file():
            raise RuntimeError("Missing test target: " + atom)
        return [atom]
    if suite != "flutter":
        raise ValueError("Unknown suite: " + suite)
    files = subprocess.check_output(
        ["git", "ls-files", "--", "flutter/test/"], cwd=ROOT, text=True
    ).splitlines()
    atoms = sorted(p for p in files if p.endswith("_test.dart"))
    if not atoms:
        raise RuntimeError("No tracked Flutter tests found")
    return atoms


def stream(command, cwd, env=None):
    proc = subprocess.Popen(
        command, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace", bufsize=1,
    )
    lines = []
    assert proc.stdout is not None
    live_path = os.environ.get("MR_TEST_LIVE_LOG")
    log = Path(live_path).open("w", encoding="utf-8") if live_path else None
    try:
        for line in proc.stdout:
            print(line, end="", flush=True)
            if log:
                log.write(line)
                log.flush()
            lines.append(line.rstrip("\r\n"))
        return proc.wait(), lines
    finally:
        if log:
            log.close()


def clean(text):
    return re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", str(text))


def write_junit(path, suite, records, output):
    root = ET.Element("testsuite", {
        "name": suite, "tests": str(len(records)),
        "failures": str(sum(r["status"] == "failure" for r in records)),
        "errors": str(sum(r["status"] == "error" for r in records)),
        "skipped": str(sum(r["status"] == "skipped" for r in records)),
        "time": str(sum(r.get("time", 0) for r in records)),
    })
    for r in records:
        case = ET.SubElement(root, "testcase", {
            "classname": clean(r["atom"]), "file": clean(os.path.normpath(r["atom"])),
            "name": clean(r["name"]), "time": str(r.get("time", 0)),
        })
        if r["status"] != "success":
            el = ET.SubElement(case, r["status"], {"message": clean(r.get("message", r["status"]))})
            el.text = clean(r.get("message", r["status"]))
    ET.SubElement(root, "system-out").text = clean("\n".join(output)[-160000:])
    path.parent.mkdir(parents=True, exist_ok=True)
    # Close the report explicitly before CircleCI reads or annotates it.
    with path.open("wb") as report:
        ET.ElementTree(root).write(report, encoding="utf-8", xml_declaration=True)


def problem(atom, message):
    return {"atom": atom, "name": "test runner error", "status": "error", "message": message}


def run_rust(suite, atoms):
    atom = RUST_ATOMS[suite]
    if atoms != [atom]:
        raise RuntimeError("Expected exact Cargo target atom: " + atom)
    command = ["cargo", "test", "--locked", "--release", "--color", "never"]
    if suite == "rust-core":
        features = os.environ.get("MR_RELEASE_FEATURES", "")
        if not {"flutter", "hwcodec", "vram"}.issubset(features.split(",")):
            raise RuntimeError("Release feature list not configured")
        command += ["--lib", "--features", features]
    else:
        command += ["-p", "clipboard"]
    command += ["--", "--format", "pretty"]
    env = os.environ.copy()
    if os.name == "nt":
        # CircleCI invokes the suite through Git Bash; it may prepend Git's
        # Unix link.exe to PATH. Cargo must use the MSVC linker, not that tool.
        linker_value = env.get("MR_MSVC_LINKER")
        if not linker_value:
            raise RuntimeError("MR_MSVC_LINKER is required on Windows")
        linker = Path(linker_value)
        if not linker.is_absolute() or not linker.is_file() or linker.name.lower() != "link.exe":
            raise RuntimeError(f"Invalid MSVC linker: {linker}")
        if "msvc" not in str(linker).lower() or "git" in [p.lower() for p in linker.parts]:
            raise RuntimeError(f"Unexpected linker location: {linker}")
        env["CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER"] = str(linker)
        env["PATH"] = str(linker.parent) + os.pathsep + env.get("PATH", "")
        print(f"MR_TEST_LINKER={linker}", flush=True)
    rc, lines = stream(command, ROOT, env=env)
    records = []
    expected = 0
    summaries = 0
    group = "unit"
    for line in lines:
        s = line.strip()
        if s.startswith("Doc-tests "):
            group = "doc"
        elif s.startswith("Running "):
            group = s
        m = re.match(r"^test (.+) \.\.\. (ok|FAILED|ignored)(?:,.*)?$", s)
        if m:
            name, status = m.groups()
            records.append({
                "atom": atom, "name": group + "::" + name,
                "status": {"ok":"success","FAILED":"failure","ignored":"skipped"}[status],
            })
        m = re.match(r"^test result: (?:ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored;", s)
        if m:
            summaries += 1
            expected += sum(map(int, m.groups()))
    if not summaries or not records or expected != len(records):
        records.append(problem(atom, f"Rust report mismatch: parsed={len(records)}, expected={expected}, summaries={summaries}"))
        rc = rc or 1
    if rc and not any(r["status"] in ("failure", "error") for r in records):
        records.append(problem(atom, f"cargo exited {rc}"))
    if any(r["status"] in ("failure", "error") for r in records):
        rc = rc or 1
    return rc, records, lines


def path_to_atom(path, atoms):
    if not path:
        return None
    value = unquote(str(path)).replace("\\", "/").lower()
    for atom in atoms:
        rel = atom.lower()
        short = rel.removeprefix("flutter/")
        if value == rel or value == short or value.endswith("/" + rel):
            return atom
    return None


def run_flutter(atoms):
    tool = shutil.which("flutter.bat") or shutil.which("flutter")
    if not tool:
        raise RuntimeError("Flutter SDK not configured")
    command = [tool, "test", "--machine", "--timeout", "60s", "--no-pub"]
    command += [a.removeprefix("flutter/") for a in atoms]
    rc, lines = stream(command, ROOT / "flutter")
    suites, tests, errors, records = {}, {}, {}, []
    done = set()
    for line in lines:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        kind = event.get("type")
        if kind == "suite":
            s = event["suite"]
            suites[s["id"]] = path_to_atom(s.get("path"), atoms)
        elif kind == "testStart":
            t = event["test"]
            tests[t["id"]] = (t, event.get("time", 0))
        elif kind == "error":
            errors.setdefault(event.get("testID"), []).append(str(event.get("error", "")) + "\n" + str(event.get("stackTrace", "")))
        elif kind == "testDone":
            tid = event["testID"]
            if tid not in tests or tid in done:
                continue
            done.add(tid)
            t, start = tests[tid]
            atom = suites.get(t.get("suiteID"))
            if not atom:
                continue
            failed = event.get("result") in ("failure", "error")
            if event.get("hidden") and not failed:
                continue
            status = "skipped" if event.get("skipped") and not failed else event.get("result", "error")
            if status not in ("success", "skipped", "failure", "error"):
                status = "error"
            records.append({
                "atom": atom, "name": t.get("name", str(tid)), "status": status,
                "time": max(0, event.get("time", start) - start) / 1000,
                "message": "\n".join(errors.get(tid, [])),
            })
    reported = {r["atom"] for r in records}
    for atom in atoms:
        if atom not in reported:
            records.append(problem(atom, "No test result reported for selected file"))
            rc = rc or 1
    if rc and not any(r["status"] in ("failure", "error") for r in records):
        records.append(problem(atoms[0], f"flutter test exited {rc}"))
    if any(r["status"] in ("failure", "error") for r in records):
        rc = rc or 1
    return rc, records, lines


def main():
    action, suite = sys.argv[1:3]
    known = discover(suite)
    if action == "discover":
        print("\n".join(known))
        return 0
    if action != "run" or len(sys.argv) < 4:
        raise RuntimeError("Usage: test_runner.py run SUITE JUNIT [ATOM...]")
    path = Path(sys.argv[3])
    # CircleCI documents newline-separated atoms on stdin when test.atoms is
    # omitted. This avoids Bash consuming backslashes in Windows file paths.
    raw_atoms = sys.argv[4:] if len(sys.argv) > 4 else sys.stdin.read().splitlines()
    atoms = list(dict.fromkeys(a.strip().replace("\\", "/").removeprefix("./") for a in raw_atoms if a.strip()))
    logs = ROOT / ".mr-test-logs" / suite
    logs.mkdir(parents=True, exist_ok=True)
    log_path = logs / (path.stem + ".log")
    os.environ["MR_TEST_LIVE_LOG"] = str(log_path)
    try:
        if not atoms or not set(atoms).issubset(known):
            raise RuntimeError(f"Unexpected or empty selected atoms: {atoms!r}")
        rc, records, lines = run_flutter(atoms) if suite == "flutter" else run_rust(suite, atoms)
    except Exception as exc:
        message = f"{type(exc).__name__}: {exc}"
        print(message, file=sys.stderr, flush=True)
        rc, records, lines = 1, [problem(a, message) for a in (atoms or known)], [message]
    # Keep the complete native output outside the JUnit directory, including doctor runs.
    log_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    write_junit(path, suite, records, lines)
    if rc:
        print(f"MR_TEST_FAILURE: suite={suite}; exit={rc}; full_log={log_path}", file=sys.stderr, flush=True)
    print(f"MR_TEST_REPORT: {suite}; records={len(records)}; exit={rc}; junit={path}", flush=True)
    return rc


if __name__ == "__main__":
    sys.exit(main())
