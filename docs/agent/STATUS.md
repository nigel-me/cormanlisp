# Status and handoff

Read this first when picking the work up in a new session (cloud or local). A session's conversation is **not** stored in the
repo and a cloud container is temporary, so this file is the memory. **Update it at the end of every working session**: move
finished items to "Done", keep "Open tasks" honest, and date the changes.

Last updated: 2026-09-29. Branch `claude/sharp-heisenberg-51u1x4`, pull request nigel-me/cormanlisp#1.
Start with `CLAUDE.md`, then `docs/agent/README.md`. The reasoning behind the recommendations is in `docs/agent/analysis-notes.md`.

## What this project is, and the user's goals

An open-source Corman Lisp (32-bit x86 Windows Common Lisp with a native-code compiler and a C++/asm kernel). The owner is
evaluating what could be done with it. Explored so far, in order: Quicklisp/ASDF compatibility (**set aside by the owner**),
freeing the build from Visual C++ 2015, useful modernisation for agentic development, and making the repo workable for coding agents.
Constraint stated by the owner: do not sacrifice the good Windows integration for compatibility.

## Done (all pushed; commits on the branch)

| Commit | What |
|---|---|
| `8ac3e80` | `CLAUDE.md` and the knowledge pack `docs/agent/01`-`07` (repo map, build/test, Lisp notes, FFI, kernel/runtime, known gaps, workflows) |
| `9149ce3`, `f5bbf77` | Test harness: `test/harness.lisp`, `test/run-tests.lisp`, `test/tools/results.py`, human guide `test/README.md`, `docs/agent/08-test-harness.md` |
| `1463d5d` | `test/tools/lispcheck.py` structural checker for Lisp files |
| `881b946` | `docs/agent/common-lisp-primer.md` and the evaluation kit `test/agent-eval/` |
| `17fcc99` | `.github/workflows/tools-check.yml` (Linux, on PRs) and `windows.yml` (manual), scripts, `docs/agent/09-ci.md`, `test/baselines/README.md` |

## What has and has not been verified

- **Verified (run on Linux, under SBCL):** the harness machinery against the real ANSI chapter files (847 results, error isolation, crash
  localisation), `results.py`, `lispcheck.py` over all repo Lisp files, the evaluation kit's tasks, and every command in `tools-check.yml`.
- **Never run on Corman Lisp or Windows:** the harness itself on Corman (seven assumptions are listed in `08-test-harness.md`), the whole
  `windows.yml` workflow and its PowerShell scripts, and every statement in `docs/agent/` tagged **[unverified]**.
- No code in `Sys/` or `CormanLispServer/` has been changed. Nothing has been built.

## Open tasks (suggested order)

1. **Run `windows.yml`, job `release-test`** (Actions tab, Run workflow). Fix whatever breaks in the harness or scripts. Then commit
   the results as `test/baselines/release.jsonl` (see `test/baselines/README.md`). This is the first real evidence about Corman behaviour.
   If the owner has an x86 Windows machine or VM (an Intel Mac VM was recommended over the M1's ARM emulation), the same steps work locally:
   `clconsole -execute test\run-tests.lisp`, then `python test\tools\results.py summary test-results.jsonl --failures`.
2. **Run the `build` job** to learn whether Visual Studio 2022 (toolset v143) can build the kernel and console and whether the result
   passes the same tests. Keep the build logs. Also check whether the VS installer still offers the old `v140` toolset component.
   Decision pending on toolchain direction (see `docs/agent/05-kernel-and-runtime.md` for why this is risky).
3. **Add `pull_request:` to `windows.yml`** once both jobs are green and baselines are committed.
4. **Structured `compile-file` results** (real `warnings-p`/`failure-p`, `with-compilation-unit`): proposed next code change, in
   `Sys/compile-file.lisp`. Needs a Windows run and an image rebuild to verify; use the harness to prove no regressions.
5. **Pathname and file layer fixes** (wild pathnames, `translate-pathname`, `pathname-match-p`, directory-aware `probe-file`,
   error-signalling `delete-file`): see `docs/agent/06-known-gaps.md`. Also groundwork for the set-aside Quicklisp/ASDF path.
6. **Build identity for fasls** (version in `lisp-implementation-version`/`machine-version` and in fasl headers).
7. Ideas ranked earlier but not started: an MCP server or structured REPL so an agent can drive a live Corman image; HTTP/JSON/TLS
   client (WinHTTP via FFI); UI Automation and Office COM toolkit; single-file agent tools via `save-application`.
8. Small things: a `.gitattributes` to pin line endings; a fresh task set to test the primer's "seen in trials" items
   (`test/agent-eval/README.md`); updating OpenSSL 1.1.x (end of life).

## Decisions and constraints to keep

- Stay 32-bit x86. No 64-bit port is planned.
- Treat a toolchain or compiler-flag change as risky; only accept it with a baseline comparison from the harness.
- Preserve CRLF line endings (except `src_vc15.sln`, LF). **On a Windows checkout set `git config core.autocrlf false`**, otherwise Git
  rewrites every line. Docs under `docs/agent/` and root-level docs are LF.
- Do not create a pull request unless asked (PR #1 already exists for this branch). Commit messages end with the attribution lines the
  session was given.
- Do not describe unverified things as tested. Tag them.
- Test failures are normal on Corman (HyperSpec examples); what matters is regressions against a baseline.

## Known defects found along the way (not fixed)

- `Libraries/sql-odbc-0.85/doc/sql-odbc-documentation.lisp` is truncated mid-sentence with NUL bytes and an unterminated `#|`.
- `test/bugs.lisp` is a saved mailing-list message, not code.
- The manual's license text is outdated; `LICENSE.txt` (MIT) is authoritative.

## Not in the repo

The full conversation transcript, and the reasoning that led to these decisions except as summarised in `analysis-notes.md`.
The raw answers from the primer evaluation are saved in `test/agent-eval/results/`. Scratch files and tools installed in the cloud
container (`sbcl`, `actionlint`) are not kept; both are quick to reinstall.

## Environment notes for cloud sessions

- `sbcl` can be installed with `apt-get install sbcl` and is used to check the portable parts of Lisp code. It cannot run Corman-specific code.
- `actionlint` (from pip, `actionlint-py`) lints the workflows. `pwsh` was not available, so PowerShell scripts could not be run.
- GitHub access is limited to this repository.
