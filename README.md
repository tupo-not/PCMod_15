# PCMod NEXT

Interactive computers for Garry's Mod: Personal and Server OS, programs, virtual files, printers, AlarmZ camera monitoring, USB devices, and a simulated IPv4/IPv6 network.

## Quick start

1. Open the tool gun's **PCmod** tab and spawn a **Computer Tower**, **Monitor**, and **Keyboard**. Choose **Personal OS** for the normal desktop.
2. Use **Wire Tool** to connect tower **VGA → monitor** and keyboard **PS2 → tower**.
3. Press **E** on the tower to turn it on, then **E** on the monitor to use the computer. Complete the first-run setup.
4. Open **Control Panel** for themes, network settings, Wi-Fi, and devices. Use **File Manager**, **Notepad**, **Browser**, and the running-program taskbar to work with windows.
5. Use **Install Disk** to add programs: **RMB** selects a program, **LMB** installs it on the targeted computer.

## AlarmZ

Install **AlarmZ**, then hold **Camera Link** and look at a Wiremod RT camera. Use **E/LMB** to connect it to a PCMod screen; **RMB** disconnects it. Protected cameras require their password for connection and disconnection.

## Networking

- Towers have two Ethernet ports; switches, LAN/backbone routers, and fibre/Ethernet modems are supported.
- DHCP assigns addresses automatically. Static IPv4, emulated IPv6, multi-NIC, Wi-Fi, NAT, firewall rules, and port forwarding are available.
- The browser works only with numeric IPv4/IPv6 addresses **inside the PCMod network**. It does not provide real Internet access or DNS.
- Router administration is available from the router's LAN/management side, not from WAN.

## Notes

- The default monitor model is from **Counter-Strike: Source**. AlarmZ cameras require **Wiremod**.
- Do not run this addon together with an older PCMod installation. Back up `data/pcmod/` before upgrading.
- Server-side changes need a map restart; client-side changes need a reconnect. Existing per-PC programs may need `sys_resetprog <name>` or a respawn.
- Useful commands: `pc_guiscale <0.25-3>`, `pc_kickstart`, `pc_debug_hitbox 1`, and `pc_settings`.
- Source and issue tracker: <https://github.com/tupo-not/PCMod_15>

## Tests

The source repository includes mock suites for the VFS, programs, UI, networking, wiring, and AlarmZ:

```sh
cd tests && ./run_tests.sh
```

Requirements: Python 3 and Lua 5.1 (`lua5.1`, `luac5.1`). Generated files under `tests/.build/` are not part of the addon.
