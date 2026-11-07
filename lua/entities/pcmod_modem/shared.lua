// ---------------------------------------------------------------------------------------------------------
// pcmod_modem
// Media converter - bridges a fibre uplink to Ethernet. It has no addresses,
// DHCP, NAT or routing; it only repeats frames between its two media.
// ---------------------------------------------------------------------------------------------------------

ENT.Type = "anim"
ENT.Base = "pcmod_switch"
ENT.PrintName = "Modem"
ENT.Class = "pcmod_modem"

ENT.ItemModel = "models/props_lab/reciever01b.mdl"

ENT.IsSwitch = true
ENT.IsModem = true

ENT.PortCount = 2

if (SERVER) then AddCSLuaFile( "shared.lua" ) end

function ENT:Setup( setupdata )
	local dt = self:Data()
	dt.IsSwitch = true
	dt.IsModem = true

	// One fibre uplink and one Ethernet link, bridged together.
	local pts = {}
	table.insert( pts, self:CreatePort( "optic" ) )
	table.insert( pts, self:CreatePort( "network" ) )
	dt.Ports = pts

	local macs = dt.PortMACs
	if ((!PCMod.MAC.IsValid( dt.MAC )) || (type( macs ) != "table") || (#macs != self.PortCount)) then
		self:GenerateMACs()
	end
	for i = 1, self.PortCount do
		if (!PCMod.MAC.IsValid( dt.PortMACs[ i ])) then dt.PortMACs[ i ] = PCMod.MAC.Random() end
	end

	self:SetNWString( "MAC", dt.MAC )
	self:UpdateData( dt )

	// Keep the routing topology transparent across the converter.
	self:AddEHook( "ent", nil, "linked" )
	self:AddEHook( "ent", nil, "unlinked" )
end
