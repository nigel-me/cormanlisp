# CLAUDE.md

Corman Lisp: a Common Lisp for 32-bit x86 Windows. It has a native-code compiler, an in-process COM
kernel written in C++/x86 assembly, a saved-image workflow, and a Win32/COM/.NET FFI.
MIT licensed (see `LICENSE.txt`; the 2000s-era manual still describes older license terms, so trust `LICENSE.txt`).

Detailed notes live in `docs/agent/` (start at `docs/agent/README.md`). This file is the short version.

## Ground rules for agents

- **You are probably on Linux; the product only builds and runs on Windows.** There is no Linux build.
  You cannot compile the C++ kernel or run Lisp here. Say so plainly rather than implying code was tested.
  Static reading, careful edits and CI-oriented work are what is possible.
- **Files use CRLF line endings** (`.lisp`, `.cpp`, `.h`, `.vcxproj`, `.bat`). Preserve them when editing.
  Check with `git ls-files --eol <file>` (`src_vc15.sln` is the exception: LF). Do not run whole-file reformatters or converters. A stray LF-only
  hunk makes a huge diff. New docs in `docs/agent/` and this file are LF.
- **Do not rewrite or "clean up" `Sys/*.lisp` casually.** They are loaded in a strict order to build the image
  (see `Sys/load-sys.lisp`, `Sys/load-sys2.lisp`). Never `LOAD` one on its own in a running image.
  A change can break the bootstrap in ways that only show up when the image is rebuilt.
- **The C++ kernel depends on compiler code generation.** `CormanLispServer/` uses MSVC-style `__asm`,
  `__declspec(naked)`, SEH and TEB access, and is built with optimisation disabled. See
  `docs/agent/05-kernel-and-runtime.md` before touching it. Treat a toolchain or compiler-flag change as a
  risky change even if it compiles.
- **Stay 32-bit.** Tagged 32-bit pointers, x86 code generation, `:32-bit` in `*features*`. There is no 64-bit port.
- Prefer small, local changes with a stated way to verify on Windows. If a change needs a Windows run to
  verify, say exactly which command or test to run.

## Layout

| Path | What it is |
|---|---|
| `Sys/` | Lisp sources for the system itself (compiler, CLOS, conditions, streams, pathnames, FFI, Win32). Order-dependent. |
| `Modules/` | Optional libraries loaded with `REQUIRE`/`LOAD` (ASDF, sockets/SSL, AllegroServe, XML-RPC, threads, Win32 wrappers). |
| `Libraries/` | Third-party Lisp code (s-xml, rdnzl, sql-odbc, acad). |
| `CormanLispServer/` | C++/asm kernel: GC, code generator (`Compx86.cpp`), reader/writer, COM server. Builds `CormanLispServer.dll`. |
| `CormanLispIDE/` | MFC IDE (`CormanLisp.exe`). |
| `clconsole/`, `clconsoleapp/`, `clboot/`, `clbootapp/` | Console and headless hosts. Also templates for `SAVE-APPLICATION`. |
| `dlltemplate/` | Template DLL that Lisp-defined DLL exports are stamped into. |
| `test/` | ANSI-example and CLOS tests (`ansi-examples.lisp` loads the chapters). |
| `examples/` | Small runnable examples: FFI, callbacks, COM, DLL creation, GUI. |
| `documentation/` | `CormanLisp.html/.pdf` manual and release notes. |
| `init.lisp` | Runs at top-level start. User customisation goes in `%USERPROFILE%\corman-init.lisp`. |
| `src_vc15.sln` | VS 2015 solution, toolset `v140_xp`, `Standard|Win32` only. |

## Building (Windows only)

1. Open `src_vc15.sln` in VS 2015 (toolset `v140_xp`) and build `Standard|Win32`.
2. Build the image with `makeimg.bat`. It runs `clconsole -execute sys\compile-sys.lisp` to produce `CormanLisp.img`.
3. `makemsi.bat` (needs WiX 3.x) and `makezip.bat` package a release.

Details and the modern-toolchain notes are in `docs/agent/02-building-and-testing.md`.

## Testing

There is no CI. Tests are Lisp files run from a Corman REPL or console (Windows only).
Machine-readable runs: `(load "test/harness.lisp")` then `(test-harness:run-all :label "...")`, or
`clconsole -execute test\run-tests.lisp`. That writes `test-results.jsonl`; compare runs with
`python3 test/tools/results.py diff baseline.jsonl new.jsonl` (works on any OS). Details, output format and
unverified assumptions: `docs/agent/08-test-harness.md`; human-oriented guide: `test/README.md`.
The older runner is still there: `(load "test/ansi-examples.lisp")` prints `PASSED:`/`FAILED:` lines.
Do not load both in one image.

## Conventions worth knowing before you edit Lisp

- Packages: `COMMON-LISP` (`CL`), `CORMANLISP` (`CCL`), `C-TYPES` (`CT`), `WIN32` (`WIN`), `PL`, `SYS`, `THREADS` (`TH`), `SOCKETS`, `IDE`.
  Most system files start with `(in-package :common-lisp)`.
- Pathnames are Windows-style. Namestrings print with backslashes but parsing accepts `/` or `\`.
  Only the `SYS` logical host exists. See `docs/agent/03-lisp-notes.md` for what is and isn't implemented.
- Compiled files are `.fasl`, tied to the exact image build. `COMPILE-FILE` can also append a fasl into an
  `.exe`/`.dll` when the output file has that extension.
- Windows APIs are declared with `#! ... !#` C-header blocks, `DEFUN-DLL`, `DEFWINAPI`. See `docs/agent/04-ffi-and-windows.md`.
- Tabs are used for indentation in most `Sys/` files. Match the file you are editing.
- New to Common Lisp or unsure of an idiom? `docs/agent/common-lisp-primer.md` is a short checklist of common mistakes
  (`case` on strings, `return` inside `loop`, lost multiple values, ...). This repo's `docs/agent/03-lisp-notes.md` wins where they differ.
  Check structure with `python3 test/tools/lispcheck.py <file>` after editing Lisp.

## Known gaps (short list)

`compile-file` always returns `nil` for warnings/failure flags; `probe-file` on directories, `translate-pathname`,
`pathname-match-p`, wild pathnames, and full logical pathnames are missing or incomplete; bundled ASDF is a 2003
revision; `external-format` is ignored. Full list with file references: `docs/agent/06-known-gaps.md`.

## Provenance

Statements in `docs/agent/` are marked **[source]** (read in this repo), **[manual]** (from
`documentation/CormanLisp.html`, which predates the 3.1 community release and may be stale) or
**[unverified]** (inferred, not tested). Treat **[unverified]** items as leads, not facts.
