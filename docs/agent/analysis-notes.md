# Analysis notes: the thinking so far

A summary of the analyses and recommendations from the first working session, so a later session (cloud or local) does not have to
rediscover them. It records conclusions and the reasons for them, not the full conversation. **Everything here comes from reading the code,
the manual and the upstream history, plus SBCL runs of the portable tooling. Nothing was built or run on Windows or Corman Lisp**, so treat
recommendations about behaviour as hypotheses to test. See `STATUS.md` for what to do next.

## 1. Quicklisp / ASDF compatibility (set aside by the owner)

Question: what would it take, without sacrificing Windows integration?

- **Verdict:** feasible; medium-to-large; no change to the Windows integration is needed. About half is risk-tolerant library work.
- **Present state:** bundled ASDF is revision 1.106 (2003), with `:broken-fasl-loader` pushed so it loads source, not fasls. No UIOP, no output
  translations, no `:package-inferred-system`. Quicklisp needs ASDF 2.x at least, and current systems assume ASDF 3.
- **Pathnames** (`Sys/filenames.lisp`, `directory.lisp`, `streams.lisp`): only the `SYS` logical host; `translate-pathname` and
  `pathname-match-p` not defined; no wild pathnames and `directory` only takes `:recurse`; `probe-file` probably fails on directories
  (inferred from Win32 semantics); `truename` is just `GetFullPathName`; `delete-file` does not signal errors; `native-namestring`,
  `getenv`, `run-program` absent. Parsing accepts `/` and `\`, namestrings print `\`; directory components are already `(:absolute "a" "b")`,
  which UIOP expects.
- **Compiled files:** fasls are raw heap objects and machine code with code-reference patching, referencing objects in the running image by
  position, and no build identity check was found. So they are only valid for the exact image, and ASDF's cache key needs a build-unique
  `implementation-identifier` (currently `machine-type` etc. return `NIL` and the version is just `major.minor`). `compile-file` returns
  `nil` for `warnings-p`/`failure-p`, and `with-compilation-unit` is a `progn`; ASDF 3 relies on both. `compile-file` can append a fasl
  into an `.exe`/`.dll` (a PE section) keyed on the output extension; that Windows feature does not conflict with ASDF and should be kept.
  `:output-file` is honoured, so ASDF output translations could redirect fasls.
- **Language dependencies:** CLOS is a Closette derivative (some MOP/method-combination features unconfirmed); `external-format`, `make-load-form`
  missing.
- **Quicklisp bootstrap:** needs an HTTP client; Corman has winsock sockets and SSL modules but no HTTPS client. WinHTTP via FFI would fit.
- **Recommended spike (never done):** try loading ASDF 3.3/UIOP from source on Windows and record failures; that best predicts effort.

## 2. Freeing the build from Visual C++ 2015

- **Facts:** all projects are pinned to `v140_xp`, Windows SDK 8.1, Win32 only. The kernel has MASM-style `__asm` (several hundred lines),
  about 30 `__declspec(naked)` functions forming the Lisp/C boundary, SEH (`__try/__except`), TEB access (`fs:0018h`), `setjmp`, and is built
  with optimisation disabled and `/safeseh:no`. The IDE is MFC. The original author warned that newer VS versions changed code generation in ways
  that broke the kernel's "very tight rules".
- **Options, in order of preference:** (A) the VS installer may still offer the v140 toolset as an optional component (unchecked); (B) retarget to
  MSVC v143 (VS 2022 Community, free for open source), still 32-bit, no code changes expected but the risk is behavioural, not syntactic;
  (C) clang-cl (accepts MS-style inline asm, naked, `__try`) as an experiment on top of B; (D) MinGW/GCC is large: MASM asm and x86 SEH unsupported
  and no MFC.
- **Guard rail:** any toolchain change must be judged by a rebuilt image plus the harness compared with a known-good baseline. This is why the harness
  and the `build` CI job exist. Stay 32-bit; a 64-bit port is a rewrite of the compiler and runtime.

## 3. Useful updates for agentic development (ideas, ranked)

Corman's distinctive strengths: a native compiler, a live saveable image, deep Windows/COM/.NET FFI, an in-process COM kernel, single-file
executables via `save-application`. Ideas: an MCP server / structured REPL so an agent can drive a live image; Windows automation (UI Automation,
Office COM); single-file agent tools; embedding as a scripting engine; a Lisp agent framework (needs an HTTPS/JSON client); better diagnostics and
structured `compile-file` results; a machine-readable test harness; and a knowledge pack for agents.
Ranking used: knowledge pack, then test harness, then MCP/structured REPL, then HTTPS/JSON, then Windows automation, then deployment stories.
The first two are done. The rest are in `STATUS.md`.

## 4. Testing and CI design

- **Harness rationale:** run the existing test files unmodified; one JSON line per test; errors isolated per example (the old runner aborted
  a group at the first error); `:trace-tests` writes a marker so a crash names the culprit; `results.py` diffs runs so builds can be compared.
  Failing HyperSpec examples are normal on Corman, so the gate is a regression against a baseline or an unfinished run, never an absolute pass rate.
- **SBCL as a proxy:** the portable machinery was tested under SBCL and found three real bugs (an unescaped docstring quote, swallowed console
  output, a missing-package error). Its limits: it finds syntax/logic errors, not Corman behaviour.
- **CI:** `tools-check.yml` (Linux, verified locally) runs on PRs. `windows.yml` (unverified) is manual until green: a red check on a PR from an
  untested workflow is noise. Windows runners are real x64 machines that run 32-bit programs natively, which makes them the trustworthy reference.

## 5. Where to run Windows tests

- A cloud session cannot run Windows. Options: the CI runner (ground truth), a local Windows machine or VM with Claude Code inside or reached with
  `claude remote-control` (runs a session on your computer that appears in the Claude Code app), or the Claude Desktop app.
- An **Intel Mac** VM (or Boot Camp) runs x86 Windows natively, so it is much better than an **M1** VM, which runs Windows for ARM and would run
  Corman under x86 emulation (dynamic code generation, TEB access, SEH and a page-fault GC mode make that risky, and results would not transfer to real x86).
  Check the hypervisor supports your macOS, and that Claude Code supports it (I believe it needs macOS 13+, which a 2016 MacBook Pro lacks).
- On a Windows checkout set `git config core.autocrlf false`; the repo stores CRLF.

## 6. A Common Lisp primer for agents

- Question: is a generic Lisp file useful, or does need vary too much by model? Answer reached: one implementation-neutral file, kept short, as a
  checklist of mistakes; do not write per-model versions.
- Evaluation (`test/agent-eval/`): haiku and sonnet with and without the primer on 45 small tasks graded by SBCL. **No measurable effect** at this
  sample size; haiku's means were identical, sonnet was at the ceiling. Classic traps were mostly avoided unprompted. The mistakes that did occur
  (`return` inside `loop` followed by a fallback form, losing values by wrapping a body, treating `ignore-errors`' second value as a flag,
  `vector-push-extend` without a fill pointer, unbalanced parentheses) were added to the primer as "seen in trials" and are untested.
  Flaws to remember: tasks written by the same author as the primer, small n, Claude models only, a first-round prompt that allowed cross-task helpers.

## 7. Working method lessons

- Tag claims **[source]**, **[manual]** or **[unverified]** and do not present unverified work as tested.
- Verify what can be verified on Linux (SBCL, actionlint, Python tools) before pushing; it caught real bugs.
- Keep repo-specific notes (`03-lisp-notes.md`) authoritative over generic ones (the primer).
- Do not disturb CRLF files; check `git ls-files --eol`.
