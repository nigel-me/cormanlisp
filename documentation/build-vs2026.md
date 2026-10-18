# VS2026/v145 Win32 build and debugging

Open `src_vc26.sln` in Visual Studio Community 2026 and select **Standard / Win32**. This builds 32-bit x86 components and the matching Lisp image; the installer is excluded.

Install MSVC v145 14.51.36231 x86 tools (compiler 19.51.36260.0), matching MFC/ATL, and Windows SDK 10.0.26100.0. The projects pin these versions and do not install or silently substitute components. Use a normal Windows account with working profile/Documents paths.

The VS2015 `src_vc15.sln` and VS2022 `src_vc22.sln` paths remain unchanged. The three project sets share runtime source; keep source lists and the explicit static-kernel object lists synchronized when changing source membership.

Outputs are isolated under `.build/v145/ide/Win32/Standard`: `obj`, `lib`, `runtime` and `logs`. Clean/Rebuild operates on this path. Do not substitute v143 images, objects or PDBs.

Set the startup project to **clconsoleapp** for the static console, **DynamicConsole** for the dynamic console, or **CormanLisp** for the GUI. Press F5. Check loaded EXE/DLL/PDB paths in Modules. Console arguments use `-image`; the GUI uses a positional image path. Enter `(load "absolute/path/to/test.lisp")` at a console prompt. Evaluate GUI worksheet forms with Shift+Enter.

The runtime retains the ESI preservation fix in `LISP_TO_FOREIGN()` and the original 64-bit `GCTimeTotal` store. Existing CRT choices and kernel /Od /Oy- /GS- /arch:IA32 /Gd settings are unchanged.

The separate solution layout passed seven build stages, no-op build, image regeneration after an input change, Clean and Rebuild on 2026-10-18. All 204 recorded v143 artifacts remained unchanged. Sensitive GC and transition disassembly matched the earlier v145 compiler trial after normalizing generated labels and excluding debug-section metadata.

The scoped local comparison passed 129/129 fresh-process checks: original v140, v145 static console and v145 dynamic console each passed four threaded scenarios ten times and the non-callback core test three times. All exited 37 with explicit completion markers. The four scenarios are one allocating worker, one explicit-GC worker, two allocating workers, and one GC worker alongside one allocating worker. In the fourth scenario, both workers remain alive until both workloads finish, then exit and join. This revised test excludes worker teardown during the other's explicit GC; it does not guarantee allocation overlaps every GC.

The original fourth scenario had produced an access-violation exit in unchanged v140 before any v145 test ran. The revised pass does not explain or clear that failure. Known callback and competing-GC baseline issues remain excluded and unresolved; hardware GC was not retested. Thread tests use a shared frozen image, core tests use each runtime's matching image, and the v140 reference uses preserved binaries.

The human-operated VS2026 debugger gate also passed for this solution: static/dynamic console and GUI launch, symbols/source resolution, console main/GC breakpoints, both console smoke markers and exit 17, GUI arithmetic and GC, and normal GUI close. The earlier compiler trial separately passed a native-x64 cloud comparison. The new permanent solution layout has not yet been built on a cloud runner; retain that distinction when describing validation.