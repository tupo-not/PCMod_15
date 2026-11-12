
// ---------------------------------------------------------------------------------------------------------
// pcmod_router
// Router entity - networking node
// ---------------------------------------------------------------------------------------------------------

ENT.Type = "anim"
ENT.Base = "pcmod_base"
ENT.PrintName = "LAN Modem"
ENT.Class = "pcmod_router"

ENT.ItemModel = "models/props_lab/reciever01a.mdl"

// WAN side medium. The LAN Modem uses fibre; the Router variant uses Ethernet.
ENT.WanType = "optic"

ENT.IsNetworkDevice = true

ENT.DefaultSetupData = {
	Wireless = false,
	WirePass = "123",
}

if (SERVER) then AddCSLuaFile( "shared.lua" ) end

function ENT:Setup( setupdata )
	if (!setupdata) then setupdata = self.DefaultSetupData end -- Ensure we have setup data
	local dt = self:Data() -- Get our data
	
	// Create our ports. Port 1 is always the WAN uplink so wiring and the
	// admin pages are predictable; 2-5 are the LAN switch ports. The uplink
	// medium is selectable (fibre or Ethernet), so one tool can spawn both the
	// LAN Modem and the Router variants.
	local uplink = setupdata.Uplink
	if ((uplink != "network") && (uplink != "optic")) then uplink = self.WanType or "optic" end
	if ((uplink != "network") && (uplink != "optic")) then uplink = "optic" end
	local pts = {}
	local wan = self:CreatePort( uplink )
	// An Ethernet WAN still looks like a normal network cable to the router,
	// so flag it; the router splits LAN and WAN by this flag rather than by
	// the physical cable type.
	if ((uplink == "network") && (wan.Type == "network")) then wan.WAN = true end
	table.insert( pts, wan )
	for i = 1, 4 do
		table.insert( pts, self:CreatePort( "network" ) )
	end
	dt.Ports = pts
	
	// Install the router subsystem
	local drv = self:InstallSubsystem( "router" )
	drv.Wireless = setupdata.Wireless

	// Register our data
	local registered = PCMod.Network.RegisterRouter( self.Entity )
	if (!registered) then
		PCMod.Warning( "== ROUTER FAILED TO REGISTER ==" )
		self:SetGVar( "noreg", true )
		return
	end
	// Registration resets the LAN gateway to 192.168.0.1; move it onto the
	// router's configured network instead (custom third octet / netmask).
	if (drv.ApplyLanAddress) then drv:ApplyLanAddress() end
	dt.IsWireless = setupdata.Wireless
	dt.WirePass = setupdata.WirePass or "123"
	// InstallSubsystem's Initialize may have seeded RouterCfg before the setup
	// options were known. Re-apply the spawn choice through the normal setter,
	// which also publishes the SSID for the look-at overlay.
	self:UpdateData( dt )
	if (drv.SetWireless) then
		drv:SetWireless( setupdata.Wireless == true )
	else
		self:SetGVar( "wireless", setupdata.Wireless )
	end
end

function ENT:RunOnRemove()
	PCMod.Network.UnRegisterRouter( self.Entity )
end

function ENT:DataRecieved( port, data )
	// Feed it straight through to the subsystem
	if (!PCMod.Data[ self:EntIndex() ].Subsystems[ "router" ]) then return end
	PCMod.Data[ self:EntIndex() ].Subsystems[ "router" ]:DataRecieved( port, data )
end