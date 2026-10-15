# VS2022 IDE build and debugging

Open `src_vc22.sln` in Visual Studio Community 2022 and select **Standard / Win32**. Build Solution builds the default development components and generates the Lisp image. The installer is excluded. This is a 32-bit x86 build; no x64 configuration is provided.

Requires the validated MSVC 14.41.34120 v143 x86 tools, Windows SDK 10.0.26100.0 and MFC/ATL components. Missing tools cause a build error; the build does not install components. Use a normal Windows account: the runtime needs ordinary profile/Documents paths. No elevation, registration or execution-policy changes are required by this build path.

The existing `src_vc15.sln`, v140_xp projects and their scripts remain the VS2015 path. New sibling `*.v143.vcxproj` files share the existing C/C++ source. When adding/removing source files, keep both project sets and the v143 static-library object list in sync.

Generated artifacts are isolated under `.build/v143/ide/Win32/Standard`: `obj/<project>` contains compiler intermediates, `lib` contains libraries, `runtime` contains executables/DLLs/PDBs/image and staged resources, and `logs` contains bootstrap evidence. Clean removes generated build outputs; Rebuild recreates them. The separate `build-v143.cmd` continues to build committed snapshots into timestamped directories.

Right-click a project in Solution Explorer and choose **Set as Startup Project**, then press F5:

- **clconsoleapp**: static console, with interactive input.
- **DynamicConsole**: dynamic-console launch project; it builds the console and image without a dependency cycle.
- **CormanLisp**: Corman GUI IDE. Evaluate forms in its worksheet using Shift+Enter.

The debugger settings select the isolated image and working directory. Consoles use `-image`; the GUI takes the image filename as a positional argument. The static console intentionally omits `-execute` because that legacy path queues input and returns without waiting for the Lisp worker. Use `(load "absolute/path/to/test.lisp")` at its prompt for debugger smoke checks.

Function breakpoints at `main` and `garbageCollect` are useful for the consoles. In Modules, verify the isolated EXE and adjacent PDB; the dynamic console and GUI also load CormanLispServer.dll and its PDB there. Kernel C++ source resolves to the current source checkout. The runtime's saved system-Lisp source paths resolve to staged resources: edit the source project entries and build again, rather than editing a staged copy.

The image custom step tracks Lisp/resource inputs and bootstrap binaries. It requires both the image and a success-only `logs/image-inputs.sha256` stamp. Failed staging/bootstrap invalidates those outputs; missing stamp forces retry. Bootstrap has a 300-second child timeout and detects entry into the Lisp debugger. Preserve logs when investigating failures. Restored files with older preserved timestamps require Rebuild, as with ordinary native incremental builds.

The runtime preserves Candidate A's boundary-local ESI repair and the original 64-bit GCTimeTotal store. Existing per-project CRT choices and kernel /Od /Oy- /GS- /arch:IA32 /Gd settings are retained. The agreed four stable threaded scenarios passed; competing explicit-GC and three-worker stress are excluded as a pre-existing v140 defect, not repaired by this build path.
