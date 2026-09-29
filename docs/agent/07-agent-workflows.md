# 07. Agent workflows and safe verification

## Before any edit

1. Check whether you can run anything. On Linux the answer is no. Plan around static verification.
2. Locate the definition you're changing **and any later redefinition** (`grep -n "(defun name" Sys/*.lisp`).
   Many functions are stubbed early in `Sys/` and redefined later.
3. Check line endings: `git ls-files --eol <file>` should show `i/crlf w/crlf`. Keep it that way.
4. Look at the surrounding style: tabs vs spaces, `;;;;` headers, comment density.

## Useful greps

```sh
grep -rn "(defun NAME\b" Sys Modules              # find all definitions, including stubs
grep -rn "load-file \"sys/" Sys/load-sys*.lisp     # image build order
grep -rn "NAME" Sys/cl-symbols.lisp                # is the symbol merely listed, or defined?
grep -rn "__asm\|__declspec(naked)" CormanLispServer  # kernel asm hot spots
grep -rIl "#+cormanlisp\|#-cormanlisp" .           # implementation-conditional code
```

A symbol appearing in `Sys/cl-symbols.lisp` or `Sys/hyperspec.lisp` does **not** mean it is implemented.
Those files are symbol tables and documentation indexes.

## Static checks worth doing on Lisp edits

- Balanced parentheses, strings and `#| |#` blocks: run `python3 test/tools/lispcheck.py <file>` (no Lisp needed; understands
  Corman's `#! ... !#` blocks, `#\(` character literals, `|symbols|`). It reports the line and column of an unclosed or stray
  parenthesis, and hints at the likely culprit when a column-1 `(` appears inside an open form.
  It checks structure only, not that the file loads. Do not use a tool that reformats or re-indents; it would change CRLF/tab style.
- No new forward reference to something defined later in the load order.
- If you add a new file to `Sys/`, add a `load-file` line in the right place in `load-sys2.lisp` and say why that position.
- If you add an exported symbol, check the package's `:export` list or `cl-symbols.lisp` conventions.

## Common tasks

### Adding a Lisp library function (not in `Sys/`)

Prefer `Modules/` and load with `REQUIRE`. Modules avoid the image-build ordering risk.
Register autoloading with `ccl:define-autoloaded-module` if it should be available without an explicit `REQUIRE`
(see the end of `Sys/load-sys2.lisp`).

### Adding a Win32 API binding

1. Check `Sys/win32.lisp` and `Modules/win*.lisp` first. It may exist.
2. Add a `#! ... !#` block or a `defwinapi` in the right module. Use `:pascal` for stdcall.
3. Add a small example under `examples/` if it demonstrates something non-obvious.

### Fixing a pathname or file function

1. Read [03](03-lisp-notes.md) and the definitions in `Sys/filenames.lisp`, `Sys/directory.lisp`, `Sys/streams.lisp`.
2. Check the effect on `compile-file`, `load`, `require`, `save-application`, `directory`, `ensure-directories-exist`, `Modules/asdf.lisp`. They all lean on these.
3. Provide a test file under `test/` in the existing `dotests`/`=>` style, and say it needs a Windows run.

### Fixing a compiler or kernel bug

1. Reproduce on Windows first. Get a minimal form and its disassembly (`disassemble`).
2. Decide whether the fix is in Lisp (`Sys/compiler.lisp`, `Sys/assembler.lisp`) or the kernel (`Compx86.cpp`). Prefer Lisp where possible. The original author moved logic out of the kernel on purpose. **[manual: README quote]**
3. For kernel changes, follow the rules in [05](05-kernel-and-runtime.md) and plan a full image rebuild plus a full test run.

### Documentation changes

Keep the manual as is unless asked. Update this pack's provenance tags when you confirm or refute something.

## Reporting

A good report for this repo says:

- What changed, in which files.
- What was verified statically and how.
- What could not be run, and the exact Windows steps to verify.
- Any **[unverified]** claim you relied on.
