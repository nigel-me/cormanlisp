# 04. FFI and Windows integration

This is the part of Corman Lisp that most sets it apart. Sources: `Sys/ffi.lisp`, `Sys/parse-c-decls.lisp`,
`Sys/win32.lisp`, `Sys/com.lisp`, `Sys/winsock.lisp`, `Modules/win*.lisp`, and the manual's chapters 13, 18, 19, 25.

## Declaring C types and calling functions

### Types **[manual + source]**

Predefined C types: `:void :char :unsigned-char :short :unsigned-short :long :unsigned-long :short-bool :long-bool :single-float :double-float :handle`.
Arrays are `(:long 5)`. Pointers are `(:long *)`, pointer to pointer `((:long *) *)`. Inline structs are `(:struct f1 :short f2 :long)`.

```lisp
(ct:defctype string32 (:char 32))

(ct:defcstruct MEMORY_BASIC_INFORMATION
  ((BaseAddress (:void *))
   (AllocationBase (:void *))
   (AllocationProtect :unsigned-long)
   (RegionSize :unsigned-long)
   (State :unsigned-long)
   (Protect :unsigned-long)
   (Type :unsigned-long)))
```

`defwintype` and `defwinstruct` are the same, but export the name from `WIN32`.
`ct:sizeof`, `ct:create-foreign-ptr`, `ct:cpointer-value`, `ct:cpointerp`, `ct:with-c-struct`, `ct:cref`, `ct:c-string-to-lisp-string`, `ct:lisp-string-to-c-string`, `ct:create-c-string`, `ct:malloc` are the workhorses.

### Calling a DLL function

```lisp
(ct:defun-dll GetFullPathName ((lpFileName (:unsigned-char *))
                               (nBufferLength :long)
                               (lpBuffer (:unsigned-char *))
                               (lpFilePart ((:unsigned-char *) *)))
  :return-type :long
  :library-name "kernel32.dll"
  :entry-name "GetFullPathNameA"
  :linkage-type :pascal)      ; :pascal (stdcall) or :c (cdecl, default)
```

`:return-type` defaults to `:long`. `defwinapi` is the same and exports from `WIN32`. This example is real code from `Sys/filenames.lisp`.

### C header blocks **[source]**

The reader understands `#! ... !#` blocks containing C declarations, which become Lisp wrappers:

```lisp
#! (:library "Kernel32" :ignore "WINUSERAPI" :export t :pascal "WINAPI")
BOOL WINAPI CloseHandle(HANDLE hObject);
HANDLE WINAPI GetStdHandle(DWORD nStdHandle);
!#
```

Options seen in the repo: `:library`, `:export t`, `:ignore "<macro>"`, `:pascal "<calling-convention-macro>"`. The parser is `Sys/parse-c-decls.lisp`; it is autoloaded rather than resident in the image, and is a hand-written C declaration parser, not a full C front end (it handles typedefs, structs and function prototypes, not macros or `#include` **[unverified]**). Most Win32 declarations are already in `Sys/win32.lisp` and `Modules/win*.lisp`.

### Callbacks (Windows calling into Lisp) **[source + manual]**

| Macro | Convention | Notes |
|---|---|---|
| `ct:defun-callback` | stdcall (`:pascal`) | Window procedures, most Win32 callbacks. |
| `ct:defun-c-callback` | cdecl | Callbacks into C libraries. |
| `ct:defun-direct-callback`, `ct:defun-direct-c-callback` | as above | Create a heap handler; used for exports. |

`(ct:get-callback-procinst 'name)` returns the pointer to pass to the foreign side. See `examples/callbacks.lisp`.

### Exporting Lisp functions from a DLL **[source]**

```lisp
(ct:defun-dll-export-c-function (lisp_add "lisp_add") ((x :long) (y :long))
  "long lisp_add(long a, long b)"
  (+ x y))
```

`examples/dllsample.lisp` has the full set (doubles, floats, C strings). The build uses `dlltemplate.dll` and fills its
placeholder exports (`Sys/compile-file.lisp`, around the `dlltemplate.dll` lookup). Manual chapter 18 covers usage. **[manual]**

## Windows integration surface **[source]**

