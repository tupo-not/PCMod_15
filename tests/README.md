# PCMod test suites

Static syntax checks and mock suites for the addon. They do not need a running
game (or even Garry's Mod installed) — only Lua 5.1 and Python 3.

## Requirements

- `lua5.1` — runs the mock suites.
- `luac5.1` — parses the translated sources (`-p` only, never executes).
- `python3` — translates GLua syntax to standard Lua 5.1.

Debian/Ubuntu: `sudo apt install lua5.1 python3`

## Running

```sh
cd pcmod/tests
./run_tests.sh                        # everything
./run_tests.sh mock_fs                # a single suite by name
./run_tests.sh mock_notepad mock_fs   # several selected suites
```

Exit codes: `0` all passed, `1` build/syntax error, `2` a test failed,
`3` a required binary is missing.

## How it works

1. `lib/build_fixtures.py` translates the GLua-specific syntax this addon uses
   (`//` comments, `!`, `!=`, `&&`, `||`) into standard Lua 5.1 and writes the
   result into `.build/`. It also compile-checks every addon Lua file with
   `luac5.1 -p`, automatically, except the retired `oldstools/` directory.
2. `lib/check_sources.py` checks project contracts that Lua cannot see: network
   channels are registered, `RunString`/`loadstring` stay out of the addon,
   new `umsg` usage is rejected, and `addon.json` matches `sh_version.lua`.
3. `run_tests.sh` discovers and runs every `mock_*.lua` suite.

The `.build/` directory is fully generated and git-ignored — never edit it.
Change the real sources under `../lua/` instead; the fixtures are rebuilt
from them on every run, so tests always exercise the current code.

## Writing a suite

`mock_*.lua` files are plain Lua (the same translation is applied on build, so
GLua operators work there too). They `dofile()` translated fixtures and assert
with `error("FAILED: ...")`; a suite passes when it reaches its final
`print("... PASSED")` line without erroring.

To include a new addon source as a fixture, add a name → path entry to
`lib/build_fixtures.py:FIXTURES`, then reference it from a mock suite. Syntax
checking is automatic, so a new source needs no extra registration for that.