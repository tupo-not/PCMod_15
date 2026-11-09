
#!/usr/bin/env python3
"""Build the Lua 5.1 fixture copies used by the mock test suites.

The game runs GLua, which luac5.1 cannot parse. Each test fixture is the
translated form of a real addon source file, so the mocks always exercise the
current code instead of a stale copy.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TESTS = os.path.dirname(HERE)
ADDON = os.path.dirname(TESTS)
LUA = os.path.join(ADDON, "lua")
BUILD = os.path.join(TESTS, ".build")

sys.path.insert(0, HERE)
from glua_translate import translate, compile_check  # noqa: E402

# fixture name -> source path (relative to lua/)
FIXTURES = {
    "cl_input.lua": "pcmod/cl_input.lua",
    "cl_keyboard.lua": "pcmod/cl_keyboard.lua",
    "cl_ui_widgets.lua": "pcmod/cl_ui_widgets.lua",
    "sh_ui_layout.lua": "pcmod/sh_ui_layout.lua",
    "sh_window.lua": "pcmod/sh_window.lua",
    "sv_window_payload.lua": "pcmod/sv_window_payload.lua",
    "prog_base.lua": "pcmod/programs/base.lua",
    "pcmod_base.lua": "pcmod/programs/base.lua",
    "ss_base.lua": "pcmod/ssdevices/base.lua",
    "pcmod_ss_base.lua": "pcmod/ssdevices/base.lua",
    "mycomp.lua": "pcmod/ssdevices/dev_win_mycomp.lua",
    "pcmod_mycomp_prog.lua": "pcmod/programs/pr_mycomputer.lua",
    "pcmod_chatserv.lua": "pcmod/programs/pr_chatserv.lua",
    "pcmod_browser.lua": "pcmod/programs/pr_browser.lua",
    "pcmod_web.lua": "pcmod/web.lua",
    "pcmod_files_ui.lua": "pcmod/ssdevices/dev_win_files.lua",
    "pcmod_open_ui.lua": "pcmod/ssdevices/dev_win_open.lua",
    "pcmod_files.lua": "pcmod/programs/pr_files.lua",
    "pcmod_notepad.lua": "pcmod/programs/pr_notepad.lua",
    "pcmod_notepad_ui.lua": "pcmod/ssdevices/dev_win_notepad.lua",
    "pcmod_sh_netproto.lua": "pcmod/sh_netproto.lua",
    "pcmod_sh_dhcp_server.lua": "pcmod/sh_dhcp_server.lua",
    "pcmod_sh_dhcp_client.lua": "pcmod/sh_dhcp_client.lua",
    "pcmod_sh_arp.lua": "pcmod/sh_arp.lua",
    "pcmod_sh_ndp.lua": "pcmod/sh_ndp.lua",
    "pcmod_sh_l2.lua": "pcmod/sh_l2.lua",
    "pcmod_sh_routing.lua": "pcmod/sh_routing.lua",
    "pcmod_drv_router.lua": "pcmod/drivers/drv_router.lua",
    "pcmod_drv_network.lua": "pcmod/drivers/drv_network.lua",
    "pcmod_drv_bios.lua": "pcmod/drivers/drv_bios.lua",
    "pcmod_network.lua": "pcmod/sv_network.lua",
    "pcmod_wiring.lua": "pcmod/sv_wiring.lua",
    "pcmod_shared.lua": "entities/pcmod_base/shared.lua",
    "pcmod_switch.lua": "entities/pcmod_switch/shared.lua",
    "pcmod_router.lua": "entities/pcmod_router/shared.lua",
    "pcmod_erouter.lua": "entities/pcmod_erouter/shared.lua",
    "pcmod_modem.lua": "entities/pcmod_modem/shared.lua",
    "pcmod_sh_common.lua": "pcmod/sh_common.lua",
    "cl2d3d.lua": "pcmod/cl_2d3d.lua",
    "cl_vgui.lua": "pcmod/cl_vgui.lua",
    "sselements_base.lua": "pcmod/sselements/base.lua",
    "sselements_button.lua": "pcmod/sselements/button.lua",
    "pcmod_os_base.lua": "pcmod/osystems/base.lua",
    "pcmod_installdisk.lua": "weapons/pcmod_installdisk/shared.lua",
}

# Additional sources that only need a syntax check.
CHECK_ONLY = [
    "pcmod/cl_gui.lua",
    "pcmod/cl_camera.lua",
    "pcmod/sh_beam.lua",
    "pcmod/themes/cl_pcmod15.lua",
    "pcmod/sh_config.lua",
    "autorun/sh_pcmod_launch.lua",
    "pcmod/drivers/drv_network.lua",
    "pcmod/osystems/os_personal.lua",
    "pcmod/osystems/os_server.lua",
    "pcmod/ssdevices/dev_win_browser.lua",
    "weapons/pcmod_installdisk/shared.lua",
    "weapons/gmod_tool/stools/pcspawn_switch.lua",
    "weapons/gmod_tool/stools/pcspawn_router.lua",
    "weapons/gmod_tool/stools/pcspawn_erouter.lua",
    "weapons/gmod_tool/stools/pcspawn_modem.lua",
    "weapons/gmod_tool/stools/pcwire.lua",
]


def main():
    os.makedirs(BUILD, exist_ok=True)
    for name, rel in FIXTURES.items():
        src_path = os.path.join(LUA, rel)
        with open(src_path, "r", encoding="utf-8", errors="surrogateescape") as fh:
            src = fh.read()
        with open(os.path.join(BUILD, name), "w", encoding="utf-8", errors="surrogateescape") as fh:
            fh.write(translate(src))

    # The mock suites themselves are written in GLua too.
    for name in sorted(os.listdir(TESTS)):
        if name.startswith("mock_") and name.endswith(".lua"):
            with open(os.path.join(TESTS, name), "r", encoding="utf-8", errors="surrogateescape") as fh:
                src = fh.read()
            with open(os.path.join(BUILD, name), "w", encoding="utf-8", errors="surrogateescape") as fh:
                fh.write(translate(src))

    check_paths = [os.path.join(LUA, rel) for rel in FIXTURES.values()]
    check_paths += [os.path.join(LUA, rel) for rel in CHECK_ONLY]
    # Keep the printed list stable and free of duplicates.
    seen = set()
    unique = []
    for path in check_paths:
        if path not in seen:
            seen.add(path)
            unique.append(path)
    return compile_check(unique)


if __name__ == "__main__":
    sys.exit(1 if main() else 0)
