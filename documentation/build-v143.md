# VS2022 Win32 reference build

Run build-v143.cmd core from a normal Windows account to build the dynamic kernel/console, bootstrap image and static console. Run build-v143.cmd full to also build the remaining default solution projects, including the IDE. The installer is excluded by the existing solution configuration.

This driver intentionally preserves the validated MSVC 14.41 reference path. The native `src_vc22.sln` selects MSVC 14.44; see [VS2022 IDE build and debugging](build-vs2022.md). Requires Git, tar, VS2022 C++ x86 tools, MSVC 14.41.34120 and Windows SDK 10.0.26100.0. Full mode also requires MFC/ATL. Missing components cause a preflight error; nothing is installed.

The driver builds committed HEAD and requires tracked files to match HEAD. Untracked files are excluded. Each invocation creates a fresh .build/v143/Win32/Standard/<run-id>/tree containing the source/runtime snapshot and all generated binaries, libraries, objects, image and PDBs. Logs, exact MSBuild commands and a build manifest are kept alongside it. Previous runs are retained. Keep the tree in place because generated images contain source/debug paths into that tree.

The existing VS2015 src_vc15.sln and v140_xp projects are unchanged. v143 is selected only through command-line properties with Standard/Win32, SDK 10.0.26100.0 and an empty per-user property directory. Compiler environment overrides are cleared only in the child shell. Existing kernel flags and runtime-library choices remain inherited.

Bootstrap has a 300-second timeout; each build step has a 900-second timeout. Failures return nonzero and retain logs; timed-out children and descendants are terminated. No administrator rights, execution-policy changes, COM registration, downloads or registry changes are needed. CMD invokes its embedded PowerShell command without changing execution policy.

For v140 continue using the existing VS2015 solution procedure. This driver provides a command-line path, not project retargeting or live canonical-source debugging in VS2022.

Validate compiler logs for /Od /Oy- /GS- /arch:IA32 /Gd, x86 output, bootstrap, runtime smoke/GC/finalizers/callbacks and the four stable threading scenarios. Competing explicit-GC and three-worker stress remain excluded as pre-existing v140 defects.