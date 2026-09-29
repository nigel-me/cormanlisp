# 03. Lisp notes: what differs from a typical Common Lisp

Corman Lisp is close to ANSI but not complete **[manual]**. This file lists behaviours that matter when writing or
porting code. Every item is tagged.

## Environment identity **[source]**

- `*features*` is set in `Sys/package.lisp`: `:cormanlisp :pl :common-lisp :win32 :os-windows :x86 :32-bit :little-endian :hardware-gc :datagram-sockets`.
  `:ipv6` is pushed at load time when IPv6 is installed (`Sys/sockets.lisp`).
- `(lisp-implementation-type)` is `"Corman Common Lisp"`. `lisp-implementation-version` returns `"major.minor"` from the kernel version string. `machine-type`, `machine-version`, `machine-instance` are stubs returning `NIL`.
- `(cormanlisp-client-type)` returns `:console-client`, `:ide-client` or `:win-app-client`.
- Reader conditionals for this system: `#+cormanlisp`.

## Packages **[source]**

| Package | Nickname | Purpose |
|---|---|---|
| `COMMON-LISP` | `CL` | Standard symbols plus most implementation internals (system files use `(in-package :common-lisp)`). |
| `CORMANLISP` | `CCL` | Implementation extensions and internals. Exports like `ccl:save-application`-family and `ccl:*auto-update-enabled*`. |
| `C-TYPES` | `CT` | FFI types, structs, `defun-dll`, callbacks, C strings. |
| `WIN32` | `WIN` | Win32 API wrappers and constants. |
| `PL` | | Kernel-level assembler/compiler internals. |
| `SYS`, `PATHNAMES` | | Internal. `PATHNAMES` holds the `pathname-internal` structure. |
| `THREADS` | `TH` | Threads. Needs `(require "THREADS")`. |
| `SOCKETS` | | Sockets and HTTP helpers. |
| `IDE` | | IDE integration (colours, menus, indenting). |

`defpackage` is implemented in `Sys/defpackage.lisp`. Package-local nicknames and other newer extensions are not present **[unverified]**.

## Pathnames **[source: `Sys/filenames.lisp`, `Sys/logical-pathname.lisp`, `Sys/directory.lisp`]**

