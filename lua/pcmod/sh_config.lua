
// ---------------------------------------------------------------------------------------------------------
// sh_config.lua - Revision 1
// Shared
// Server overrides applied after the defaults in sh_baseconfig.lua.
//
// sh_baseconfig.lua owns every default and the compatibility-sensitive tables
// (WireTypes, RPCost, RPDisks, ...). This file only changes what a server
// actually wants to change, so a default can never silently diverge in two
// places again.
// ---------------------------------------------------------------------------------------------------------

// Advertise PCMod with a timed chat message and enable RP purchases.
cfg.TimedMessage = false
cfg.RPMode = true

// Boot pacing and UI scale.
cfg.BootSpeed = 0.25
cfg.GuiScale = 0.5

// Keep the remover tool from deleting PCMod devices (Shift bypasses).
cfg.RemoverProtection = true

// Packet slot capacity and IP TTL defaults. Packet ids are recycled inside
// [1, MaxNetworkPid] by sv_network.lua.
// TTL is the IPv4 maximum, so a large backbone (hundreds of routers) stays
// reachable; loops are still bounded by it and by MaxNetworkPass.
cfg.MaxNetworkPid = 500
cfg.DefaultTTL = 255
cfg.TraceMaxHops = 255

// UI command rate limit: one window per this many seconds, with a small
// same-tick burst allowance for multi-step UI actions.
cfg.CommandFlood = 0.05

// Marks the configuration as fully loaded. sh_baseconfig validates this.
cfg.Loaded = true
