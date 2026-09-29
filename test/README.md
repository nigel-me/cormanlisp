# Running the Corman Lisp tests

This guide is for people. It explains how to run the test harness, read its results, and compare two runs,
for example to check that a new build behaves the same as an old one.

> **Status.** The harness has been exercised on a different Common Lisp (SBCL) using the real test files, but it has
> **not yet been run on Corman Lisp itself**. If something below fails on your machine, that is useful information:
> see [Troubleshooting](#troubleshooting) and please report it or fix the harness. Nothing here changes the tests themselves.

## What it is

The test files in this directory (the HyperSpec examples in `ansi-chapter-*.lisp` and the sequence tests in
`test-sequences.lisp`) already existed. They print results to the screen, which is fine for a human looking at one run
but awkward for comparing runs. The harness runs the **same tests** and additionally writes a results file with one
line per test, so you can:

- see totals at a glance,
- list exactly which tests fail, with expected and actual values,
- compare a run against an earlier "known good" run and see what got worse or better,
- find out which test was running if Corman Lisp crashes or hangs.

It is not a full conformance suite: the HyperSpec examples cover only a slice of the standard.

## Before you start

- A working Corman Lisp: the executables, `CormanLisp.img`, and this `test` directory. Use a **fresh** console or IDE session
  (the harness redefines `verify` and `dotests`, the names `ansi-examples.lisp` uses, so do not mix the two runners in one session).
- **Optional:** Python 3 (any recent version, standard library only) for the summary and comparison tool. It does not need
  to be on the Windows machine; you can copy the results file anywhere and analyse it there.

## Quick start

From the Corman Lisp directory, in the console (`clconsole.exe`) or in the IDE:

```lisp
(load "test/harness.lisp")
(test-harness:run-all :label "my-first-run")
```

You will see each test file as it runs, a line for each failing test, and a final tally:

```
ansi-chapter-3.lisp
  FAIL  SPECIAL #14: (DECLAIM (SPECIAL X))
        expected: T
        actual:   (X)
...
Results: 778 pass, 16 fail, 16 error, 37 info  (500 ms)
Written to test-results.jsonl
```

*(The numbers above come from a trial run on another Lisp and are only illustrative. Your counts will differ.)*

The full results are in `test-results.jsonl` in the current directory. Now look at them:

```
python test\tools\results.py summary test-results.jsonl --failures
```

(Use `py -3` or `python3` if `python` is not on your path.)

### Running without opening the console

```
clconsole -execute test\run-tests.lisp
```

This runs everything and then ends the process with exit code **0** if all tests passed and **1** otherwise, so a script or
batch file can act on the result. Edit `test\run-tests.lisp` to change the label, and remove `:exit t` if you want the console
to stay open afterwards.

## What the results mean

Each test ends up with one of four statuses:

| Status | Meaning |
|---|---|
| `pass` | The result matched what the test expected. |
| `fail` | The expression ran but returned something different from what was expected. |
| `error` | Evaluating the expression signalled an error, or the file could not be loaded. The message says what happened. |
| `info` | The test's expected value was `implementation-dependent`, so there is nothing to compare. It ran; it is neither good nor bad. |

A few things worth knowing when you read failures:

- Many HyperSpec examples are known to behave differently across implementations, so a failing test is not automatically a bug.
  What matters most is **change**: a test that passed on a good build and fails on a new one.
- Tests in a file share state, as the original runner did (they define functions and variables that later tests use).
  One failure can therefore cause later ones. Look at the first failure in a group.
- `test-sequences.lisp` is recorded one result per *suite*, not per example. When a suite fails, its printed output (which lists
  the failing examples) is kept in the `output` field.

## Common tasks

### Save a baseline, then check a change against it

1. On a build you trust, run the harness and keep the results:
   ```lisp
   (test-harness:run-all :label "known-good" :output-file "baseline.jsonl")
   ```
2. Make your change, rebuild (and rebuild the image if you touched `Sys/` or the kernel), start a fresh session, and run:
   ```lisp
   (test-harness:run-all :label "candidate" :output-file "candidate.jsonl")
   ```
3. Compare:
   ```
   python test\tools\results.py diff baseline.jsonl candidate.jsonl
   ```

The report has these sections: **REGRESSIONS** (passed before, fails now), **Fixed**, **Still failing but differently**,
**New tests**, and **Missing from new run**. It ends with the totals of both runs. The command's exit code is 1 if there are
any regressions, which makes it usable in scripts. Add `--strict` to also fail when tests are missing or the new results
file is damaged, and `--limit N` to show more entries per section.

Keep baselines somewhere safe (they are small text files). `test-results*.jsonl` is ignored by git, so it will not be committed by accident.

### See what failed and why

```
python test\tools\results.py summary candidate.jsonl --failures
```

Shows totals per file and, for each failing test, the expression, the expected and actual values, and any error message.
`--limit N` controls how many are listed (default 50).

### Run only some files

```lisp
(test-harness:run-all :files '("ansi-chapter-5.lisp" "test-sequences.lisp"))
```

File names are those in the table at the top of `harness.lisp` (`*manifest*`).

### Find the test that crashes or hangs

If Corman Lisp dies or you have to kill it during a run, the results file will have no final summary, and `results.py` will say so.
To learn which test was running, rerun with tracing on:

```lisp
(test-harness:run-all :trace-tests t)
```

Then:

```
python test\tools\results.py check test-results.jsonl
```

reports "last test started but never finished" and shows the expression. The harness writes and flushes a marker before every test,
so nothing is lost when the process dies. If the process hangs rather than crashes, interrupt it and use the same command.
The harness cannot put a time limit on a test.

### Add a test

Add an entry to an existing `ansi-chapter-*.lisp` file in the format it already uses:

```lisp
(dotests MY-FEATURE
    (+ 1 2)                 =>  3
    (subseq "hello" 1 3)    =>  "el"
    (member 3 '(1 2 3))     =>  true          ; true / false test the result as a boolean
    (get-universal-time)    =>  implementation-dependent
)
```

- `expr => expected` pairs. `expected` is not evaluated. It is compared with `equalp`.
- `true` and `false` mean "any non-nil value" and "nil".
- `(values a b)` as the expected form checks multiple return values.
- `implementation-dependent` runs the expression and records `info`.

To add a whole new test file, put it in this directory and add a line to `*manifest*` in `harness.lisp`
(`("my-tests.lisp" :dotests)`). Files that need a person to answer prompts, benchmarks, and non-code files are deliberately
left out of the manifest.

## Reference

### `test-harness:run-all`

| Keyword | Default | Meaning |
|---|---|---|
| `:output-file` | `"test-results.jsonl"` | Where to write results (overwritten if it exists). Relative to the current directory. |
| `:label` | `""` | A name recorded in the results, e.g. `"vs2015"` or `"after-gc-fix"`. Shown by `results.py`. |
| `:files` | all | List of file names from the manifest to run. |
| `:trace-tests` | `nil` | Write a marker before each test so a crash can be traced (see above). |
| `:exit` | `nil` | End the process afterwards with code 0 (all passed) or 1. |

Returns `T` if there were no failures or errors, `NIL` otherwise.

Other variables you can set before calling it: `test-harness:*capture-output*` (default `T`; output printed by tests goes into
the results file instead of the screen), `test-harness:*max-text*` (longest stored value, default 400 characters),
`test-harness:*max-failures-shown*` (how many failures are echoed to the screen, default 60).

### `test/tools/results.py`

| Command | Purpose |
|---|---|
| `results.py summary FILE [--failures] [--limit N]` | Totals per file; optionally list failing tests. |
| `results.py diff BASE NEW [--limit N] [--strict]` | Compare two runs. Exit code 1 on regressions. |
| `results.py check FILE` | Validate a results file: complete run? counts consistent? which test was last running? |

The file format is JSON Lines (one JSON object per line), so you can also inspect it with any JSON-aware tool.
Record types are `environment`, `result`, `summary`, and (with tracing) `begin`. Field-by-field details are in
[`docs/agent/08-test-harness.md`](../docs/agent/08-test-harness.md).

## Checking a Lisp file's structure

`test/tools/lispcheck.py` finds unbalanced parentheses, unterminated strings and unterminated `#| |#` comments without needing a
Lisp, and reports the line and column:

```
python test\tools\lispcheck.py Sys\myfile.lisp
```

It understands Corman's `#! ... !#` C-declaration blocks (use `--generic` for plain Common Lisp), `#\(` character
literals and `|symbols|`. When a file has an error it also prints hints, such as a `(` in column 1 inside a form that is
still open, which usually marks where a `)` went missing. Use `--strict` to make warnings (for example mixed CRLF/LF line endings)
fail the run. It checks structure only; it does not tell you the file will load.

Run over the whole repository it reports two files: `test/bugs.lisp` (a saved mailing-list message, not code) and
`Libraries/sql-odbc-0.85/doc/sql-odbc-documentation.lisp` (truncated mid-sentence with stray NUL bytes; a genuine defect
in the upstream file).

## Troubleshooting

| What you see | Likely cause and what to do |
|---|---|
| `Can't resolve load path` / file not found when loading `test/harness.lisp` | The current directory is not the Corman Lisp directory. Use a full path, or `cd` there first. |
| An `error` result named `<load>` for a file | That test file could not be loaded (a reader error, or something the harness needs is missing). The message says which. Earlier tests in the same file are still recorded. |
| Every file shows `<load>` errors, or the results file is empty | The harness itself is not working on this build. Check the assumptions listed in `docs/agent/08-test-harness.md`, especially error handling and `*load-truename*`. This is the most likely place to hit a first-run problem. |
| `test-sequences.lisp` fails to load | The harness loads `testkit.lisp` from this directory first. Make sure it is present and that `(require "TESTKIT")` was not shadowed. |
| Output stops midway and there is no "Results:" line | The process crashed or hung. Rerun with `:trace-tests t` and use `results.py check`. |
| `results.py` says "summary claims N but the file has M" | The results file was edited or truncated after writing. Rerun. |
| Two runs of the same build give different results | Some tests depend on state left by earlier ones or on time. Always start from a fresh session and run all files in the same order. |
| `python` is not recognised | Try `py -3` or `python3`, or copy the results file to a machine that has Python. |

## Limits worth knowing

- No per-test time limit, and a hard crash of the Lisp process ends the run (tracing tells you where).
- The HyperSpec examples are a thin slice of the standard, so a fully green run does not mean the system is fully conformant.
- Only the files in the manifest are run. `closette-tests.lisp` asks questions interactively, `bugs.lisp` is a saved mailing-list message,
  and `classbench`, `float-test` and `mflop-test` are benchmarks.
