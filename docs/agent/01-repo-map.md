# 01. Repo map

## Top level

| Path | Notes |
|---|---|
| `CormanLispServer/` | The kernel: C++ and x86 assembly. Builds `CormanLispServer.dll`, an in-process COM server, and a static-library variant used by the `*app` hosts. `src/` has `Gc.cpp` (collector), `Compx86.cpp` (x86 code generator), `Lisp.cpp` and `Lispfunc.cpp` (runtime and kernel functions), `LispMath.cpp`, `Read.cpp`/`Write.cpp`, `Unassemble.cpp` (uses bundled `distorm/`), `CormanLispServer.cpp` (exceptions, thread setup), `CoCormanLisp.cpp` (COM object). Headers in `include/`, notably `Lisp.h` (tagging and many asm macros). |
| `CormanLispIDE/` | MFC application (`CormanLisp.exe`): editor windows, worksheet, embedded web browser control (`webbrowser.cpp`, `browser.cpp`), `oleaccproxy.cpp`. |
| `clconsole/`, `clconsoleapp/` | Console host. `clconsole` uses the DLL; `clconsoleapp` links the kernel statically. Both are templates for `SAVE-APPLICATION`. |
| `clboot/`, `clbootapp/` | Headless hosts with no UI of their own (same DLL/static split). The Lisp program must do its own I/O. |
| `dlltemplate/` | Template DLL with placeholder exports (exports named `CCL__F0xx`, up to `CCL__F100`) that `Sys/compile-file.lisp` fills with Lisp-defined exported functions. |
| `Sys/` | ~109 Lisp files that make up the system image. Order-dependent. |
| `Modules/` | Optional libraries. Loaded via `REQUIRE`, `LOAD`, or autoload hooks. |
| `Libraries/` | Third-party code: `s-xml`, `rdnzl` (.NET bridge), `sql-odbc-0.85`, `odbc`, `acad`. |
| `test/` | Test files. See [02](02-building-and-testing.md). |
| `examples/` | Runnable samples. Good idioms for FFI, callbacks, COM, DLL creation, GUI apps. |
| `Utilities/` | Build-time helper scripts (version file for WiX, HyperSpec install, license conversion). |
| `installer/` | WiX 3.x sources for the MSI. |
| `zlib/` | Bundled zlib. Used for image and fasl compression. |
| `include/` | Shared C headers. |
| `documentation/` | Manual (`CormanLisp.html/.pdf/.doc`) and release notes 1.21 to 3.1. |
| `HyperSpec-7-0.tar.gz`, `Utilities/install-hyperspec.lisp` | HyperSpec, installed on demand. |
| `init.lisp` | Runs when the top level starts. |
| `makeimg.bat`, `makemsi.bat`, `makezip.bat`, `delimg.bat` | Build and packaging scripts. |
| `src_vc15.sln` | Visual Studio solution. |
| `RDNZL.dll`, `libssl-1_1.dll`, `libcrypto-1_1.dll` | Committed prebuilt binaries (OpenSSL 1.1.x). |

Binary artefacts (`*.exe`, `*.dll`, `*.lib`, `*.img`, `*.obj`, `*.pdb`) are gitignored except a few committed DLLs.
The image (`CormanLisp.img`) is always a build product. **[source]**

## How the image is built **[source]**

`makeimg.bat` runs `clconsole -execute sys\compile-sys.lisp`, which:

