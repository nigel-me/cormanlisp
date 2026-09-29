#!/usr/bin/env python3
"""Summarise and compare test-results.jsonl files written by test/harness.lisp.

    results.py summary FILE [--failures] [--limit N]
    results.py diff BASE NEW [--limit N] [--strict]
    results.py check FILE

Uses only the Python standard library, so it runs anywhere (for example on a
machine without Windows, on results copied off a Windows build).

Exit codes: 0 = fine, 1 = regressions (diff) / problems in the run (summary, check),
2 = unreadable input.
"""

import argparse
import json
import sys
from collections import OrderedDict

BAD = ("fail", "error")


class Run:
    def __init__(self, path):
        self.path = path
        self.environment = None
        self.summary = None
        self.results = []        # result records in file order
        self.last_begin = None   # last "begin" record seen (only with trace on)
        self.problems = []       # structural problems with the file itself
        self._load()

    def _load(self):
        try:
            handle = open(self.path, encoding="utf-8")
        except OSError as exc:
            raise SystemExit("cannot open %s: %s" % (self.path, exc))
        with handle:
            for number, line in enumerate(handle, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                except ValueError as exc:
                    self.problems.append("line %d is not valid JSON: %s" % (number, exc))
                    continue
                kind = record.get("type")
                if kind == "environment":
                    self.environment = record
                elif kind == "summary":
                    self.summary = record
                elif kind == "begin":
                    self.last_begin = record
                elif kind == "result":
                    self.results.append(record)
                    self.last_begin = None
                else:
                    self.problems.append("line %d has unknown record type %r" % (number, kind))
        if self.environment is None:
            self.problems.append("no environment record")
        if self.summary is None:
            self.problems.append(
                "no summary record: the run did not finish (crash, hang or killed)")
            if self.last_begin is not None:
                b = self.last_begin
                self.problems.append(
                    "last test started but never finished: %s / %s #%s: %s"
                    % (b.get("file"), b.get("suite"), b.get("index"), b.get("expr")))
            elif self.results:
                r = self.results[-1]
                self.problems.append(
                    "last completed test: %s / %s #%s (run with :trace-tests t to "
                    "identify the test that was running)"
                    % (r.get("file"), r.get("suite"), r.get("index")))
        else:
            counted = self.totals()
            claimed = self.summary.get("totals", {})
            for status, count in claimed.items():
                if counted.get(status, 0) != count:
                    self.problems.append(
                        "summary claims %d %s but the file has %d"
                        % (count, status, counted.get(status, 0)))

    def totals(self):
        totals = {}
        for r in self.results:
            totals[r["status"]] = totals.get(r["status"], 0) + 1
        return totals

    def keyed(self):
        """Map (file, suite, expr, occurrence) -> record. Occurrence numbers
        repeated identical expressions within one suite."""
        seen = {}
        out = OrderedDict()
        for r in self.results:
            base = (r.get("file"), r.get("suite"), r.get("expr"))
            n = seen.get(base, 0)
            seen[base] = n + 1
            out[base + (n,)] = r
        return out


def describe_env(run):
    e = run.environment or {}
    return "%s %s  label=%r  started=%s" % (
        e.get("implementation", "?"), e.get("version", "?"),
        e.get("label", ""), e.get("started", "?"))


def short(text, width=110):
    if text is None:
        return "-"
    text = text.replace("\n", " ")
    return text if len(text) <= width else text[: width - 3] + "..."


def cmd_summary(args):
    run = Run(args.file)
    print(args.file)
    print("  " + describe_env(run))
    totals = run.totals()
    print("  totals: " + ", ".join(
        "%d %s" % (totals.get(s, 0), s) for s in ("pass", "fail", "error", "info")))
    per_file = OrderedDict()
    for r in run.results:
        per_file.setdefault(r["file"], {})
        per_file[r["file"]][r["status"]] = per_file[r["file"]].get(r["status"], 0) + 1
    for name, counts in per_file.items():
        print("    %-24s %s" % (name, ", ".join(
            "%d %s" % (counts.get(s, 0), s) for s in ("pass", "fail", "error", "info")
            if counts.get(s, 0))))
    if run.summary:
        print("  elapsed: %s ms" % run.summary.get("elapsed_ms"))
    if args.failures:
        shown = 0
        for r in run.results:
            if r["status"] in BAD:
                if shown >= args.limit:
                    print("  ... (more; raise --limit)")
                    break
                shown += 1
                print("  [%s] %s / %s #%s" % (r["status"], r["file"], r["suite"], r["index"]))
                print("      expr:     " + short(r.get("expr")))
                if r["status"] == "fail":
                    print("      expected: " + short(r.get("expected")))
                    print("      actual:   " + short(r.get("actual")))
                if r.get("message"):
                    print("      message:  " + short(r.get("message")))
    for problem in run.problems:
        print("  PROBLEM: " + problem)
    return 1 if run.problems else 0


def cmd_check(args):
    run = Run(args.file)
    for problem in run.problems:
        print("PROBLEM: " + problem)
    if not run.problems:
        print("ok: %d results" % len(run.results))
    return 1 if run.problems else 0


def cmd_diff(args):
    base, new = Run(args.base), Run(args.new)
    print("base: %s  (%s)" % (args.base, describe_env(base)))
    print("new:  %s  (%s)" % (args.new, describe_env(new)))
    for label, run in (("base", base), ("new", new)):
        for problem in run.problems:
            print("  %s PROBLEM: %s" % (label, problem))
    bk, nk = base.keyed(), new.keyed()

    regressions, fixes, changed, added, removed = [], [], [], [], []
    for key, b in bk.items():
        n = nk.get(key)
        if n is None:
            removed.append((key, b))
            continue
        bs, ns = b["status"], n["status"]
        if bs == ns:
            continue
        if bs in BAD and ns in BAD:
            changed.append((key, b, n))
        elif ns in BAD:
            regressions.append((key, b, n))
        elif bs in BAD:
            fixes.append((key, b, n))
        # pass <-> info: neutral, not reported
    for key, n in nk.items():
        if key not in bk:
            added.append((key, n))

    def section(title, items, show):
        print("\n%s: %d" % (title, len(items)))
        for item in items[: args.limit]:
            show(item)
        if len(items) > args.limit:
            print("  ... (%d more; raise --limit)" % (len(items) - args.limit))

    def show_change(item):
        key, b, n = item
        print("  %s / %s #%s   %s -> %s" % (key[0], key[1], n.get("index"), b["status"], n["status"]))
        print("      expr:   " + short(key[2]))
        if n["status"] == "fail":
            print("      expected: " + short(n.get("expected")))
            print("      actual:   " + short(n.get("actual")))
        if n.get("message"):
            print("      message:  " + short(n.get("message")))

    def show_added(item):
        key, n = item
        print("  %s / %s  [%s]  %s" % (key[0], key[1], n["status"], short(key[2], 80)))

    section("REGRESSIONS (passing before, failing now)", regressions, show_change)
    section("Fixed (failing before, passing now)", fixes, show_change)
    section("Still failing but differently", changed, show_change)
    section("New tests", added, show_added)
    section("Missing from new run", removed, show_added)

    bt, nt = base.totals(), new.totals()
    print("\nbase: " + ", ".join("%d %s" % (bt.get(s, 0), s) for s in ("pass", "fail", "error", "info")))
    print("new:  " + ", ".join("%d %s" % (nt.get(s, 0), s) for s in ("pass", "fail", "error", "info")))

    failed = bool(regressions)
    if args.strict:
        failed = failed or bool(removed) or bool(new.problems)
    return 1 if failed else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("summary", help="totals per file, optionally the failing tests")
    p.add_argument("file")
    p.add_argument("--failures", action="store_true", help="list failing and erroring tests")
    p.add_argument("--limit", type=int, default=50)
    p.set_defaults(func=cmd_summary)

    p = sub.add_parser("diff", help="compare two runs; exit 1 if anything regressed")
    p.add_argument("base")
    p.add_argument("new")
    p.add_argument("--limit", type=int, default=25)
    p.add_argument("--strict", action="store_true",
                   help="also fail on tests missing from NEW or a problem in NEW's file")
    p.set_defaults(func=cmd_diff)

    p = sub.add_parser("check", help="validate the structure of a results file")
    p.add_argument("file")
    p.set_defaults(func=cmd_check)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
