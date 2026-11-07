// ---------------------------------------------------------------------------------------------------------
// pcmod_erouter
// Router entity - same as the LAN modem, but the WAN side is Ethernet instead
// of fibre so it can sit behind a separate modem.
// ---------------------------------------------------------------------------------------------------------

ENT.Type = "anim"
ENT.Base = "pcmod_router"
ENT.PrintName = "Router"
ENT.Class = "pcmod_erouter"

ENT.ItemModel = "models/props_lab/reciever01a.mdl"

// The LAN-side behaviour (DHCP, NAT, web page, wireless) is inherited from
// pcmod_router; only the WAN cable type differs.
ENT.WanType = "network"

ENT.IsNetworkDevice = true

if (SERVER) then AddCSLuaFile( "shared.lua" ) end
