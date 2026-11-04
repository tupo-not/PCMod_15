
// ---------------------------------------------------------------------------------------------------------
// sv_network.lua - Revision 1
// Server-Side
// Controls the networking aspect of PCMod
// ---------------------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------------------------
// Define our library
// ---------------------------------------------------------------------------------------------------------

PCMod.Network = {}
PCMod.Network.Version = "1.0"
PCMod.Network.Packets = {}
PCMod.Network.NextID = 1
PCMod.Network.Subnets = {}
PCMod.Network.Backbones = {}
PCMod.Network.Availible = {}
PCMod.Network.Availible.Back = {}
PCMod.Network.Availible.Sub = {}

for i = 1, 255 do
	PCMod.Network.Availible.Back[ i ] = true
	PCMod.Network.Availible.Sub[ i ] = true
end

PCMod.Msg( "Network Library Loaded (V" .. PCMod.Network.Version .. ")", true )


// ---------------------------------------------------------------------------------------------------------
/* Basic Concept of how networking in PCMod works:
	
	Say we have 2 PCs, A and B. A wants to send a packet to B. It compiles the data to send in a table, and sends it to the router it is connected to.
	
	The router creates a packet out of the data. The packet contains the source, destination, port and data and it has a unique ID. The packet is stored in a global table.
	
	The router will then proceed to send that packet's ID to every other router it can.
	
	When a router recieves a packet ID, it will check 3 things.
	 - If the packet is flagged 'delivered', it will ignore it.
	 - If the packet has already been processed by the router, it will ignore it.
	 - If the packet's destination is a PC linked to the router, it will forward it to the PC.
	 
	 If the packet does not meet any of these conditions, the router will forward it on to other routers and record the fact that the packet has been processed.
	 
	This will, as long as there is a path from source to destination, ensure the packet will reach the target 100% of the time. (Unless a function call is ignored by the engine)
	
*/
// ---------------------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------------------------
// CreatePacket - Forms a packet, stores it, and returns the UID
// ---------------------------------------------------------------------------------------------------------
// Round 19 (AUDIT2 A-01): packet slots are recycled inside [1, MaxNetworkPid].
// Previously Packets[] grew without limit and ids grew past MaxNetworkPid, after
// which every router hard-rejected new packets ("Connection ERROR!") - the
// in-game network died permanently after MaxNetworkPid packets in one session.
function PCMod.Network.CreatePacket( source, dest, port, body )
	local maxpid = PCMod.Cfg.MaxNetworkPid or 500
	local pk = {}
	pk.Source = source
	pk.Dest = dest
	pk.Port = port
	pk.Body = body
	pk.Delivered = false
	// Dual-stack metadata: keep the address the program used and expose the
	// emulated IPv6 form of each endpoint. Routing still uses the IPv4 core.
	pk.SourceIPv4 = PCMod.IPv6.ToIPv4( source ) or source
	pk.DestIPv4 = PCMod.IPv6.ToIPv4( dest ) or dest
	pk.SourceIPv6 = PCMod.IPv6.FromIPv4( pk.SourceIPv4 )
	pk.DestIPv6 = PCMod.IPv6.FromIPv4( pk.DestIPv4 )
	// The /64 each endpoint belongs to (mapped IPv4 addresses get their
	// standard mapped /64, which is informational only).
	pk.SourceIPv6Prefix = pk.SourceIPv6 && PCMod.IPv6.GetPrefix( pk.SourceIPv6, 64 )
	pk.DestIPv6Prefix = pk.DestIPv6 && PCMod.IPv6.GetPrefix( pk.DestIPv6, 64 )
	local pid = PCMod.Network.NextID
	if ((pid < 1) || (pid > maxpid) || PCMod.Network.Packets[ pid ]) then
		pid = PCMod.Network.FindFreePacketSlot( maxpid, pid )
		// The slot held a previous packet - routers remember every pid they
		// processed (drv_router mem.P), so forget it everywhere or the new
		// packet would be dropped as "Already processed".
		if (PCMod.Network.Packets[ pid ]) then
			PCMod.Network.ClearPacketMemory( pid )
		end
	end
	PCMod.Network.Packets[ pid ] = pk
	PCMod.Network.NextID = pid + 1
	if (PCMod.Network.NextID > maxpid) then PCMod.Network.NextID = 1 end
	return pid
end

// ---------------------------------------------------------------------------------------------------------
// FindFreePacketSlot - Picks a free/recyclable packet id <= maxpid (never fails)
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.FindFreePacketSlot( maxpid, start )
	if (!start || start < 1 || start > maxpid) then start = 1 end
	// 1) an empty slot from the cursor upwards, then from 1 (ids stay ordered)
	for i = start, maxpid do
		if (!PCMod.Network.Packets[ i ]) then return i end
	end
	for i = 1, start - 1 do
		if (!PCMod.Network.Packets[ i ]) then return i end
	end
	// 2) table full: reclaim a delivered packet (its delivery is complete).
	//    Prefer ids >= start so reclamation rotates instead of pinning one slot.
	local ge, all
	for k, v in pairs(PCMod.Network.Packets) do
		if (v.Delivered) then
			if (k >= start && (!ge || k < ge)) then ge = k end
			if (!all || k < all) then all = k end
		end
	end
	if (ge) then return ge end
	if (all) then return all end
	// 3) pathological (all slots undelivered): rotate over occupied ids >= start,
	//    then from 1 - memory stays bounded, the network stays up, the oldest id
	//    in the rotation is sacrificed (its in-flight delivery may be misrouted).
	ge, all = nil, nil
	for k in pairs(PCMod.Network.Packets) do
		if (k >= start && (!ge || k < ge)) then ge = k end
		if (!all || k < all) then all = k end
	end
	return ge or all or 1
