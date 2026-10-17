# Native-x64 host validation — 2026-10-17

The VS2022 build passed the scoped comparison against the preserved original
VS2015 runtime on a native AMD/x64 Windows host. The Corman binaries remain
**32-bit x86**; this is not an x64 port.

## Validated baseline

- Corman source: `1081565ff0e6c0997bacb890fd2e4ffcde4aab17`.
- MSVC v143 directory: `14.44.35207`; compiler: `19.44.35229.0`;
  linker: `14.44.35229.0`; host tools: `HostX64/x86`.
- Windows SDK: `10.0.26100.0`; configuration: `Standard / Win32`.
- GitHub-hosted `windows-2022`, image `20261012.333.1`, OS build `20348`;
  OS and runner architecture recorded as X64, processor vendor AuthenticAMD.
- Experiment harness: `1b65e3f7a9df18119015aa93e4e8034ba1d58931`.

All seven build stages passed: zlib, kernel, dynamic console, image bootstrap,
static kernel, static console and full default solution build. The normalized
GC instruction listing matched the local validated reference.

## Runtime results

Each repetition used a fresh process. The four original-v140 threading tests
passed 10/10 each before v143 testing began. All 129 processes exited with
code 37 and had their explicit completion marker verified. There were no
timeouts, crashes/other exits, Lisp errors or setup failures.

| Scenario | v140 original static | v143 static | v143 dynamic |
|---|---:|---:|---:|
| One secondary worker allocating | 10/10 | 10/10 | 10/10 |
| One secondary worker explicitly invoking GC | 10/10 | 10/10 | 10/10 |
| Two secondary workers allocating, no explicit GC | 10/10 | 10/10 | 10/10 |
| One explicit-GC worker and one allocating worker | 10/10 | 10/10 | 10/10 |
| Non-callback core | 3/3 | 3/3 | 3/3 |

Timing below is median / slowest successful repetition, in seconds; these
short cloud runs are correctness checks, not controlled performance benchmarks.

| Scenario | v140 original static | v143 static | v143 dynamic |
|---|---:|---:|---:|
| Thread 1 | 0.180 / 0.224 | 0.173 / 0.230 | 0.177 / 0.257 |
| Thread 2 | 0.275 / 0.333 | 0.275 / 0.348 | 0.310 / 0.477 |
| Thread 3 | 0.219 / 0.277 | 0.214 / 0.287 | 0.221 / 0.343 |
| Thread 4 | 0.345 / 0.423 | 0.296 / 0.299 | 0.370 / 1.585 |
| Core | 10.800 / 11.850 | 10.904 / 11.502 | 10.957 / 11.215 |

Thread tests used the identical frozen v140 suite image and parameters across
all three targets. Core checks used each runtime's matching image, including
the freshly bootstrapped v143 image, and retained arithmetic, hash-table,
240-round GC/live-data and finalizer checks. The original v140 executable/image
were checksum-verified preserved artifacts, not rebuilt on this runner.

## Limits and next compiler trials

Minimal callback failures also observed with original v140 remain unresolved
and excluded. Repeated competing explicit-GC requests and unstable three-worker
GC stress remain excluded baseline limitations. This run does not establish
their correctness, test the GUI or experimental hardware GC, or prove general
runtime correctness. Prior local evidence remains separate.

Treat this exact compiler/SDK combination as the validated modern-build baseline.
Keep the existing VS2015/v140_xp path and the ESI preservation fix in
`CormanLispServer/include/Lisp.h` unchanged. Evaluate any
new compiler separately against this baseline with the same stable suite,
build/disassembly checks and manual debugger/GUI gate before adopting it.

## Evidence

Run ID: `39006222201`; artifact ID: `12091048154`.
Artifact: `corman-v143-native-x64-result.zip`.
SHA256: `7ef79c1e7ff583eb7976b6ee9499ea8315378400940c6379a7d1d27ce978380a`.

The durable investigation checkpoint retains the artifact, including
`acceptance-summary.csv`, `Test-runs.csv`, build/toolchain records and individual
worker/main/stdout/stderr logs. The private experiment run may require access;
the result and limitations above are self-contained.
