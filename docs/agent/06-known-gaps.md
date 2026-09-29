# 06. Known gaps and rough edges

Everything here was found by reading the code. **Nothing was run.** "Impact" is a judgement.

## Language and library

| Gap | Where | Impact |
|---|---|---|
| `compile-file` returns `NIL` for `warnings-p` and `failure-p` always | `Sys/compile-file.lisp` (`compile-file`) | Build tools that key on compile results (ASDF 3) treat every compile as clean. |
| `with-compilation-unit` is a plain `progn` (defined twice in one file) | `Sys/compile-file.lisp` | No deferred warnings. |
| `external-format` ignored in `compile-file`, `load`, `open` | `Sys/compile-file.lisp`, `Sys/streams.lisp` | No real UTF-8/UTF-16 handling. Modern text I/O needs care. |
| `make-load-form` not implemented | listed in `Sys/cl-symbols.lisp` only | Literal objects of user classes can't be dumped to fasls. |
| Only the `SYS` logical host; `logical-pathname*` are stubs | `Sys/filenames.lisp`, `Sys/logical-pathname.lisp` | Logical pathnames effectively unsupported. |
| `translate-pathname`, `pathname-match-p` missing | `Sys/cl-symbols.lisp` lists symbols only | Blocks ASDF output-translations and source registry. |
| No wildcards in the pathname parser; `directory` takes only `:recurse` | `Sys/filenames.lisp`, `Sys/directory.lisp` | No `**/*.lisp` style searches. |
| `probe-file` likely fails on directories | `Sys/streams.lisp:192` **[unverified]** | Directory-existence checks misbehave. |
| `truename` only normalises to a full path | `Sys/filenames.lisp` (`get-full-path-name`) | No existence check, no symlink or case resolution. |
| `delete-file` doesn't signal on failure | `Sys/streams.lisp` | Callers can't detect failure. |
| `native-namestring`, `getenv`, `run-program` not provided | grep found none | Portability layers need their own versions. |
| `machine-type`, `machine-version`, `machine-instance` return `NIL`; version is `major.minor` | `Sys/misc-utility.lisp`, `Sys/version.lisp` | Weak implementation identifier, which matters for fasl caching. |
| Fasls carry no build identity check | `Sys/compile-file.lisp` header writing/reading | Stale fasl after an image rebuild may misbehave **[unverified]**. |
| Bundled ASDF is revision 1.106 (2003), with `:broken-fasl-loader` pushed | `Modules/asdf.lisp:112` | Not compatible with Quicklisp or modern `.asd` files. |
| CLOS is a Closette derivative | `Sys/clos.lisp` | Some advanced CLOS/MOP features unconfirmed (see [03](03-lisp-notes.md)). |
| Conditions are only partly used by library functions | manual ch. 15 **[manual, may be stale]** | Error handling by condition type may not work for library errors. |
| Threads: many library functions not thread safe | manual ch. 20 | Concurrent use is risky. |
| Packages: no local nicknames | `Sys/defpackage.lisp` **[unverified]** | Modern library code that relies on them won't load. |
| 32-bit only, x86 only | `*features*`, kernel design | No 64-bit port; large heaps limited. |

## Build and platform

| Gap | Where | Impact |
|---|---|---|
| Requires VS 2015 toolset `v140_xp` | `src_vc15.sln`, all `.vcxproj` | Old, hard to obtain. See toolchain notes in [02](02-building-and-testing.md). |
| Kernel written to MSVC-x86-specific asm, naked functions, SEH | `CormanLispServer/` | Other compilers need substantial rewrites. See [05](05-kernel-and-runtime.md). |
| MFC IDE | `CormanLispIDE/` | Ties the IDE to MSVC and to Windows. |
| `dlltemplate` links CRT libraries by name (`vcruntimed.lib`, `ucrtd.lib`) | `dlltemplate.vcxproj` | Fragile across toolchain versions. |
| CI exists only for the tooling; the Windows workflow is manual and has never run | `.github/workflows/` | Nothing yet catches Corman Lisp regressions automatically. See [09](09-ci.md). |
| OpenSSL 1.1.x prebuilt DLLs committed | repo root | End of life; security-relevant. |
| Runtime redistribution steps commented out in `makezip.bat` | `makezip.bat` | Release packaging needs manual care. |
| `WINVER 0x0501` (XP) | `CormanLispIDE/include/Stdafx.h` | Old platform floor. |
| `MODULES`/`SYS` are added by uppercase names in `init.lisp` | `init.lisp` | Case-insensitive on Windows, but be mindful when moving to other file systems. |

## Documentation drift

- The manual (`documentation/CormanLisp.html`) still contains the old license paragraph. `LICENSE.txt` (MIT) is authoritative.
- The manual says the kernel is built with VS 2005. The 3.1 notes say VS 2015.
- The manual's CLOS and conditions sections describe the 2.x/3.0 state. Check the source before trusting them.

## Suggested follow-ups (from the analysis that produced this pack)

1. Machine-readable test output and a CI job that at least builds the solution.
2. Structured `compile-file` results and real `warnings-p`/`failure-p`.
3. Pathname layer: wild pathnames, `translate-pathname`, `pathname-match-p`, directory-aware `probe-file`, error-signalling file operations.
4. A build identity in `lisp-implementation-version` / `machine-version` and in fasl headers.
5. A structured REPL / MCP server so an agent can drive a persistent image.