end

// ---------------------------------------------------------------------------------------------------------
// ClearPacketMemory - Forgets a recycled pid in every registered router
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.ClearPacketMemory( pid )
	if (!pid) then return end
	local function clear( list )
		for _, rtr in pairs( list ) do
			local ent = rtr.Ent
			if (IsValid( ent )) then
				local mem = ent:Memory()
				if (mem && mem.P && mem.P[ pid ]) then
					mem.P[ pid ] = nil
					ent:UpdateMemory( mem )
				end
			end
		end
	end
	clear( PCMod.Network.Subnets )
	clear( PCMod.Network.Backbones )
end

// ---------------------------------------------------------------------------------------------------------
// RegisterRouter - Registers a router with the network system
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.RegisterRouter( ent )
	local back = ""
	local rtr = {}
	local id
	rtr.LAN = {}
	rtr.Ent = ent
	rtr.EntID = ent:EntIndex()
	rtr.IsBackbone = false
	if (ent:GetClass() == "pcmod_brouter") then
		for _, v in pairs(PCMod.Network.Backbones) do
			if (v.EntID == rtr.EntID) then
				PCMod.Msg( "Router "..ent:EntIndex().."(Backbone) is already registered", true )
				return
			end
		end
		id = PCMod.Network.GetSub( true )
		rtr.IsBackbone = true
		if (!id) then
			rtr.Ent:ForceRemove( "No subnets availible" )
			return
		end
		PCMod.Network.Backbones[ id ] = rtr
		back = "(Backbone)"
		rtr.Ent:SetBSubnet( id )
		rtr.Ent:SetBIP( 0 )
	else
		for _, v in pairs(PCMod.Network.Subnets) do
			if (v.EntID == rtr.EntID) then
				PCMod.Msg( "Router "..ent:EntIndex().." is already registered", true )
				return
			end
		end
		id = PCMod.Network.GetSub( false )
		if (!id) then
			rtr.Ent:ForceRemove( "No subnets availible" )
			return
		end
		PCMod.Network.Subnets[ id ] = rtr
		rtr.Ent:SetSubnet( id )
		rtr.Ent:SetIP( 0 )
	end

	PCMod.Msg( "Registered router "..ent:EntIndex()..back.." and aquired subnet "..id, true )
	
	return true
end

// ---------------------------------------------------------------------------------------------------------
// UnRegisterRouter - Unregisters a router with the network system
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.UnRegisterRouter( ent )
	local res = PCMod.Network.FindSubByEnt( ent )
	local back = ""
	if (!res) then return end

	if (res[2]) then
		for i = 1, 10 do
			if (PCMod.Network.Backbones[ res[ 1 ] ].LAN[ i ]) then
				PCMod.Network.UnRegisterPC( PCMod.Network.Backbones[ res[ 1 ] ].LAN[ i ].Ent, res[ 1 ], true )
			end
		end
		PCMod.Network.Backbones[ res[ 1 ] ] = nil
		PCMod.Network.Availible.Back[ res[ 1 ] ] = true
		back = "(Backbone)"
	else
		for i = 1, 4 do
			if (PCMod.Network.Subnets[ res[ 1 ] ].LAN[ i ]) then
				PCMod.Network.UnRegisterPC( PCMod.Network.Subnets[ res[ 1 ] ].LAN[ i ].Ent, res[ 1 ], false )
			end
		end
		PCMod.Network.Subnets[ res[ 1 ] ] = nil
		PCMod.Network.Availible.Sub[ res[ 1 ] ] = true
	end

	PCMod.Msg( "Unregistered router "..ent:EntIndex()..back.." and released subnet "..res[1], true )
end

// ---------------------------------------------------------------------------------------------------------
// GetSub - Gets the subnet of an entity based on recount
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.GetSub( isBackbone, recount )
	// Round 27 (M-17): the allocation is a plain bounded scan now.
	// The old implementation called itself again whenever the availability
	// table was out of date (up to 255 levels of recursion) and - when the
	// address space was exhausted - returned 0 instead of false. 0 is
	// TRUTHY in Lua, so RegisterRouter did NOT see a failure and put the
	// router on the invalid subnet 0, where FindSubByEnt (which scans
	// 1..255) could never find it again - a "dead" router.
	// The availability table is now rebuilt from the real registrations on
	// every call, so it can never be out of date.
	local list = PCMod.Network.Subnets
	local avail = PCMod.Network.Availible.Sub
	if (isBackbone) then
		list = PCMod.Network.Backbones
		avail = PCMod.Network.Availible.Back
	end
	for i = 1, 255 do
		if (!list[ i ]) then
			avail[ i ] = true
		else
			avail[ i ] = false
		end
	end
	local found = 0
	for k, v in pairs( avail ) do
		if ((v == true) && (found == 0)) then found = k end
	end
	// no id left - the caller (RegisterRouter) removes the router instead
	// of registering it on subnet 0
	if (found == 0) then return false end
	avail[ found ] = false
	return found
