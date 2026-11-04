# AGENTS.md

Guidance for AI agents (and humans) working in this repository.

## What this is

PCMod, a Garry's Mod addon. Lua files use GLua conventions: `//` and `/* */`
comments, and the operators `!`, `!=`, `&&`, `||` (not `not`, `~=`, `and`, `or`).
Do not "fix" these to standard Lua. The test toolchain translates them.

## Layout

- `lua/pcmod/` — server, client, and shared logic; drivers; OSes; programs;
  screen-space devices.
- `lua/entities/pcmod_base/` — the PC entity (ports, hard drive VFS, networking).
- `lua/weapons/` — toolgun stools (wiring).
- `tests/` — mock/Lua 5.1 test suites and the GLua→Lua translator.

## Running tests

```sh
cd tests && ./run_tests.sh
```

See `tests/README.md`. Never edit `tests/.build/` — it is generated.

## Conventions

- Preserve compatibility with existing PCMod programs, saved PC data, the boot
  flow, and legacy file-picker/screen-space payloads. Internal names such as
  `mycomputer` / `window_mycomp` are part of that contract.
- Server-side changes need a map restart; client-side changes need a reconnect;
  per-PC program changes need `sys_resetprog <name>` (or a respawn) on existing
  PCs.
- Add or update a mock suite whenever you change behaviour the existing suites
  would otherwise miss.
- Match the surrounding code's GLua style and tab indentation.

## Commit policy

- Keep generated files out of git (see `.gitignore`).
- Run the full test suite before committing.