1. `(load "sys/load-sys.lisp")`: the bootstrap phase. Loads, in order: `bootstrap`, `expand`, `uvector`, `read`, `misc`, `readtable`, `massage`, `write`, `destructure`, `util`, `sequence`, `format`, then (through `load-file`) `types`, `io`, `clmacros`, `backquote`, `package`, `pl-imports`, `setf`, `structures`, `array`, `arrays`, `assembler`, `hash-table`, `toplevel`.
2. `(top-level)` re-enters the toplevel so the newly built kernel Lisp is live.
3. `(load "sys/load-sys2.lisp")`: the main phase. Roughly: `declarations`, `kernel-asm`, `kernel-funcs`, `trees`, `compiler`, `lists`, `characters`, `strings`, `math`, `random`, `symbols`, `control-structures`, `sequences`, `subtypep`, `coerce`, `input-output`, `errors`, `defpackage`, `misc-features`, `clos`, `fast-class-of`, `conditions`, `tail-calls`, `profiler`, `ffi`, `trace`, `parse-c-decls`, `win32`, `win-conditions`, `com`, `winsock`, `time`, `math2`, `filenames`, `streams`, `autoload`, `loop`, `describe`, `pretty`, `directory`, `open-file`, `menus`, `registry`, `edit-window`, `imagehlp`, `map-file`, `compile-file`, `debug`, `save-application`, `dribble`, `require`, `documentation`, `print-float`, `bits`, `boole`, `bignums`, `math-ops`, `places`, `misc-utility`, the `scmindent` code formatter, `code-indenter`, `context-menu`, `setf-expander`, `sockets`, `xp`, `threads`, `version`, `auto-update`, `jumpmenu`, `ide-menus`.
4. Loads patch files named `CormanLisp_3_0_patch_??.lisp` from `ccl::local-patches-directory` in name order.
5. Declares autoloaded modules, makes keyword symbols constant, sets `*compiler-save-lambdas*` and friends, then `(save-image "CormanLisp.img")`.

Consequences:

- Many `Sys/` files redefine functions defined earlier as stubs, and forward-declare things with placeholder `defun`s. Read the **later** definition; e.g. `namestring` in `filenames.lisp` is first a stub then redefined, `file-stream-name` appears in both `filenames.lisp` (stub returning `nil`) and `streams.lisp` (real one).
- Ordering matters in both directions. Moving a `load-file` line or adding a dependency on a later file breaks the build.
- The manual says: never `LOAD` files in `Sys/` directly. **[manual]**

## Where things are (Lisp side) **[source]**

| Topic | Files |
|---|---|
| Compiler and assembler | `compiler.lisp`, `assembler.lisp`, `kernel-asm.lisp`, `kernel-funcs.lisp`, `trees.lisp`, `tail-calls.lisp`, `collect-literals.lisp` |
| Reader, printer | `read.lisp`, `readtable.lisp`, `write.lisp`, `print-float.lisp`, `format.lisp`, `xp.lisp`, `pretty.lisp` |
| Packages | `package.lisp`, `defpackage.lisp`, `pl-imports.lisp`, `pl-symbols.lisp`, `cl-symbols.lisp` |
| CLOS | `clos.lisp`, `clos-eql-patch.lisp`, `fast-class-of.lisp` |
| Conditions | `conditions.lisp`, `errors.lisp`, `win-conditions.lisp` |
| Types | `types.lisp`, `subtypep.lisp`, `coerce.lisp` |
| Files and pathnames | `filenames.lisp`, `logical-pathname.lisp`, `directory.lisp`, `streams.lisp`, `open-file.lisp`, `map-file.lisp` |
| Compile and load | `compile-file.lisp` (fasl format, `LOAD`, `COMPILE-FILE`), `require.lisp`, `autoload.lisp` |
| Applications and images | `save-application.lisp`, `toplevel.lisp` |
| Windows and FFI | `ffi.lisp`, `parse-c-decls.lisp`, `win32.lisp`, `com.lisp`, `winsock.lisp`, `registry.lisp`, `imagehlp.lisp`, `sockets.lisp` |
| Threads | `THREADS.lisp`, `synchronized.lisp`, `Modules/mp.lisp` |
| Debug tools | `debug.lisp`, `trace.lisp`, `profiler.lisp`, `stepper.lisp`, `describe.lisp`, `dribble.lisp` |
| IDE | `edit-window.lisp`, `menus.lisp`, `ide-menus.lisp`, `context-menu.lisp`, `jumpmenu.lisp`, `code-indenter.lisp`, `scmindent/` |
| Math | `math.lisp`, `math-ops.lisp`, `math2.lisp`, `bignums.lisp`, `bits.lisp`, `boole.lisp`, `random.lisp` |
