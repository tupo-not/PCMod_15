
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
	
	// Create our ports
	local pts = {}
	table.insert( pts, self:CreatePort( "network" ) )
	table.insert( pts, self:CreatePort( "network" ) )
	table.insert( pts, self:CreatePort( "network" ) )
	table.insert( pts, self:CreatePort( "network" ) )
	local wan = self:CreatePort( self.WanType or "optic" )
	// An Ethernet WAN still looks like a normal network cable to the driver,
	// so flag it; the driver splits LAN and WAN by this flag rather than by
	// the physical cable type.
	if ((self.WanType == "network") && (wan.Type == "network")) then wan.WAN = true end
	table.insert( pts, wan )
	dt.Ports = pts
	
	// Install the main driver
	local drv = self:InstallDriver( "webgr_router" )
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
	self:SetGVar( "wireless", setupdata.Wireless )
	
	// Update us
	self:UpdateData( dt )
end

function ENT:RunOnRemove()
	PCMod.Network.UnRegisterRouter( self.Entity )
end

function ENT:DataRecieved( port, data )
	// Feed it straight through to the driver
	if (!PCMod.Data[ self:EntIndex() ].Drivers[ "webgr_router" ]) then return end
	PCMod.Data[ self:EntIndex() ].Drivers[ "webgr_router" ]:DataRecieved( port, data )
end