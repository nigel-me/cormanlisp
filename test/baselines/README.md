# Test baselines

Known-good results files that the Windows workflow (`.github/workflows/windows.yml`) compares new runs against.
If a file below exists, a run that has tests passing in the baseline but failing now is reported as a regression and the job fails.
If it does not exist, the run is only summarised.

| File | Compared with | How to create it |
|---|---|---|
| `release.jsonl` | the harness run against a released Corman Lisp build (`release-test` job) | run the workflow, download the `results-release` artifact, and commit `release.jsonl` here |
| `build.jsonl` | the harness run against a build from source (`build` job) | run the workflow, download the `build-logs-and-results` artifact, and commit `results/build.jsonl` here as `build.jsonl` |

Commit a baseline only from a run you have looked at and accept as the reference (it should have finished, with a `summary` record;
`python3 test/tools/results.py check <file>` says so). Failing tests in a baseline are fine: only changes from passing to failing count as regressions.
The `label`, timestamps and timings inside the file do not matter to the comparison.