end

// ---------------------------------------------------------------------------------------------------------
// FindSubByEnd - Gets the subnet based on the entity
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.FindSubByEnt( ent )
	local EntID = ent:EntIndex()
	for i = 1, 255 do
		if (PCMod.Network.Subnets[ i ] && PCMod.Network.Subnets[ i ].EntID == EntID) then
			return { i, false }
		end
	end
	for i = 1, 255 do
		if (PCMod.Network.Backbones[ i ] && PCMod.Network.Backbones[ i ].EntID == EntID) then
			return { i, true }
		end
	end
	return false
end

// ---------------------------------------------------------------------------------------------------------
// RegisterPC - Registers a tower with the network system
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.RegisterPC( ent, subnet, backbone )
	local pc = {}
	pc.Ent = ent
	pc.EntID = ent:EntIndex()
	local tmp
	local good = true
	PCMod.Msg( "Attempt RegisterPC("..ent:EntIndex()..", "..subnet..", "..tostring( backbone )..")", true )
	if (backbone) then
		tmp = PCMod.Network.Backbones[ subnet ]
		if(!PCMod.Network.Backbones[ subnet ]) then
			good = false
		end
		if (good) then
			for _, v in pairs(tmp.LAN) do
				if (v.EntID == pc.EntID) then
					PCMod.Msg( "Router "..ent:EntIndex().." is already registered to backbone", true )
					return
				end
			end
			for i = 1, 10 do
				if (!PCMod.Network.Backbones[ subnet ].LAN[ i ]) then
					PCMod.Network.Backbones[ subnet ].LAN[ i ] = pc
					pc.Ent:SetBSubnet( subnet )
					pc.Ent:SetBIP( i )
					PCMod.Msg( "Registered router "..ent:EntIndex().." to backbone and aquired ip 10.0."..subnet.."."..i, true )
					return
				end
			end
		end
	else
		tmp = PCMod.Network.Subnets[ subnet ]
		if(!PCMod.Network.Subnets[ subnet ]) then
			good = false
		end
		if (good) then
			for _, v in pairs(tmp.LAN) do
				if (v.EntID == pc.EntID) then
					PCMod.Msg( "PC "..ent:EntIndex().." is already registered to router", true )
					return
				end
			end
			for i = 1, 4 do
				if (!PCMod.Network.Subnets[ subnet ].LAN[ i ]) then
					PCMod.Network.Subnets[ subnet ].LAN[ i ] = pc
					pc.Ent:SetSubnet( subnet )
					pc.Ent:SetIP( i )
					PCMod.Msg( "Registered pc "..ent:EntIndex().." to router and aquired ip 192.168."..subnet.."."..i, true )
					return
				end
			end
		end
	end
	local port
	for k, v in pairs(ent:Ports()) do
		if ((v.Type == "network" || v.Type == "optic") && (!tmp || v.ConEnt == tmp.Ent)) then
			port = k
		end
	end
	PCMod.Wiring.UnlinkPort( ent, port )
	if (good) then
		PCMod.Notice( "No ips availible", ent:GetOwner() )
	else
		PCMod.Notice( "Invalid subnet", ent:GetOwner() )
	end
end

// ---------------------------------------------------------------------------------------------------------
// UnRegisterPC - Unregisters a tower with the network system
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.UnRegisterPC( ent, subnet, backbone )
	if (backbone) then
		if (!PCMod.Network.Backbones[ subnet ]) then return end
		for i = 1, 10 do
			if (PCMod.Network.Backbones[ subnet ].LAN[ i ] && PCMod.Network.Backbones[ subnet ].LAN[ i ].EntID == ent:EntIndex()) then
				PCMod.Network.Backbones[ subnet ].LAN[ i ] = nil
				ent:SetBSubnet( false )
				ent:SetBIP( false )
				PCMod.Msg( "Unregistered router "..ent:EntIndex().." from backbone and released ip 10.0."..subnet.."."..i, true )
				return
			end
		end
	else
		if (!PCMod.Network.Subnets[ subnet ]) then return end
		for i = 1, 4 do
			if (PCMod.Network.Subnets[ subnet ].LAN[ i ] && PCMod.Network.Subnets[ subnet ].LAN[ i ].EntID == ent:EntIndex()) then
				PCMod.Network.Subnets[ subnet ].LAN[ i ] = nil
				ent:SetSubnet( false )
				ent:SetIP( false )
				PCMod.Msg( "Unregistered pc "..ent:EntIndex().." from router and released ip 192.168."..subnet.."."..i, true )
				return
			end
		end
	end
end