# Corman Lisp knowledge pack (for coding agents)

A working reference for agents (and new contributors) touching this repo. It complements `CLAUDE.md` at the
repo root and the shipped manual in `documentation/CormanLisp.html`.

## Read in this order

| File | Read it when |
|---|---|
| [01-repo-map.md](01-repo-map.md) | You need to find where something lives, or understand the image build order. |
| [02-building-and-testing.md](02-building-and-testing.md) | You need to build, rebuild the image, run tests, or reason about what can be verified. |
| [03-lisp-notes.md](03-lisp-notes.md) | You are writing or changing Lisp: packages, pathnames, files, CLOS, conditions, threads. |
| [04-ffi-and-windows.md](04-ffi-and-windows.md) | You are calling Win32/COM/DLLs, defining callbacks, or exporting Lisp from a DLL. |
| [05-kernel-and-runtime.md](05-kernel-and-runtime.md) | You are near the C++/asm kernel, the code generator, the GC, or register conventions. |
| [06-known-gaps.md](06-known-gaps.md) | You want to know what is missing or wrong, with file references. |
| [07-agent-workflows.md](07-agent-workflows.md) | You want checklists for common tasks and safe ways to verify without Windows. |
| [08-test-harness.md](08-test-harness.md) | You want machine-readable test results, or to diff two runs (e.g. two builds). |

## Provenance tags

- **[source]**: observed by reading this repo.
- **[manual]**: from `documentation/CormanLisp.html`. That manual predates the 3.1 community release in places,
  so treat it as a good guide to intent and a possibly stale guide to current behaviour.
- **[unverified]**: inferred and never run. This pack was written on Linux with no way to execute Corman Lisp.

If you confirm or refute an **[unverified]** item on a real Windows machine, update the file and drop the tag.

## Ground truth about this pack

- It was assembled by reading code and the manual, not by running the system. Nothing here was executed.
- File and line references were accurate for the repo state at the time of writing. Verify with `grep` before relying on a line number.
- Keep additions short and factual. Prefer a file reference over a paragraph of explanation.
