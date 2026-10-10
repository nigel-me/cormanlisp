# VS2022 native debugger validation record

Recorded 2026-10-10. This records user-observed debugger evidence and the remaining checks. It does not claim additional runtime tests were performed.

## Build identity

- Canonical repository: `C:\src\cormanlisp-vs2022`.
- Branch: `vs2022-port`.
- Tested HEAD: `3c44f98c09183f550e5cf63730bef6a1b10f61d5` (isolated v143 build driver).
- Candidate A runtime commit: `450c30a1fc0a1969c5fb7dff716615011e72579d` (Preserve ESI across Lisp-to-foreign boundary).
- Retained snapshot: `C:\src\cormanlisp-vs2022\.build\v143\Win32\Standard\20261009-211248-2145a34b\tree`.
- Build configuration: Standard/Win32, v143; MSVC 14.41.34120, Windows SDK 10.0.26100.0.
- Debugger: Visual Studio Community 2022, 17.11.35312.102.
- Trial files: `C:\src\cormanlisp-vs2022\.build\v143\debugging-trial-2026-10-09`.

Keep this snapshot in place: its image and debug information reference snapshot paths. Debug its matching binaries and PDBs. Source stepping resolves to the snapshot, not live edits in the canonical checkout.

## Launch and smoke procedure

Run the trial's `manual-clconsole.cmd` for the dynamic console or `manual-clconsoleapp.cmd` for the static console from a normal Windows account. Each sets the snapshot as the working directory and launches VS2022 with `/DebugExe` and that snapshot's image.

Set function breakpoints at `main` and `garbageCollect`. Start debugging. For the static console, continue from main to the Lisp prompt, then enter:

```lisp
(load "C:/src/cormanlisp-vs2022/.build/v143/debugging-trial-2026-10-09/ide-gc-smoke.lisp")
```

The unchanged smoke file contains:

```lisp
(progn
  (assert (= (+ 20 22) 42))
  (format t "IDE-GC-BEFORE~%")
  (finish-output)
  (gc 2)
  (format t "IDE-GC-AFTER~%")
  (finish-output)
  (win:ExitProcess 17))
```

At the GC breakpoint record Modules, Registers and Disassembly as described below. Then continue, disabling the GC breakpoint if desired. Success requires both progress lines and intentional process exit 17. When closing a temporary executable debugging solution, choose **Don't Save** if prompted to save `clconsoleapp.sln`.

The static launcher intentionally omits `-execute`. Its original use queued the Lisp file asynchronously and allowed the main thread to return while debugging paused the Lisp thread. That trial exited 0 and showed a first-chance access violation in `pushDynamicBinding`, called by `LispMainProc`. The exact access-violation cause was not established. That trial is not a smoke pass. The corrected interactive procedure subsequently passed.

## Results recorded so far

| Check | Static clconsoleapp | Dynamic clconsole |
| --- | --- | --- |
| main breakpoint reached | Confirmed by user | Confirmed by user |
| garbageCollect breakpoint reached | Confirmed by user, including two stops in one smoke run | Confirmed by user |
| Matching loaded binary/PDB paths | Confirmed by user in Modules | Confirmed by user for host EXE and kernel DLL |
| EIP/ESP/EBP/ESI inspected | Confirmed by user | Confirmed by user |
| Native disassembly at GC entry | Confirmed by user | Confirmed by user |
| Smoke progress and exit 17 | Confirmed by user; process 2880 showed both progress lines and exit 17, earlier process 588 also exited 17 | Confirmed by user; process 7280 showed both progress lines and exit 17 |

The current process 9500 GC pause supplies the static live inspection below. Its final exit has not yet been reported; the completed smoke runs are separate observations.

## Static console: live evidence

Modules reported:

```text
Process: [9500] clconsoleapp.exe
Binary: C:\src\cormanlisp-vs2022\.build\v143\Win32\Standard\20261009-211248-2145a34b\tree\clconsoleapp.exe
Symbol status: Symbols loaded.
PDB: C:\src\cormanlisp-vs2022\.build\v143\Win32\Standard\20261009-211248-2145a34b\tree\clconsoleapp.pdb
Module range: 00D20000-00E01000
Timestamp displayed: 10/9/2026 9:17 PM
```

Registers supplied at the GC entry pause:

```text
EAX = 4C27F8F4  EBX = 00000000  ECX = 00000010  EDX = 00000002
ESI = 036813E8  EDI = 0C000005  EIP = 00D3E240
ESP = 4C27F8D4  EBP = 4C27F8EC  EFL = 00000212
```

The source resolved to the snapshot's `CormanLispServer\src\Gc.cpp`. The user supplied this entry disassembly:

```text
void garbageCollect(long level)
00D3E240  push ebp
00D3E241  mov ebp,esp
00D3E243  push 0FFFFFFFFh
00D3E245  push 0D9CF00h
00D3E24A  push offset __except_handler3 (0D8C2E3h)
00D3E24F  mov eax,dword ptr fs:[00000000h]
00D3E255  push eax
00D3E256  mov dword ptr fs:[0],esp
00D3E25D  add esp,0FFFFFFBCh
00D3E260  push ebx
00D3E261  push esi
00D3E262  push edi
00D3E263  mov dword ptr [ebp-18h],esp
HANDLE process = 0;
00D3E266  mov dword ptr [process],0
```

