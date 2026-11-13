
// ---------------------------------------------------------------------------------------------------------
// sv_wiring.lua - Revision 1
// Server-Side
// Loads wiring based functions
// ---------------------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------------------------
// Define our library
// ---------------------------------------------------------------------------------------------------------

PCMod.Wiring = {}
PCMod.Wiring.Version = "1.0"
PCMod.Wiring.WireTypes = PCMod.Cfg.WireTypes

// Maximum distance from the player to the cable end being clicked. 0 disables
// the limit. The default (cfg.WireRange) keeps normal reach; a server admin can
// lower or raise it at runtime with pcmod_wire_maxdist.
local defaultWireRange = tonumber( PCMod.Cfg && PCMod.Cfg.WireRange ) or 140
local WireRangeCvar = (GetConVar && GetConVar( "pcmod_wire_maxdist" )) or nil
if ((!WireRangeCvar) && CreateConVar) then
	WireRangeCvar = CreateConVar( "pcmod_wire_maxdist", tostring( defaultWireRange ),
		(FCVAR_ARCHIVE or 0) + (FCVAR_REPLICATED or 0),
		"Maximum distance from the player to the cable end being clicked. 0 = unlimited." )
end

function PCMod.Wiring.WireRange()
	if (WireRangeCvar != nil) then return WireRangeCvar:GetFloat() end
	local cv = GetConVar && GetConVar( "pcmod_wire_maxdist" )
	if (cv != nil) then return cv:GetFloat() end
	return tonumber( PCMod.Cfg && PCMod.Cfg.WireRange ) or 0
end

PCMod.Msg( "Wiring Library Loaded (V" .. PCMod.Wiring.Version .. ")", true )


// ---------------------------------------------------------------------------------------------------------
// TypeToName - Converts a port type to the nice name
// ---------------------------------------------------------------------------------------------------------
function PCMod.Wiring.TypeToName( ptype )
	for _, v in pairs( PCMod.Wiring.WireTypes ) do
		if (v.Name == ptype) then return v.ExtName end
	end
	return "Unknown"
end

// ---------------------------------------------------------------------------------------------------------
// CanWireSameType - Determines if a wire type can be wired to the same class
// ---------------------------------------------------------------------------------------------------------
function PCMod.Wiring.CanWireSameType( ptype )
	for _, v in pairs( PCMod.Wiring.WireTypes ) do
		if (v.Name == ptype) then return v.SameType end
	end
	return false
end

// ---------------------------------------------------------------------------------------------------------
// WithinReach - Can the player click this cable end?
// The player picks a port on the first device, then walks/aims to the second
// and clicks it. Only the end being clicked now (ent2) has to be near; the
// first end may be behind them. This also caps the actual click distance, so a
// ray/overlay limit cannot be bypassed by wiring from a far corner.
// ---------------------------------------------------------------------------------------------------------
function PCMod.Wiring.WithinReach( ply, ent1, ent2 )
	local reach = PCMod.Wiring.WireRange()
	// 0 (or less) disables the distance check entirely.
	if ((!reach) || (reach <= 0)) then return true end
	local from = (ply && ply.GetShootPos && ply:GetShootPos()) or (ply && ply.GetPos && ply:GetPos())
	if (!from) then return true end
	local ent = ent2 or ent1
	if ((!ent) || (!ent.IsValid) || (!ent:IsValid())) then return false end
	local to = ent.GetPos && ent:GetPos()
	if (!to) then return true end
	return ((from - to):Length() <= reach)
end

// ---------------------------------------------------------------------------------------------------------
// LinkPorts - Links two ports together
// ---------------------------------------------------------------------------------------------------------
function PCMod.Wiring.LinkPorts( srcent, srcprt, destent, destprt, ropetable )
	if ((!srcent) || (!srcent:IsValid()) || (!srcent.IsPCMod)) then return false end
	if ((!destent) || (!destent:IsValid()) || (!destent.IsPCMod)) then return false end
	local source = srcent:Ports()[srcprt]
	if (!source) then return false end
	local dest = destent:Ports()[destprt]
	if (!dest) then return false end
	if (source.Connected || dest.Connected) then return false end
	source.Connected = true
	source.ConEnt = destent
	source.RemotePort = destprt
	source.RopeTable = ropetable
	srcent:UpdatePort( srcprt, source )
	dest.Connected = true
	dest.ConEnt = srcent
	dest.RemotePort = srcprt
	dest.RopeTable = ropetable
	destent:UpdatePort( destprt, dest )
	srcent:FireEvent( { "linked", srcprt } )
	destent:FireEvent( { "linked", destprt } )
	return true
end

// ---------------------------------------------------------------------------------------------------------
// UnlinkPort - Unlinks a port, as well as it's target
// ---------------------------------------------------------------------------------------------------------
function PCMod.Wiring.UnlinkPort( srcent, srcprt )
	if ((!srcent) || (!srcent:IsValid()) || (!srcent.IsPCMod)) then return false end
	local source = srcent:Ports()[srcprt]
	if (!source) then return false end
	if (source.RopeTable) then PCMod.Wiring.UnlinkRopeTable( source.RopeTable ) end
	source.RopeTable = nil
	if (!source.Connected) then return false end
	local destent = source.ConEnt
	if ((!destent) || (!destent:IsValid()) || (!destent.IsPCMod)) then return false end
	// Keep the destination port id before the source is reset. The destination's
	// "unlinked" event needs it to release the interface lease for that port;
	// after the reset it used to arrive as 0.
	local remotePort = source.RemotePort
	local dest = destent:Ports()[remotePort]
	if (dest) then
		dest.Connected = false
		dest.ConEnt = nil
		dest.RemotePort = 0
		if (dest.RopeTable) then PCMod.Wiring.UnlinkRopeTable( dest.RopeTable ) end
		dest.RopeTable = nil
		destent:UpdatePort( remotePort, dest )
	end
	source.Connected = false
	source.ConEnt = nil
	source.RemotePort = 0
	srcent:UpdatePort( srcprt, source )
	srcent:FireEvent( { "unlinked", srcprt, destent } )
	destent:FireEvent( { "unlinked", remotePort, srcent } )
	return true
end

// ---------------------------------------------------------------------------------------------------------
// UnlinkRopeTable - Destroys all ropes and constraints in a table (should work for any entity type)
// ---------------------------------------------------------------------------------------------------------
function PCMod.Wiring.UnlinkRopeTable( ropetable )
	for _, tbl in pairs( ropetable ) do
		for _, ent in pairs( tbl ) do
			if ((ent) && (ent:IsValid())) then ent:Remove() end
		end
	end
	ropetable = {}
	return ropetable
end
