#!/usr/bin/env python3
"""Grade Common Lisp answers with SBCL (needs `sbcl` on the PATH).

    grade.py --set easy|hard ANSWER.md [ANSWER.md ...]     grade answer files, print a table
    grade.py --set easy|hard --selftest                    check the tasks themselves

ANSWER.md layout: for every task a heading line "### <task-id>" followed by a ```lisp fenced block
(see make_prompt.py, which produces the prompt that asks for this layout).

Each task is graded in its own fresh SBCL process: the code block is loaded, then every test form
for that task is evaluated. A task passes only if all of its tests are true. --selftest runs the reference
solutions (must all pass) and the deliberately naive ones (must all fail).
"""
import argparse, importlib, json, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
TIMEOUT = 30


def load_set(name):
    tasks = importlib.import_module("tasks_" + name).TASKS
    oracle = importlib.import_module("oracle_" + name)
    return tasks, oracle.ORACLE, oracle.NAIVE


def extract(text):
    """{task_id: code}. A '### id' heading followed by one or more fenced blocks."""
    out = {}
    parts = re.split(r'(?m)^#{2,4}\s*`?([A-Za-z0-9_-]+)`?\s*$', text)
    for i in range(1, len(parts) - 1, 2):
        blocks = re.findall(r'```[A-Za-z-]*\n(.*?)```', parts[i + 1], re.S)
        if blocks:
            out[parts[i]] = "\n".join(blocks)
    return out


def run_task(task, code):
    tests = task["tests"]
    with tempfile.TemporaryDirectory() as d:
        sol = os.path.join(d, "sol.lisp")
        open(sol, "w").write(code)
        forms = "\n".join("  %s" % json.dumps(t) for t in tests)
        drv = os.path.join(d, "drv.lisp")
        open(drv, "w").write('''
(setf *load-verbose* nil *compile-verbose* nil)
(defparameter *tests* (list
%s))
(handler-bind ((warning #'muffle-warning))
  (handler-case (load "%s")
    (error (e) (format t "LOADFAIL: ~A~%%" e) (finish-output) (sb-ext:exit :code 3 :abort t))))
(let ((pass 0))
  (dolist (s *tests*)
    (let ((form (let ((*package* (find-package :cl-user))) (read-from-string s))))
      (handler-case
          (if (eval form) (incf pass) (format t "FALSE: ~A~%%" s))
        (error (e) (format t "ERROR: ~A~%%   in ~A~%%" e s)))))
  (format t "RESULT ~D/~D~%%" pass (length *tests*))
  (finish-output)
  (sb-ext:exit :code (if (= pass (length *tests*)) 0 1) :abort t))
''' % (forms, sol))
        try:
            p = subprocess.run(["sbcl", "--noinform", "--non-interactive", "--no-sysinit", "--no-userinit",
                                "--load", drv], capture_output=True, text=True, timeout=TIMEOUT, cwd=d)
        except subprocess.TimeoutExpired:
            return dict(status="timeout", passed=0, total=len(tests), detail="timeout")
        out = (p.stdout or "") + (p.stderr or "")
        if "LOADFAIL" in out:
            return dict(status="loadfail", passed=0, total=len(tests), detail=out[out.index("LOADFAIL"):][:300])
        m = re.search(r"RESULT (\d+)/(\d+)", out)
        if m:
            passed, total = int(m.group(1)), int(m.group(2))
            detail = "\n".join(l for l in out.splitlines() if l.startswith(("FALSE", "ERROR")))[:400]
            return dict(status="pass" if passed == total else "fail", passed=passed, total=total, detail=detail)
        return dict(status="crash", passed=0, total=len(tests), detail=out[-300:])


def grade_text(tasks, text):
    sols = extract(text)
    res = {}
    for t in tasks:
        code = sols.get(t["id"])
        res[t["id"]] = (run_task(t, code) if code is not None else
                        dict(status="missing", passed=0, total=len(t["tests"]), detail="no solution block"))
    return res


def selftest(tasks, oracle, naive):
    byid = {t["id"]: t for t in tasks}
    bad = 0
    for t in tasks:
        r = run_task(t, oracle[t["id"]])
        if r["status"] != "pass":
            bad += 1
            print("REFERENCE SOLUTION FAILS:", t["id"], r)
    for k, code in naive.items():
        r = run_task(byid[k], code)
        if r["status"] == "pass":
            bad += 1
            print("NAIVE SOLUTION PASSES (test too weak):", k)
    print("%d tasks, %d naive variants: %s" % (len(tasks), len(naive), "OK" if not bad else "%d problem(s)" % bad))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--set", choices=("easy", "hard"), required=True)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("answers", nargs="*")
    a = ap.parse_args()
    tasks, oracle, naive = load_set(a.set)
    if a.selftest:
        return selftest(tasks, oracle, naive)
    kinds = {t["id"]: t["kind"] for t in tasks}
    print("%-28s %6s %8s %8s  %s" % ("answer file", "all", "trap", "control", "loadfail/missing/timeout"))
    for f in a.answers:
        r = grade_text(tasks, open(f).read())
        n = lambda k: sum(1 for i, v in r.items() if v["status"] == "pass" and (k is None or kinds[i] == k))
        tot = lambda k: sum(1 for x in kinds.values() if k is None or x == k)
        odd = sum(1 for v in r.values() if v["status"] in ("loadfail", "missing", "timeout", "crash"))
        print("%-28s %3d/%-3d %4d/%-3d %4d/%-3d  %d" % (os.path.basename(f), n(None), tot(None), n("trap"),
              tot("trap"), n("control"), tot("control"), odd))
        for i, v in r.items():
            if v["status"] != "pass":
                print("    %-18s %s %d/%d %s" % (i, v["status"], v["passed"], v["total"],
                                                  v["detail"][:80].replace("\n", " | ")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
