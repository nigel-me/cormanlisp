# 02. Building and testing

## What an agent on Linux can and cannot do

- **Cannot:** build the kernel, run any Lisp, rebuild the image, run tests. Corman Lisp is a Windows x86 program.
  It is reported to run under Wine **[manual: README]**, but it has not been tried in this environment and I would
  not rely on it. Treat "no Windows available" as the default and say so in your reports.
- **Can:** read and edit source, review changes, write documentation and scripts, prepare project-file or CI edits,
  and do static checks (grep, balanced-paren checks, CRLF checks).

## Building on Windows **[source]**

The solution is `src_vc15.sln`, single configuration `Standard|Win32`. All projects use toolset `v140_xp`
(Visual Studio 2015 with Windows XP targeting), Windows SDK 8.1.

| Project | Output | Notes |
|---|---|---|
| `zlib` | `zlib.lib` | Bundled. |
| `CormanLispServer` | `CormanLispServer.dll` and import lib | The kernel. Linker options `/MACHINE:I386 /safeseh:no`. Optimisation disabled. Buffer security checks off. |
| `CormanLispStatic` | `CormanLispStatic.lib` | Makefile-type project. Runs `makestaticlib.bat`, which `lib`s together the kernel object files. |
| `dlltemplate` | `dlltemplate.dll` | Template for DLLs produced by Lisp. Links `msvcrt.lib;vcruntimed.lib;ucrtd.lib` by name. |
| `clboot`, `clbootapp` | `clboot.exe`, `clbootapp.exe` | Headless hosts. |
| `clconsole`, `clconsoleapp` | `clconsole.exe`, `clconsoleapp.exe` | Console hosts. Post-build embeds a manifest with `mt`. |
| `CormanLisp` (IDE) | `CormanLisp.exe` | MFC, dynamic. |
| `CormanLispImage` | `CormanLisp.img` | Makefile-type. Depends on `clconsole`. |
| `Installer` | MSI | Makefile-type. Needs WiX 3.x (`candle`, `light`). |

Then rebuild the image: `makeimg.bat`. It deletes the old `CormanLisp.img`, runs the bootstrap through
`sys\compile-sys.lisp`, and saves a new image. `delimg.bat` removes it. `makezip.bat` repacks an MSI into a zip;
the commented-out lines copy the VC140 runtime and MFC DLLs next to the executables.

### Toolchain constraints **[source, plus unverified consequences]**

- The kernel contains MASM-style inline assembly (`__asm`), about 30 `__declspec(naked)` functions (32 occurrences), SEH
  (`__try/__except`), `fs:0018h` (TEB) access, and `setjmp`. Optimisation is off because the assembly assumes the
  compiler's frame layout.
- The original author noted that newer Visual Studio versions changed code generation in ways that broke the
  kernel's "very tight rules about how it expects its code to look" **[manual: README quote from Roger Corman]**.
  The 3.1 community release used VS 2015 successfully.
- Consequence **[unverified]**: a newer MSVC or clang-cl might build cleanly and still misbehave in the GC, FFI or
  exception paths. Any toolchain change needs a rebuilt image plus the full test set compared against a known-good build.
- MinGW/GCC is not a drop-in alternative **[unverified]**: MASM-syntax `__asm`, x86 SEH and MFC are all unsupported there.

## Running tests **[source]**

There is no CI and no test runner script. Tests are Lisp files loaded into a running Corman Lisp:

```lisp
;; from the install directory, in the console or IDE
(load "test/ansi-examples.lisp")     ; loads test/ansi-chapter-2 .. 8
```

- `test/ansi-examples.lisp` defines `dotests` and `verify`. Each example is `expression => expected`.
  Output lines are `PASSED: ...` and `**************` / `FAILED: expr => result  Expected: ...`.
  A quick pass/fail summary can be made by counting those markers in captured output.
- `verify` stops testing a group on the first unhandled `error` (it warns and returns), so one error hides the
  rest of that group.
- Other files: `closette-tests.lisp`, `classbench.lisp`, `float-test.lisp`, `mflop-test.lisp`, `bugs.lisp`,
  `test-sequences.lisp`, and `testkit.lisp` (`DEFINE-TEST-SUITE`, from 1998).
- Regression testing after a kernel change: rebuild the image, run all of `test/`, and diff the output against a
  run on a known-good build.

### Machine-readable runs

`test/harness.lisp` wraps these files and writes JSON Lines results; `test/tools/results.py` summarises and diffs them.
See [08](08-test-harness.md).

### Console

`clconsole.exe` starts a console REPL. `-execute file.lisp` runs a file **[source: `makeimg.bat`]**. `-image ""` is passed when building the image, presumably to start
without loading one **[unverified]**. The console prompt is `?`; `:quit` exits **[source: `init.lisp`]**.
Use the console for anything scripted or agent-driven. It has no GUI dependency.

## Startup files **[manual]**

- `init.lisp` in the install directory runs for every instance.
- `%USERPROFILE%\corman-init.lisp` is the per-user file (since 3.1). Prefer it for personal settings.
- 3.1 no longer assumes write access to the install directory. Output (images, executables, crash dumps) goes to
  `%USERPROFILE%\Documents\Corman Lisp\` for the IDE, or the current directory for the console.
- The installer sets `%CORMANLISP_HOME%` to the install directory.

## Verification checklist for changes that cannot be run here

1. State what you changed and what you could not run.
2. Give the exact Windows-side steps: which project to rebuild, whether the image must be rebuilt, which test files to load.
3. For `Sys/` changes, say which earlier or later files the change interacts with (see the load order in [01](01-repo-map.md)).
4. Keep CRLF. Check `git diff --stat` for whole-file changes that indicate a line-ending accident.
