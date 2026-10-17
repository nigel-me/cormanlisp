# VS2026 with the existing v143 toolchain

The unchanged `src_vc22.sln` passed the agreed build, runtime and manual
debugger checks in Visual Studio Community 2026. This validates a newer IDE
and MSBuild with the existing compiler, not adoption of v145.

## Configuration and build

- Tested source: `63b432aaecaaa37b1b3ef16955e5119d66bc728f` in a disposable copy.
- Visual Studio Community 2026: `18.11.0` (`18.11.12306.390`).
- VS2026 MSBuild and ARM64-hosted compiler tools on Windows ARM/Parallels.
- Toolset: v143 `14.44.35207`, compiler `19.44.35229.0`.
- Windows SDK: `10.0.26100.0`; matching x86 MFC/ATL installed.
- Configuration: `Standard / Win32`; all runtime binaries remain x86.

All seven stages passed: zlib, kernel, dynamic console, image bootstrap,
static kernel, static console and full default solution build including the
GUI. No source/project edits or retargeting were needed. The selected compiler
came from the VS2026 installation, not a fallback to VS2022.

Kernel options `/Od /Oy- /GS- /arch:IA32 /Gd` were retained. The normalized
`Gc.obj` disassembly matched the validated v143 reference, SHA256:
`0E658D07A550BCD932F89FB066F321B21FCE7D5136A1E70AC4F547D89D94CB1C`.

## Automated acceptance

All 129 fresh-process checks passed with exit 37 and independently verified
completion markers. No timeout, crash/other exit, Lisp error or setup failure
occurred. The original-v140 threading gate completed before v143 testing.

| Scenario | v140 original static | VS2026/v143 static | VS2026/v143 dynamic |
|---|---:|---:|---:|
| One worker allocating | 10/10 | 10/10 | 10/10 |
| One worker explicitly invoking GC | 10/10 | 10/10 | 10/10 |
| Two workers allocating without explicit GC | 10/10 | 10/10 | 10/10 |
| One GC worker and one allocating worker | 10/10 | 10/10 | 10/10 |
| Non-callback core | 3/3 | 3/3 | 3/3 |

Threading used the same frozen suite image and parameters across targets;
core checks used each runtime's matching image. Core coverage retained
arithmetic, hash tables, GC/live-data preservation and finalizers. The original
v140 binaries were reused, not rebuilt. Artifact hashes remained unchanged
through testing.

Readiness, worker join and individual process limits remained 30, 60 and 180
seconds respectively. Only the overall suite allowance increased from the
cloud harness's 480 seconds to 1,200 seconds for this local run.

## Manual VS2026 debugger gate

The human tester confirmed both consoles and the GUI completed the checklist:

- Static and dynamic consoles: symbols/source resolution, main/GC breakpoints,
  both `IDE-GC-BEFORE` and `IDE-GC-AFTER` markers, and intentional exit 17.
- GUI: arithmetic result 32, GC breakpoint/continue and clean shutdown.

An initial bare filename entered at the Lisp prompt caused a package-reader
error. Using `(load "path/to/ide-gc-smoke.lisp")` corrected the input; the
subsequent checks passed. This was not a runtime regression.

## Scope and next step

This is local Windows ARM/Parallels evidence, separate from the prior
[native-x64 cloud validation](v143-native-x64-validation.md). Callback failures
also seen with original v140, competing explicit-GC and three-worker stress
remain unresolved and excluded. Experimental hardware GC was not repeated.

The VS2015 build, ESI preservation fix and original 64-bit GCTimeTotal store
remain unchanged. Keep v143 as the reference. Investigate v145 only in a
separate disposable trial before proposing any permanent toolset change.
