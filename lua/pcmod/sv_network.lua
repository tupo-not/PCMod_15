
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
PCMod.Network.Backbones = {}
PCMod.Network.Availible = {}
PCMod.Network.Availible.Back = {}

for i = 1, 65535 do
	PCMod.Network.Availible.Back[ i ] = true
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
		// Never alias a new packet onto an in-flight id. Routers keep
		// asynchronous references to these ids, so reuse is only safe after
		// delivery (or when the slot was already empty).
		if (!pid) then return nil end
		// The slot held a delivered packet - routers remember every pid they
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
// FindFreePacketSlot - Picks a free/recyclable packet id <= maxpid.
// Returns nil when every slot is still in flight; callers must backpressure.
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
	// 3) Every slot is still in flight. Reusing one would let stale router
	//    references deliver the new packet as if it were the old one.
	return nil
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
		// A LAN router owns a private, isolated LAN. It does not consume a
		// globally-unique subnet: every router's LAN is 192.168.0.0/24 (or /16),
		// and the LAN knows nothing about the wider network.
		rtr.Ent:SetSubnet( 0 )
		rtr.Ent:SetIP( 1 )
	end

	PCMod.Msg( "Registered router "..ent:EntIndex()..back.." (subnet "..tostring( id )..")", true )
	
	return true
end

// ---------------------------------------------------------------------------------------------------------
// UnRegisterRouter - Unregisters a router with the network system
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.UnRegisterRouter( ent )
	local res = PCMod.Network.FindSubByEnt( ent )
	if (!res) then return end

	for i = 1, 10 do
		if (PCMod.Network.Backbones[ res ].LAN[ i ]) then
			PCMod.Network.UnRegisterPC( PCMod.Network.Backbones[ res ].LAN[ i ].Ent, res, true )
		end
	end
	PCMod.Network.Backbones[ res ] = nil
	PCMod.Network.Availible.Back[ res ] = true

	PCMod.Msg( "Unregistered backbone "..ent:EntIndex().." and released /32 "..res, true )
end

// ---------------------------------------------------------------------------------------------------------
// GetSub - Allocate a free backbone /32 id
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.GetSub()
	local list = PCMod.Network.Backbones
	local avail = PCMod.Network.Availible.Back
	for i = 1, 65535 do
		if (!list[ i ]) then avail[ i ] = true else avail[ i ] = false end
	end
	local found = 0
	for k, v in pairs( avail ) do
		if ((v == true) && (found == 0)) then found = k end
	end
	if (found == 0) then return false end
	avail[ found ] = false
	return found
end

// ---------------------------------------------------------------------------------------------------------
// FindSubByEnt - Gets the backbone /32 id of a backbone router
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.FindSubByEnt( ent )
	local EntID = ent:EntIndex()
	for i = 1, 65535 do
		if (PCMod.Network.Backbones[ i ] && PCMod.Network.Backbones[ i ].EntID == EntID) then return i end
	end
	return false
end

// ---------------------------------------------------------------------------------------------------------
// RegisterPC - Registers a LAN router onto a backbone (assigns its 10.x WAN
// /32 NAT address). LAN PCs get their private lease from the router instead.
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.RegisterPC( ent, subnet )
	local pc = {}
	pc.Ent = ent
	pc.EntID = ent:EntIndex()
	local tmp = PCMod.Network.Backbones[ subnet ]
	if (!tmp) then return "invalid" end
	for _, v in pairs( tmp.LAN ) do
		if (v.EntID == pc.EntID) then
			PCMod.Msg( "Router "..ent:EntIndex().." is already registered to backbone", true )
			return "exists"
		end
	end
	for i = 1, 10 do
		if (!tmp.LAN[ i ]) then
			tmp.LAN[ i ] = pc
			pc.Ent:SetBSubnet( subnet )
			pc.Ent:SetBIP( i )
			PCMod.Msg( "Registered router "..ent:EntIndex().." to backbone and aquired ip "..PCMod.IPv4.BackboneAddress( subnet, i + 1 ), true )
			return "assigned"
		end
	end
	return "full"
end

// ---------------------------------------------------------------------------------------------------------
// UnRegisterPC - Removes a LAN router from a backbone
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.UnRegisterPC( ent, subnet )
	local tmp = PCMod.Network.Backbones[ subnet ]
	if (!tmp) then return end
	for i = 1, 10 do
		if (tmp.LAN[ i ] && tmp.LAN[ i ].EntID == ent:EntIndex()) then
			tmp.LAN[ i ] = nil
			ent:SetBSubnet( false )
			ent:SetBIP( false )
			PCMod.Msg( "Unregistered router "..ent:EntIndex().." from backbone and released ip "..PCMod.IPv4.BackboneAddress( subnet, i + 1 ), true )
			return
		end
	end
end

// ---------------------------------------------------------------------------------------------------------
// Reconverge - Recompute the backbone /32 routing tables (distance vector).
// Called whenever a backbone link is added or removed; synchronously floods
// each backbone's distance vector until the tables stabilise.
// ---------------------------------------------------------------------------------------------------------
function PCMod.Network.Reconverge()
	local list = {}
	for _, r in pairs( PCMod.Network.Backbones or {} ) do
		if ((r) && (r.Ent)) then table.insert( list, r.Ent ) end
	end
	for _, ent in ipairs( list ) do
		local data = PCMod.Data[ ent:EntIndex() ]
		local drv = data && data.Drivers && data.Drivers[ "webgr_router" ]
		if (drv && drv.RecalcRoutes) then drv:RecalcRoutes() end
	end
	// A path graph of N backbones converges in N iterations.
	for i = 1, 32 do
		for _, ent in ipairs( list ) do
			local data = PCMod.Data[ ent:EntIndex() ]
			local drv = data && data.Drivers && data.Drivers[ "webgr_router" ]
			if (drv && drv.AdvertiseRoutes) then drv:AdvertiseRoutes() end
		end
	end
end