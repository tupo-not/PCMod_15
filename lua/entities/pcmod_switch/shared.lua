// ---------------------------------------------------------------------------------------------------------
// pcmod_switch
// Network switch entity - Ethernet or optical, forwards frames between its ports
// ---------------------------------------------------------------------------------------------------------

ENT.Type = "anim"
ENT.Base = "pcmod_base"
ENT.PrintName = "Switch"
ENT.Class = "pcmod_switch"

ENT.ItemModel = "models/props_lab/reciever01a.mdl"

ENT.IsSwitch = true

ENT.DefaultSetupData = {
	Mode = "ethernet",
}

ENT.PortCount = 8
ENT.PortTypes = {
	ethernet = "network",
	optic = "optic",
}

if (SERVER) then AddCSLuaFile( "shared.lua" ) end

// ---------------------------------------------------------------------------------------------------------
// MAC addresses
// ---------------------------------------------------------------------------------------------------------
// Switches are identified by a random base MAC and have one random MAC per port.
// They are generated once on spawn and persisted both by the duplicator
// (pcmod_base BuildDupeInfo / ApplyDupeInfo) and by map saves (OnSave /
// OnRestore), so a copied or saved world keeps the same addresses.
function ENT:GenerateMACs()
	local dt = self:Data()
	dt.MAC = PCMod.MAC.Random()
	dt.PortMACs = {}
	for i = 1, self.PortCount do
		dt.PortMACs[ i ] = PCMod.MAC.Random()
	end
	return dt
end

function ENT:GetPortMAC( port )
	local macs = self:Data().PortMACs
	if (!macs) then return nil end
	return macs[ port ]
end

function ENT:SetMACs( mac, portmacs )
	local dt = self:Data()
	if (PCMod.MAC.IsValid( mac )) then dt.MAC = PCMod.MAC.Normalize( mac ) end
	if (type( portmacs ) == "table") then dt.PortMACs = portmacs end
	self:UpdateData( dt )
	self:SetNWString( "MAC", dt.MAC )
end

// ---------------------------------------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------------------------------------

function ENT:Setup( setupdata )
	if (!setupdata) then setupdata = self.DefaultSetupData end
	local mode = setupdata.Mode
	if (!self.PortTypes[ mode ]) then mode = "ethernet" end

	local dt = self:Data()
	dt.Mode = mode
	dt.IsSwitch = true

	// Create the ports for the selected configuration.
	local pts = {}
	for i = 1, self.PortCount do
		table.insert( pts, self:CreatePort( self.PortTypes[ mode ] ) )
	end
	dt.Ports = pts

	// MACs are generated once. A restored entity keeps the ones saved in its
	// dupe info; Setup only fills in what is missing.
	local macs = dt.PortMACs
	if ((!PCMod.MAC.IsValid( dt.MAC )) || (type( macs ) != "table") || (#macs != self.PortCount)) then
		self:GenerateMACs()
	end
	for i = 1, self.PortCount do
		if (!PCMod.MAC.IsValid( dt.PortMACs[ i ] )) then dt.PortMACs[ i ] = PCMod.MAC.Random() end
	end

	self:SetNWString( "MAC", dt.MAC )
	self:UpdateData( dt )
end

// ---------------------------------------------------------------------------------------------------------
// Pure L2 bridge
// ---------------------------------------------------------------------------------------------------------
// The switch keeps only a MAC -> port table. All forwarding decisions live in
// pcmod/sh_l2.lua so the entity itself stays a thin hardware wrapper.

function ENT:LearnMAC( mac, port )
	PCMod.L2.Learn( self, mac, port )
end

function ENT:PortForMAC( mac )
	return PCMod.L2.PortForMAC( self, mac )
end

function ENT:DataRecieved( port, data )
	return PCMod.L2.Receive( self, port, data )
end