EIP is inside the reported module at RVA 0x1E240. The displayed prologue establishes an EBP frame, installs an x86 SEH frame and saves EBX/ESI/EDI. At the entry pause the first `push ebp` has not executed yet; the supplied EBP is not the newly established GC frame. Absolute addresses can vary between runs.

This confirms native debugger visibility. The observed ESI value alone does not establish that ESI holds QV at a boundary. Candidate A's separate boundary probes previously verified correct QV during the marker operation, exact restoration of incoming ESI, and unchanged marker semantics.

## Dynamic console: live evidence

Process 3996 reported both modules with `Symbols loaded.`:

```text
Host binary: C:\src\cormanlisp-vs2022\.build\v143\Win32\Standard\20261009-211248-2145a34b\tree\clconsole.exe
Host PDB: C:\src\cormanlisp-vs2022\.build\v143\Win32\Standard\20261009-211248-2145a34b\tree\clconsole.pdb
Host range: 00A90000-00A9A000
Kernel binary: C:\src\cormanlisp-vs2022\.build\v143\Win32\Standard\20261009-211248-2145a34b\tree\CormanLispServer.dll
Kernel PDB: C:\src\cormanlisp-vs2022\.build\v143\Win32\Standard\20261009-211248-2145a34b\tree\CormanLispServer.pdb
Kernel range: 6CB80000-6CC5E000
Kernel file version displayed: 3.02.0.0
Both timestamps displayed: 10/9/2026 9:13 PM
```

Registers at the GC entry pause:

```text
EAX = 00000000  EBX = 02BC8610  ECX = 00000008  EDX = 00000000
ESI = 02BD0FB8  EDI = 0AC719CD  EIP = 6CBA7F90
ESP = 4B9CF5A0  EBP = 4B9CF5A8  EFL = 00000252
```

Source resolved to `C:\src\cormanlisp-vs2022\.build\v143\Win32\Standard\20261009-211248-2145a34b\tree\CormanLispServer\src\Gc.cpp`. Supplied disassembly:

```text
6CBA7F88  mov dword ptr [esi+14h],edx
6CBA7F8B  pop ebp
6CBA7F8C  ret
6CBA7F8D  int 3
6CBA7F8E  int 3
6CBA7F8F  int 3
void garbageCollect(long level)
6CBA7F90  push ebp
6CBA7F91  mov ebp,esp
6CBA7F93  push 0FFFFFFFFh
6CBA7F95  push 6CBFB878h
6CBA7F9A  push offset __except_handler3 (6CBEB1E4h)
6CBA7F9F  mov eax,dword ptr fs:[00000000h]
6CBA7FA5  push eax
6CBA7FA6  mov dword ptr fs:[0],esp
6CBA7FAD  add esp,0FFFFFFBCh
6CBA7FB0  push ebx
6CBA7FB1  push esi
6CBA7FB2  push edi
6CBA7FB3  mov dword ptr [ebp-18h],esp
6CBA7FB6  mov dword ptr [process],0
6CBA7FBD  mov dword ptr [ret],0
6CBA7FC4  mov dword ptr [temp],0
6CBA7FCB  mov dword ptr [mark1],0
```

EIP is inside the kernel DLL at RVA 0x27F90, before the first prologue instruction executes. Its prologue has the same displayed frame/SEH setup and nonvolatile-register saves as the static build. The preceding instructions belong to the preceding function, not `garbageCollect`. This establishes dynamic native-debugger visibility; it is not a new boundary-invariant probe.

The user subsequently supplied the completed dynamic smoke output:

```text
?IDE-GC-BEFORE
IDE-GC-AFTER

C:\src\cormanlisp-vs2022\.build\v143\Win32\Standard\20261009-211248-2145a34b\tree\clconsole.exe (process 7280) exited with code 17 (0x11).
```

Dynamic smoke: PASS, user-observed. The reported exit belongs to process 7280; the live inspection above belongs to process 3996. These are recorded as separate observations rather than asserting they were the same process. Together with the static results, both console variants have demonstrated breakpoints, loaded symbols, register/disassembly inspection and a completed exit-17 smoke run.

## Offline symbol evidence

The earlier read-only identity check passed for `clconsole.exe`, `clconsoleapp.exe`, `CormanLispServer.dll` and `CormanLisp.exe` with their adjacent PDBs. Evidence is retained in the trial's `pdb-identity-check.csv`, `check-pdb.ps1` and `SYMBOL-CHECKS.md`.

The DLL's PE age is 1, PDB general age 19, and DBI age 1. This alone is not a mismatch: matching GUID, general age at least the requested age, and matching DBI age satisfy the published validation checks. Offline identity evidence is separate from confirming actual loaded symbols in the live debugger.

## Remaining record to collect

The agreed debugger checks are complete for both console variants across the recorded sessions. No further runtime run is required to complete this documentation.

Final exits of inspection processes 3996 (dynamic) and 9500 (static) were not separately supplied. They may be added if available, but neither is inferred from the completed smoke sessions above.

No runtime source, Candidate A, build products, projects or solutions were changed for this record. The rejected two-store GCTimeTotal workaround remains excluded. This document does not expand the agreed runtime acceptance suite or reopen the pre-existing competing-GC defect.
