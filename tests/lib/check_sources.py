#!/usr/bin/env python3
"""Small project-specific source checks that Lua 5.1 cannot express.

These are intentionally conservative: they catch drift that the runtime tests
cannot see, without trying to be a full GLua linter.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TESTS = os.path.dirname(HERE)
ADDON = os.path.dirname(TESTS)
LUA = os.path.join(ADDON, "lua")

SOURCE_IGNORE = (
    os.path.join("weapons", "gmod_tool", "oldstools"),
)

# CompileString is the admin-only syntax check command in sv_programs.lua.
COMPILE_WHITELIST = {
    os.path.join("pcmod", "sv_programs.lua"),
}

# Files that still use the existing usermessage transport. New code must use net.
EXISTING_UMSG = {
    os.path.join("pcmod", "cl_2d3d.lua"),
    os.path.join("pcmod", "cl_gui.lua"),
    os.path.join("pcmod", "cl_keyboard.lua"),
    os.path.join("pcmod", "cl_rp.lua"),
    os.path.join("pcmod", "sh_beam.lua"),
    os.path.join("pcmod", "sh_common.lua"),
    os.path.join("pcmod", "sh_settings.lua"),
    os.path.join("pcmod", "sv_core.lua"),
    os.path.join("pcmod", "sv_rp.lua"),
}

# The subsystem refactor retired the driver vocabulary. Production code must
# use canonical subsystem names so saved data and the runtime cannot diverge.
RETIRED_SUBSYSTEM = re.compile(
    r"\b(?:Drivers|DeriveDriver|InstallDriver|PushDriverData|CallDriver|"
    r"GetOSDriver|GetNetworkDriver|GetConnectedRouterDrivers|"
    r"gen_bios|gen_display|gen_input|gen_network|gen_sound|gen_usb|webgr_router)\b"
    r"|\bpc_drv_reload\b|\bsv_drivers\b|\bdrv_"
)


def source_files():
    for root, dirs, files in os.walk(LUA):
        relroot = os.path.relpath(root, LUA)
        if any(
            relroot == ignored or relroot.startswith(ignored + os.sep)
            for ignored in SOURCE_IGNORE
        ):
            continue
        for name in sorted(files):
            if name.endswith(".lua"):
                yield os.path.join(root, name)


def strip_comments(src):
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    src = re.sub(r"--[^\n]*", "", src)
    return src


def line_of(src, index):
    return src.count("\n", 0, index) + 1


def main():
    errors = []
    receive = {}
    registered = set()

    for path in source_files():
        rel = os.path.relpath(path, LUA)
        with open(path, "r", encoding="utf-8", errors="ignore") as fh:
            raw = fh.read()
        code = strip_comments(raw)

        for match in re.finditer(r"net\.Receive\s*\(\s*['\"]([^'\"]+)['\"]", code):
            receive.setdefault(match.group(1), []).append((rel, line_of(code, match.start())))
        for match in re.finditer(r"util\.AddNetworkString\s*\(\s*['\"]([^'\"]+)['\"]", code):
            registered.add(match.group(1))

        for match in re.finditer(r"\b(RunString|loadstring|CompileString)\s*\(", code):
            if rel not in COMPILE_WHITELIST:
                errors.append(
                    f"{rel}:{line_of(code, match.start())}: {match.group(1)} is not allowed here"
                )

        if rel not in EXISTING_UMSG and re.search(r"\b(?:umsg\.|usermessage\.)", code):
            errors.append(
                f"{rel}: new usermessage/umsg usage; use net instead"
            )

        for match in RETIRED_SUBSYSTEM.finditer(code):
            errors.append(
                f"{rel}:{line_of(code, match.start())}: retired subsystem name {match.group(0)!r}"
            )

    for channel, places in sorted(receive.items()):
        if channel not in registered:
            for rel, line in places:
                errors.append(
                    f"{rel}:{line}: net.Receive(\"{channel}\") has no util.AddNetworkString"
                )

    # addon.json and the shared version file must agree.
    version_path = os.path.join(LUA, "pcmod", "sh_version.lua")
    with open(version_path, "r", encoding="utf-8", errors="ignore") as fh:
        version_src = fh.read()
    match = re.search(r'PCMod\.Version\s*=\s*["\']([^"\']+)["\']', version_src)
    if not match:
        errors.append("pcmod/sh_version.lua: PCMod.Version is missing")
    else:
        with open(os.path.join(ADDON, "addon.json"), "r", encoding="utf-8") as fh:
            addon_version = json.load(fh).get("version")
        if addon_version != match.group(1):
            errors.append(
                f"addon.json version {addon_version!r} does not match sh_version.lua {match.group(1)!r}"
            )

    if errors:
        for error in errors:
            print(f"FAIL {error}")
        print(f"\n{len(errors)} source contract error(s).")
        return 1
    print(f"Source contracts OK ({len(registered)} network channel(s)).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
