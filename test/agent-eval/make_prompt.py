#!/usr/bin/env python3
"""Print the prompt for one evaluation run.

    make_prompt.py --set easy|hard [--primer docs/agent/common-lisp-primer.md] > prompt.txt

Without --primer you get the control prompt; with it, the same prompt plus the primer text. Give the prompt to the
model under test (with no ability to run code, otherwise you are measuring the tool, not the model), have it write its
answer file, then grade it with grade.py.
"""
import argparse, importlib, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

HEAD = '''You are completing a set of small Common Lisp programming tasks.

Rules:
- Target: standard ANSI Common Lisp running in SBCL, in package COMMON-LISP-USER. Do not use in-package or defpackage.
- No external libraries: no Quicklisp, no alexandria, no (require ...).
- Define exactly what each task names. Do not include test code, examples, printing, or top-level calls.
- Every task is checked on its own, in a fresh Lisp session that sees only that task's code block. A task's code must therefore be
  self-contained: it must not call functions defined for other tasks. Define any helper you need inside that task's block, under a name
  that starts with the task's own name.
- You cannot run any code in this environment and must not try. Write the solutions from your own knowledge.
- Save your answer using this exact layout and nothing else:
  for every task, a heading line "### <task-id>" followed by one fenced ```lisp block with all the code for that task.
'''


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--set", choices=("easy", "hard"), required=True)
    ap.add_argument("--primer")
    a = ap.parse_args()
    tasks = importlib.import_module("tasks_" + a.set).TASKS
    out = HEAD
    if a.primer:
        out += "\n## Reference notes on Common Lisp (read before solving)\n\n" + open(a.primer).read() + "\n"
    out += "\n## Tasks\n\n" + "\n".join("### %s\n%s\n" % (t["id"], t["prompt"]) for t in tasks)
    sys.stdout.write(out)


if __name__ == "__main__":
    main()
