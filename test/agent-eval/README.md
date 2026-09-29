# Common Lisp agent evaluation kit

A small, repeatable way to ask: **does giving a model a Common Lisp reference file
(`docs/agent/common-lisp-primer.md`) make its Common Lisp better?** It is also usable for any other question of the form
"how well does model X write plain Common Lisp?".

It grades on SBCL, not on Corman Lisp: it measures general Common Lisp skill, not Corman-specific behaviour.

## How it works

1. `make_prompt.py` prints a prompt: a set of small tasks ("define `(join-strings sep strings)` ...") with either no reference notes
   (control) or the primer prepended.
2. You give it to the model under test, **with no ability to run code** (otherwise you are measuring the tool, not the model),
   and have it write its answers in the layout `### task-id` followed by a fenced `lisp` block.
3. `grade.py` loads each task's code in a fresh SBCL process and evaluates that task's test forms. A task passes only if all pass.

```
python3 test/agent-eval/grade.py --set hard --selftest            # check the tasks themselves (needs sbcl)
python3 test/agent-eval/make_prompt.py --set hard > control.txt
python3 test/agent-eval/make_prompt.py --set hard --primer docs/agent/common-lisp-primer.md > primer.txt
python3 test/agent-eval/grade.py --set hard answer1.md answer2.md ...
```

Task sets: `easy` (28 tasks: 24 aimed at classic Lisp traps, 4 unrelated controls) and `hard` (17 tasks: longer forms, conditions and
restarts, CLOS method combination, macros, parsing; 4 controls). Each task has reference solutions and, for some, deliberately
naive ones (`--selftest` checks that the tests accept the former and reject the latter, so the tests do catch the classic mistakes).

## Results so far (one experiment, treat as preliminary)

Subjects: Claude haiku and Claude sonnet, each run with and without the primer (version 1, before the additions marked
"seen in trials"). Tasks passed out of the set size; one run is one model answering the whole set once.

| Set | Model | Without primer | With primer |
|---|---|---|---|
| easy (28) | haiku | 25, 27 | 25, 27 |
| easy (28) | sonnet | 28, 28 | 28, 28 |
| hard (17) | haiku | 15, 14, 15 | 15, 16, 13 |
| hard (17) | sonnet | 17, 16 | 17, 17 |

What this shows and does not show:

- **No measurable effect of the primer.** The haiku means are identical with and without it (26 of 28; 14.7 of 17), and the spread
  between runs of the same condition (13 to 16) is larger than any difference between conditions. Sonnet was at or near the ceiling
  everywhere. The four unrelated control tasks did not get worse.
- **The classic traps were mostly avoided without help.** `case` on strings, destructive `sort`, `\t` in strings, missing library
  functions, variable capture in macros: both models mostly got these right unprompted. That is the main reason the primer showed no
  lift: little headroom on the mistakes it targets.
- **The mistakes that did occur were different**, and they are now in the primer marked *(seen in trials)*: `return` inside a `loop`
  followed by a fallback form (twice), losing extra return values by wrapping a form in `let`, treating the second value of
  `ignore-errors` as a success flag, `vector-push-extend` on an array without a fill pointer (one cause behind three failed tasks),
  and, in one haiku run, unbalanced parentheses that made two solutions unloadable (what `test/tools/lispcheck.py` is for).
  Those additions were written after seeing these failures, so they are **untested**: re-running the same tasks would flatter them.
  A fair test needs new tasks.
- **Model differences:** haiku made more errors than sonnet on the same tasks (per-run scores 76 to 96% against 94 to 100%), and the kinds of error
  differed by run more than by model. One reference file is enough; nothing here supports writing per-model versions.

Limits: small samples (2 to 3 runs per cell), only two Claude models, one prompt format, tasks written by the same people as the primer
(so they favour it, and it still did not help), no statistical test, graded on SBCL. During the runs SBCL was made non-executable so
the subjects could not test their own code; they were also told not to read other files, which was not otherwise enforced.
A first round had a flaw (two solutions called a helper defined in another task's block); the prompt now requires self-contained
solutions and only the corrected wording is in `make_prompt.py`.

## Adding tasks

Append to `TASKS` in `tasks_easy.py` or `tasks_hard.py`: `id`, `kind` (`trap` if it targets something the primer covers, otherwise
`control`), a `prompt`, and `tests` (Lisp forms that must all be true). Add a reference solution to `ORACLE` in the matching
`oracle_*.py` (and optionally a `NAIVE` one showing the mistake you expect), then run `grade.py --set ... --selftest`.
Prefer tasks where the natural mistake gives a wrong result rather than an error message, and avoid tests that depend on hash table order.