- Representation: the structure `pathnames::pathname-internal` with slots `host device directory name type version defaults case logical`. `pathnamep` tests for it. `equal`/`equalp` on pathnames go through `pathname=` (`Sys/misc.lisp`, `Sys/misc-utility.lisp`).
- Directory components are lists `(:absolute "a" "b")` or `(:relative "a")`. Device is a drive letter string, e.g. `"C"`.
- Parsing accepts `/` and `\`. `namestring` output uses `\`. `directory-namestring` ends with `\`.
- Parsing is backward from the end of the string. A single token with no dot and no separator becomes the *name* with no type. Parsing does not recognise wildcards; `*` is just a character in a name.
- `MAKE-PATHNAME` is `make-pathname-internal`. A separate `make-pathname-hs` (JP Massar) does extra validation and warns when `*portable-pathname-components*` is true. It is not the default.
- `MERGE-PATHNAMES`: handles `:relative` directories by appending to the default and removes `<dir> :back` pairs. Version defaults to `:newest` unless the name is supplied.
- `TRUENAME` is `GetFullPathName` only. It does not check existence and does not resolve links or case.
- `PROBE-FILE` calls `truename` then tries `CreateFile(GENERIC_READ, OPEN_EXISTING)`. Because no backup-semantics flag is passed, **[unverified]** it will return `NIL` for directories.
- Logical pathnames: only the host `SYS` is registered. `logical-pathname`, `logical-pathname-translations`, and `load-logical-pathname-translations` are stubs (`Sys/filenames.lisp`), so the working parser in `logical-pathname.lisp` is not fully wired in.
- Missing or stubbed: `translate-pathname`, `pathname-match-p` (symbols listed in `cl-symbols.lisp` only), wild pathnames in `directory`, `native-namestring`.
- `DIRECTORY`: `(directory spec &key recurse)`. Uses `_findfirst/_findnext` on the `truename` of the spec. It returns files only (subdirectories are separate: `directory-subdirs`, `directory-files-and-subdirs`).
- `ENSURE-DIRECTORIES-EXIST` calls `truename` first then `CreateDirectory` on each prefix, ignoring failures for existing ones.
- `RENAME-FILE` is a fuller implementation using `MoveFile`. `DELETE-FILE` returns the Win32 result and does not signal on failure.
- `FILE-WRITE-DATE` opens the file to read its times. It does not work on directories.
- `*default-pathname-defaults*` is reset from the current directory on image restore.
- `USER-HOMEDIR-PATHNAME` is implemented (`Sys/misc-utility.lisp`).

## Files: compile and load **[source: `Sys/compile-file.lisp`]**

- Source extensions searched: `.lisp`, `.lsp`, `.cl`. Compiled extension: `.fasl`.
- `COMPILE-FILE` accepts `:output-file`, `:verbose`, `:print`, `:external-format` (the last two are ignored). It returns `(values output-file nil nil)`; the second and third values are always `NIL`.
- `COMPILE-FILE-PATHNAME` defaults to the source's `truename` with type `fasl`, next to the source.
- If the output file has type `EXE` or `DLL`, the fasl is appended as a `.fasl` PE section of that file (`file-is-executable`).
- `LOAD` with no file type prefers whichever of `.lisp` / `.fasl` is newer. It also falls back to looking in the Corman Lisp install directory. `LOAD` binds `*load-pathname*` and `*load-truename*`.
- Fasl format: 128-byte header (magic `COCL`), optionally gzip-compressed body (`*compress-fasl-files*` defaults to true). The body is raw heap objects and machine code with code-reference patching. It references objects that already exist in the running image through a positional table, so **a fasl is only valid against the image build that produced it** **[unverified]**: no version or checksum check was found.
- `WITH-COMPILATION-UNIT` is defined twice (`Sys/compile-file.lisp`) and is a plain `progn`.
- `MAKE-LOAD-FORM` is not implemented **[source: only listed in `cl-symbols.lisp`]**.
- `REQUIRE` / `PROVIDE` (`Sys/require.lisp`) search registered module sources, then `*module-default-directories*` for `<name>.fasl` then `<name>.lisp`. `init.lisp` adds `MODULES` and `SYS`. `(ccl::register-module-source name paths)` and `(ccl::push-module-directory dir)` extend the search.

## CLOS **[source + manual]**

- Based on Closette and heavily modified (`Sys/clos.lisp`). `DEFMETHOD` without `DEFGENERIC` works. EQL specializers, `with-slots`, class and method redefinition are supported. Existing instances are not updated properly on class redefinition **[manual]**.
- Present: `change-class`, `initialize-instance`, `reinitialize-instance`, `shared-initialize`, `update-instance-for-different-class`, `class-precedence-list`, `add-method`, `remove-method`, `find-method`, `compute-applicable-methods-using-classes`, `print-object`.
- Not established either way **[unverified]**: `define-method-combination`, method combination other than the standard one, `:allocation :class`, `no-next-method`, `update-instance-for-redefined-class`, `make-load-form` integration, full MOP.
- `DEFSTRUCT` structures have their own classes and can specialise methods.

## Conditions **[source + manual]**

- `define-condition`, `make-condition`, `handler-bind`, `handler-case`, `restart-case`, `compute-restarts`, `invoke-restart`, `ignore-errors` exist (`Sys/conditions.lisp`).
- The manual says few library functions signal proper conditions **[manual, may be stale]**. Some paths use `(error "format string" ...)` with a string, and `OPEN` errors are generic.
- Win32 exceptions (access violation, stack overflow, and so on) are translated into Lisp conditions in `Sys/win-conditions.lisp` and `CormanLispServer.cpp`.

## Threads **[manual, source]**

- Package `THREADS`, loaded by `(require "THREADS")`. `create-thread`, `exit-thread`, `suspend-thread`, `resume-thread`, `terminate-thread`, critical sections, `with-synchronization`. `Modules/mp.lisp` is a separate multiprocessing library.
- Special variable bindings are per thread; the outermost (global) value is shared **[manual]**.
- Many library functions are not fully thread safe **[manual]**. Do not assume so without checking.

## Memory **[manual]**

- Generational, copying, compacting collector in the kernel. Objects move. Do not keep raw addresses of Lisp objects across calls that may allocate. FFI code must pin or copy (see [04](04-ffi-and-windows.md)).
- The experimental hardware-assisted mode is toggled with `ccl::enable-hardware-gc` and queried with `hardware-gc-enabled-p`.

## Idioms you will see in `Sys/`

- Tab-indented code, `;;;;` file headers with author and history, `(in-package :common-lisp)` at the top.
- `uref`/`uref-set` and `*-offset` constants for raw uvector access (symbols, packages, streams).
- `(declaim (ftype ...))` and stub `defun`s used as forward references, later redefined.
- `(setq *compiler-warn-on-undefined-function* nil)` around forward references.
- Assembly written in Lisp with `pl:defasm` and `{ ... }` blocks (see `Sys/compile-file.lisp`, `Sys/assembler.lisp`).

## Portability tips

- `#+cormanlisp` / `#-cormanlisp` in shared code. `#+win32` works too.
- Do not assume a POSIX file system, `~`, or `/` as the only separator.
- Avoid depending on `external-format`, `make-load-form`, `pathname-match-p`, `translate-pathname`, wild `directory`.
- Windows line endings: `open` in text mode; check `Sys/streams.lisp` before assuming LF-only behaviour **[unverified]**.
