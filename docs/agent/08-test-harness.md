# 08. Test harness

`test/harness.lisp` runs the existing test files and writes machine-readable results.
`test/tools/results.py` summarises and compares runs. Purpose: an objective pass/fail signal for any change
(kernel, compiler, pathname layer, toolchain) that a person or agent can diff against a known-good run.

**Status:** written on Linux. The harness logic (recording, JSON output, error isolation, counting, comparison,
crash localisation) was exercised under SBCL 2.2.9 against the real `test/ansi-chapter-*.lisp` files. It has **not** been
run on Corman Lisp. The SBCL numbers are not Corman numbers; only the machinery was checked.

## Running it (Windows, fresh image)

```lisp
(load "test/harness.lisp")
(test-harness:run-all :label "vs2015-baseline")      ; writes test-results.jsonl in the current directory
```

or from the command line: `clconsole -execute test\run-tests.lisp` (edit the `:label` in that file; it passes `:exit t`,
which ends the process with code 0 or 1 through `ExitProcess`, so scripts can react to the result).

`run-all` keywords: `:output-file` (default `"test-results.jsonl"`), `:label`, `:files` (list of manifest file names to
run), `:trace-tests` (see crash localisation), `:exit`. Returns `T` when nothing failed or errored.

Use a fresh image. The harness redefines `VERIFY` and `DOTESTS` in `COMMON-LISP-USER`, the names used by
`test/ansi-examples.lisp`. Do not load `ansi-examples.lisp` into the same image afterwards.

## What it runs

The `*manifest*` in `harness.lisp`:

- `ansi-chapter-2` to `ansi-chapter-8`: HyperSpec examples in `DOTESTS` form. Each `expr => expected` is one result.
- `test-sequences`: 15 `DEFINE-TEST-SUITE` suites from `testkit.lisp`. Recorded **one result per suite** (pass when the suite reports 0 problems), with the suite's printed output kept in the record.

Deliberately excluded: `closette-tests.lisp` (asks questions via `y-or-n-p`), `bugs.lisp` (a saved mailing-list message,
not code), `classbench`, `float-test`, `mflop-test` (benchmarks). To add a file, add an entry to `*manifest*`.

Differences from `test/ansi-examples.lisp` (deliberate):

- An error in one example is recorded and the group **continues**; the original aborts the group.
- Judging rules are the same (`true`, `false`, `implementation-dependent`, `(values ...)`, otherwise `equalp`). Examples marked
  `implementation-dependent` are recorded as status `info` rather than counted as passes.
- Text a test prints is captured into the record instead of appearing on the console (`*capture-output*`).

## Output format (JSON Lines)

One object per line. Every record has `"type"`.

| type | fields |
|---|---|
| `environment` | `harness_version`, `label`, `implementation`, `version`, `features` (array), `started` (UTC) |
| `begin` | `file`, `suite`, `index`, `expr`. Only with `:trace-tests t`. Written and flushed before each test. |
| `result` | `file`, `suite`, `index`, `status` (`pass`, `fail`, `error`, `info`), `expr`, `expected`, `actual`, `output`, `message`, `ms` |
| `summary` | `totals`, `files` (per-file totals), `elapsed_ms` |

Values are printed with `prin1` (`*print-length*` 20, `*print-level*` 6, truncated to `*max-text*` = 400 characters).
Records are flushed as they are written, so a crash loses at most the current test.

## Comparing runs

```sh
python3 test/tools/results.py summary test-results.jsonl --failures
python3 test/tools/results.py diff baseline.jsonl new.jsonl        # exit 1 if anything regressed
python3 test/tools/results.py check new.jsonl                       # structural validation
```

`diff` matches tests by (file, suite, expression, occurrence) and reports regressions (pass or info to fail or error),
fixes, tests that are still failing but differently, new tests, and tests missing from the new run. `--strict` also fails
on missing tests or a damaged results file. `pass` and `info` changes are treated as neutral.

Typical use: run once on a known-good build, keep that file as the baseline, and diff every candidate build
(new toolchain, kernel change, image rebuild) against it.

### Crash or hang

If the process dies, the file has no `summary` record and `results.py` says so. Rerun with `:trace-tests t`; the last
`begin` record without a following `result` is the test that was running, and `results.py` prints it.
The harness cannot time-limit a test or survive a hard crash of the Lisp process. It catches Lisp errors, including the
`COMMON-LISP::%ERROR` throw Corman uses internally.

## Corman-specific assumptions that still need confirming **[unverified]**

These are the places where the harness relies on Corman behaviour that could not be checked here:

1. `HANDLER-CASE` with an `ERROR` clause catches errors signalled by the evaluated forms.
2. `*LOAD-TRUENAME*` is bound while `harness.lisp` loads, and `DIRECTORY-NAMESTRING` of it ends with a separator.
3. `WITH-OPEN-FILE ... :IF-EXISTS :SUPERSEDE` plus `FINISH-OUTPUT` flush a file stream.
4. `MAKE-HASH-TABLE :TEST 'EQUAL`, `MAPHASH`, `SORT` with `:KEY`, `DECODE-UNIVERSAL-TIME` with a time-zone argument.
5. `-execute` runs the file and `ExitProcess` is callable as `WIN32:EXITPROCESS` (it is declared in `Sys/win32.lisp`).
6. `(require "TESTKIT")` inside `test-sequences.lisp` is satisfied because the harness loads `testkit.lisp` first, which does `(provide "TESTKIT")`.
7. The `test-sequences` suite functions live in `COMMON-LISP-USER` (as that file declares).

If any of these fails, the first symptom will be an `error` record for `<load>` or an empty output file. Fix the harness, not the tests.

## Known limits

- No per-test timeout. An infinite loop hangs the run (use `:trace-tests t` to find it).
- Tests share global state, exactly as in the original runner (chapters `setq` undeclared variables and redefine functions). Results can depend on order.
- Only tests in the manifest are covered; the ANSI examples are a thin slice of the standard, not a conformance suite.
- `test-sequences` is per-suite, not per-example.