| Area | Where | Notes |
|---|---|---|
| Win32 API | `Sys/win32.lisp`, `Modules/win*.lisp` (`winbase`, `winuser`, `wingdi`, `winnt`, `windef`, `winutil`, `win32-wrappers`, `win32-symbols`) | Constants, structs and API declarations. Package `WIN32`. |
| COM | `Sys/com.lisp`, `Modules/com-type-libs.lisp`, `examples/com-interfaces.lisp` | Interfaces and type-library reading. |
| The kernel as a COM server | `CormanLispServer/src/CoCormanLisp.cpp` | Any COM client can host Corman Lisp. `clconsole` and the IDE are two such clients. |
| Registry | `Sys/registry.lisp`, `examples/registry.lisp` | |
| Sockets, TLS | `Sys/sockets.lisp`, `Sys/winsock.lisp`, `Modules/ssl-sockets.lisp`, `acl-socket.lisp` | Winsock. IPv6 and datagram sockets when available. SSL uses the bundled OpenSSL 1.1.x DLLs and TLS by default. |
| .NET | `Modules/rdnzl.lisp`, `Libraries/rdnzl/`, manual chapter 25 | RDNZL bridge. Ships `RDNZL.dll`. Which .NET versions work today is **[unverified]**. |
| Java | `Modules/jni.lisp` | JNI type definitions. |
| ODBC | `Libraries/odbc`, `Libraries/sql-odbc-0.85` | |
| AutoCAD | `Libraries/acad` | ARX hosting (`acad2000`, `acadr14`, `acadr13` options of `save-application`). |
| Web server / RPC | `Modules/allegroserve.lisp`, `xmlrpc.lisp`, `html.lisp`, `uri.lisp`, `telnet-listener.lisp` | Early 2000s ports. |
| Windows GUI examples | `examples/hellowin.lisp`, `poppad1.lisp`, `sysmets3.lisp`, `devcaps1.lisp`, `examples/gui/` | Petzold-style apps written in Lisp. |
| Shell / files | `win:shell-execute`, `ccl::copy-file`, `ccl::get-current-directory`, `ccl::set-current-directory` | |

## Standalone applications and DLLs **[source + manual]**

- `(ccl:save-application "name" #'start-fn &key console static ...)` writes an `.exe` next to a saved image, copied from one of four host templates:

  | Options | Template |
  |---|---|
  | (default) | `clboot.exe` (headless GUI-subsystem host, uses `CormanLispServer.dll`) |
  | `:console t` | `clconsole.exe` |
  | `:static t` | `clbootapp.exe` (kernel linked statically) |
  | `:console t :static t` | `clconsoleapp.exe` |

  The template is copied from the Corman Lisp server directory, then the image is attached (for non-AutoCAD apps the application and image share one file name). The `:acad*` options pick `cormanlisp1x.arx` templates for AutoCAD. Selection logic: `Sys/save-application.lisp:54`.
- Static templates embed the kernel; dynamic templates need `CormanLispServer.dll` next to them.
- `compile-file` with an `.exe`/`.dll` output appends the fasl as a PE section. `Sys/compile-file.lisp` reads it back with `win::open-read-exe`.
- DirectCall (manual chapter 19): a C-callable API into the kernel for non-COM hosts, with `BlessThread()` for foreign threads. **[manual]**

## Working rules for FFI code

- Lisp objects move. Pass foreign memory (`ct:malloc`, `ct:create-c-string`, structs allocated with `ct` functions), not addresses of Lisp objects. **[manual]**
- Free what you `malloc` unless a finalizer does it. Many existing snippets leak; do not copy that.
- The callee's calling convention must match `:linkage-type` / callback macro exactly. A stdcall/cdecl mismatch corrupts the stack silently. **[general x86 knowledge]**
- Handle types are 32-bit. There is no 64-bit FFI. **[source: `:32-bit`]**
- The 3.1 notes say FFI-heavy programs no longer crash on 64-bit Windows, but the process is still 32-bit. **[manual: 3.1 release notes]**
- OpenSSL DLL names are fixed (`libssl-1_1.dll`, `libcrypto-1_1.dll`). Updating them means matching the module's declarations.
