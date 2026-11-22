
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
// CreateRopeTable - Creates a PCMod-owned cable and its legacy entity table.
// Clearing constraint.Type keeps the generic duplicator from creating a second
// cable; BuildDupeInfo/ApplyDupeInfo restore this one with the logical link.
// ---------------------------------------------------------------------------------------------------------
function PCMod.Wiring.CreateRopeTable( srcent, destent, data )
	data = data || {}
	local const, rope = constraint.Rope(
		srcent, destent, data.bone1 || 0, data.bone2 || 0,
		data.lpos1, data.lpos2, data.length || 0, data.addlength || 0,
		data.forcelimit || 0, data.width || 1, data.material || "cable/rope",
		data.rigid == true, data.color
	)
	if (IsValid( const )) then const.Type = nil end
	local rps = {}
	if (const || rope) then rps = { { const, rope } } end
	return rps
end

// Serialize only PCMod-owned ropes. Legacy Type="Rope" constraints remain
// owned by the generic duplicator for backwards compatibility.
function PCMod.Wiring.GetRopeData( ropetable, owner )
	for _, group in pairs( ropetable || {} ) do
		for _, ent in pairs( group ) do
			if (IsValid( ent ) && (ent.Type == nil) && ent.LPos1 && ent.LPos2) then
				local forward = (ent.Ent1 == owner)
				if (forward || (ent.Ent2 == owner)) then
					return {
						bone1 = forward && ent.Bone1 || ent.Bone2,
						bone2 = forward && ent.Bone2 || ent.Bone1,
						lpos1 = forward && ent.LPos1 || ent.LPos2,
						lpos2 = forward && ent.LPos2 || ent.LPos1,
						length = ent.length,
						addlength = ent.addlength,
						forcelimit = ent.forcelimit,
						width = ent.width,
						material = ent.material,
						rigid = ent.rigid,
						color = ent.color,
					}
				end
			end
		end
	end
	return nil
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
	local dest = destent:Ports()[source.RemotePort]
	if (dest) then
		dest.Connected = false
		dest.ConEnt = nil
		dest.RemotePort = 0
		if (dest.RopeTable) then PCMod.Wiring.UnlinkRopeTable( dest.RopeTable ) end
		dest.RopeTable = nil
		destent:UpdatePort( source.RemotePort, dest )
	end
	// Capture the peer's port BEFORE clearing it: the unlinked event must carry
	// the real port index, not the zeroed RemotePort.
	local remoteprt = source.RemotePort
	source.Connected = false
	source.ConEnt = nil
	source.RemotePort = 0
	srcent:UpdatePort( srcprt, source )
	srcent:FireEvent( { "unlinked", srcprt, destent } )
	destent:FireEvent( { "unlinked", remoteprt, srcent } )
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
