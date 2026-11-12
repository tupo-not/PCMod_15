
// ---------------------------------------------------------------------------------------------------------
// pcmod_brouter
// Backbone Router entity - high-speed router linker
// ---------------------------------------------------------------------------------------------------------

ENT.Type = "anim"
ENT.Base = "pcmod_base"
ENT.PrintName = "Backbone Router"
ENT.Class = "pcmod_brouter"

ENT.ItemModel = "models/props_lab/reciever01b.mdl"

ENT.IsNetworkDevice = true

ENT.DefaultSetupData = {
	Wireless = false,
}

if (SERVER) then AddCSLuaFile( "shared.lua" ) end

function ENT:Setup( setupdata )
	if (!setupdata) then setupdata = self.DefaultSetupData end -- Ensure we have setup data
	local dt = self:Data() -- Get our data
	
	// Create our ports. The first ten are fibre backbone links; the last is a
	// dedicated Ethernet management port (MGMNT) used to reach the web panel.
	local pts = {}
	table.insert( pts, self:CreatePort( "optic" ) )
	table.insert( pts, self:CreatePort( "optic" ) )
	table.insert( pts, self:CreatePort( "optic" ) )
	table.insert( pts, self:CreatePort( "optic" ) )
	table.insert( pts, self:CreatePort( "optic" ) )
	table.insert( pts, self:CreatePort( "optic" ) )
	table.insert( pts, self:CreatePort( "optic" ) )
	table.insert( pts, self:CreatePort( "optic" ) )
	table.insert( pts, self:CreatePort( "optic" ) )
	table.insert( pts, self:CreatePort( "optic" ) )
	local mgmt = self:CreatePort( "network" )
	mgmt.Name = "MGMNT"
	mgmt.Management = true
	table.insert( pts, mgmt )
	dt.Ports = pts
	
	// Install the router subsystem
	self:InstallSubsystem( "router" )

	local registered = PCMod.Network.RegisterRouter( self.Entity )
	if (!registered) then
		PCMod.Warning( "== ROUTER FAILED TO REGISTER ==" )
		self:SetGVar( "noreg", true )
		return
	end

	// Update us
	self:UpdateData( dt )
end

function ENT:RunOnRemove()
	PCMod.Network.UnRegisterRouter( self.Entity )
end

function ENT:DataRecieved( port, data )
	// Feed it straight through to the subsystem
	if (!PCMod.Data[ self:EntIndex() ].Subsystems[ "router" ]) then return end
	PCMod.Data[ self:EntIndex() ].Subsystems[ "router" ]:DataRecieved( port, data )
end