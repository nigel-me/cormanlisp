# 05. Kernel and runtime architecture

Read this before editing anything in `CormanLispServer/` or the assembly-level parts of `Sys/` (`assembler.lisp`,
`kernel-asm.lisp`, `compiler.lisp`, and the code that emits calls into the kernel).

Sources: manual chapter 26 "Run-time Architecture" **[manual]**, and the C++ sources **[source]**.

## What the kernel is **[manual + source]**

`CormanLispServer.dll` is an in-process COM server written in C++ and x86 assembly. It implements:

- The COM server interface (`CoCormanLisp.cpp`, `CormanLispServer.cpp`).
- Bootstrap code to start the engine and load the image.
- Memory management: allocation and a generational copying collector (`Gc.cpp`).
- Code generation, producing x86 machine code (`Compx86.cpp`).
- A library of kernel functions (`Lisp.cpp`, `Lispfunc.cpp`, `LispMath.cpp`, `Read.cpp`, `Write.cpp`).
- GZIP compression (zlib) used by `save-image` and `compile-file`.
- A disassembler front end (`Unassemble.cpp` with `distorm/`).

Most kernel library functions are replaced by Lisp versions when the image is built. The kernel versions exist to
bootstrap the system.

## Register conventions for compiled Lisp code **[manual]**

| Reg | Role |
|---|---|
| `EBP` | Frame pointer. Negative offsets are locals, positive are parameters. |
| `ESI` | The current thread's **QV vector**: kernel objects, jump-table entries and dynamic (special) variable bindings. `QV[0]` is `NIL`, so `mov eax,[esi]` loads `NIL`. Not part of the Lisp heap. |
| `EDI` | Function environment pointer on entry (captured lexical bindings, or `NIL`). May be reused inside the function. |
| `EAX` | Temporary and the return value. Single value returned in `EAX`. With multiple values, `EAX` holds the first and all values are in a list at `[ESI+8]`. No values returns `NIL`. |
| `EBX` | On entry to a variable-arity function, points at the first (leftmost) parameter. It is not at a fixed offset from `EBP`. |
| `ECX` | Untagged argument count on entry, untagged value count on return. |
| `EDX` | General purpose. |

Parameters are pushed **left to right** for Lisp functions, unlike C's right to left. **[manual]**
That is why the C++ boundary uses `__declspec(naked)` thunks: they rearrange the stack and set `ECX`/`ESI` before
entering Lisp or C code.

## Tagging and GC safety **[manual]**

- All Lisp objects carry 2 or 3 low-bit tags in a 32-bit word. Fixnums have low three bits `000`.
- Heap objects can move at any allocation. **Every register and stack slot the collector can see must hold either
  a correctly tagged Lisp value or a value that cannot be mistaken for a heap pointer.** The argument count in `ECX`
  is allowed to be untagged because heap addresses are always above 65536.
- Untagged intermediate values are only safe in windows where no allocation, call or thread switch can occur.
- Another thread can trigger a collection at any time, so "no allocation in my code" is not enough when threads
  are running.
- Pointers into the middle of a Lisp object are unsafe across any call that can allocate.

## Foreign code and threads **[manual]**

- Foreign calls need run-time bookkeeping so the collector can scan the stack correctly.
- Each Lisp thread has its own stack and QV vector. Threads share global bindings and rebind specials locally.
- `BlessThread()` (DirectCall) registers a foreign thread that wants to call into Lisp.
- GC critical sections are asm routines (`EnterGCCriticalSection`, `LeaveGCCriticalSection` in `Gc.cpp`).

## Why the C++ is toolchain-sensitive **[source]**

Observed in `CormanLispServer/src` and `include/Lisp.h`:

- About 30 `__declspec(naked)` functions (32 occurrences, some in alternative `#ifdef` variants): `LispCall0..N`, `AllocVector`, `LispAllocVector`, `LispAllocVectorTagged`, `LoadLocalHeap`, `cons`, `createShortFloat`, `shortFloat`, `addShortFloats`, `Plus_EAX_EDX`, `Minus_EAX_EDX`, `Load_QV_Reg`, `genericThunkFunc`, `CallThrowUserExceptionStub`, `TerminateLispThreadException`, and others.
- Several hundred lines of MASM-syntax inline `__asm`, plus macros in `Lisp.h` (`SETUP_LISP_CALL`, argument-count checks, arg-pointer setup) that expand into `__asm` sequences and refer to C++ locals by name.
- SEH: `__try/__except (handleStructuredException(GetExceptionCode(), GetExceptionInformation()))` in `Gc.cpp`, `Lisp.cpp`, `CormanLispServer.cpp`. Linked with `/safeseh:no`.
- Direct TEB access (`fs:0018h`) for per-thread QV (`ThreadQV`, `Lisp.cpp`).
- `setjmp` in `Compx86.cpp` and `Lisp.cpp`.
- Compiled with `Optimization=Disabled`.

Practical rules:

1. Do not change compiler flags, calling conventions or struct layouts casually.
2. Do not add C++ locals or change the order of locals inside a function that contains `__asm` unless you have read the asm.
3. Do not "modernise" `__declspec(naked)` functions into ordinary functions.
4. A change that compiles is not evidence it works. GC and FFI bugs from stack or tagging mistakes can appear far from the edit.
5. `Compx86.cpp` is huge (thousands of lines); the generator's output format is relied on by `Sys/compiler.lisp`
   and by the fasl loader's code-reference patching (`update-code-references`, `store-code-reference` in `Sys/compile-file.lisp`).

## Relationship between kernel and image **[source + unverified]**

- The kernel exports (via `CormanLispServer.def`): `DllGetClassObject`, `DllCanUnloadNow`, `DllRegisterServer`, `DllUnregisterServer`, `Initialize`. Everything else is reached through the COM object or through jump-table entries built at startup.
- The heap allocation was made position independent (5/9/99 note in `Gc.cpp`): heaps are allocated dynamically
  rather than at fixed addresses, which is what allows hosting inside other processes (AutoCAD, the COM clients).
- Whether a `CormanLisp.img` built by one kernel binary loads correctly under a differently compiled kernel is not
  established. **[unverified]** Rebuild the image whenever the kernel changes.
- Fasls likely have the same coupling to the image. See [03](03-lisp-notes.md).
