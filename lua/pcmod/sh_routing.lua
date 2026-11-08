// ---------------------------------------------------------------------------------------------------------
// sh_routing.lua - broadcast hello routing
//
// Backbone routers exchange distance vectors in hellos that switches flood as
// ordinary L2 broadcasts. LAN routers advertise the /64 they own. No switch
// relays router events; routing is a router-to-router protocol.
// ---------------------------------------------------------------------------------------------------------

PCMod = PCMod or {}
PCMod.Routing = PCMod.Routing or {}

PCMod.Routing.HelloInterval = 5
PCMod.Routing.HelloTimeout = 20

function PCMod.Routing.Prefixes( router )
	local out = {}
	if (router:IsBackbone()) then
		// A backbone has no /64 of its own; it re-advertises the child /64s
		// learned from attached LAN routers. Backbone /32s travel in the DV,
		// not here, so they never look like connected devices.
		for prefix, rec in pairs( router.PrefixRoutes or {} ) do
			out[ prefix ] = { origin = rec.origin or 0, hops = rec.hops or 0 }
		end
	elseif (router.Entity.GetIPv6Prefix) then
		local p = router.Entity:GetIPv6Prefix()
		if (p) then
			local bb = (router.Entity.GetBSubnet && router.Entity:GetBSubnet()) or 0
			out[ p ] = { origin = bb, hops = 0 }
		end
	end
	return out
end

function PCMod.Routing.Body( router, dv, prefixes )
	local ent = router.Entity
	local bb = ent.GetBSubnet && ent:GetBSubnet() or nil
	local ip = (ent.GetFullBIP && ent:GetFullBIP()) or (ent.GetFullIP && ent:GetFullIP()) or nil
	if ((dv == nil) && router:IsBackbone() && router.GetDV) then dv = router:GetDV() end
	if (!prefixes) then prefixes = PCMod.Routing.Prefixes( router ) end
	return PCMod.Net.Hello( bb, ip, ent:GetMAC(), dv, prefixes )
end

// Broadcast a hello out every backbone/WAN port. Backbones use split horizon:
// the distance vector sent to a neighbour omits routes learned through it, and
// a /64 is never sent back out the port it was learned from.
function PCMod.Routing.Send( router, force )
	if ((!router) || (!router.Entity)) then return end
	local now = CurTime()
	if ((!force) && router.LastHello && ((now - router.LastHello) < (PCMod.Routing.HelloInterval or 5))) then return end
	router.LastHello = now
	// Make sure our own /32 is in the table before advertising, otherwise a
	// freshly spawned backbone would send an empty DV and no neighbour could
	// ever learn about it.
	if (router:IsBackbone() && router.RecalcRoutes) then router:RecalcRoutes() end
	local mac = router.Entity:GetMAC()
	local prefixes = PCMod.Routing.Prefixes( router )
	local ports = router.OPorts or {}
	for _, idx in ipairs( ports ) do
		local p = router.Entity:Ports()[ idx ]
		if (p && p.Connected) then
			local dv = nil
			if (router:IsBackbone() && router.GetDV) then
				local excl = nil
				for nbb, nport in pairs( router.Neighbors or {} ) do
					if (nport == idx) then excl = nbb break end
				end
				dv = router:GetDV( excl )
			end
			local pfx = {}
			for prefix, info in pairs( prefixes ) do
				local rec = router.PrefixRoutes && router.PrefixRoutes[ prefix ]
				if ((!rec) || (rec.port != idx)) then pfx[ prefix ] = info end
			end
			local body = PCMod.Routing.Body( router, dv, pfx )
			router.Entity:PushData( idx, {
				"sendpacket",
				{ (body[3] or "0.0.0.0"), PCMod.Net.BroadcastIP, 0, body },
				nil,
				{ SourceMAC = mac, DestMAC = PCMod.MAC.BROADCAST },
			} )
		end
	end
end

function PCMod.Routing.Handle( router, port, body, macs )
	if (!PCMod.Net.IsHello( body )) then return false end
	local bb = body[2]
	local ip = body[3]
	local mac = body[4] or (macs && macs.SourceMAC)
	local dv = body[5]
	local prefixes = body[6]
	router.HelloSeen = router.HelloSeen or {}
	if (router:IsBackbone()) then
		router.Neighbors = router.Neighbors or {}
		router.NeighborMAC = router.NeighborMAC or {}
		if ((bb) && (istable( dv )) && (dv[ bb ] != nil)) then
			router.Neighbors[ bb ] = port
			router.NeighborMAC[ bb ] = mac
			router.HelloSeen[ bb ] = CurTime()
			// RecvRoutes stores the advertisement and recalculates routes.
			if (router.RecvRoutes) then router:RecvRoutes( bb, dv ) end
		end
	end
	if (istable( prefixes )) then
		router.PrefixRoutes = router.PrefixRoutes or {}
		local mybb = router.Entity.GetBSubnet && router.Entity:GetBSubnet() or nil
		// A neighbour backbone re-advertising one of our own /64s must not
		// override the LAN router attached to us. A LAN router's own hello has
		// no DV, so only DV-carrying hellos get this protection.
		local fromBackbone = (istable( dv ) && (dv[ bb ] != nil))
		for prefix, flag in pairs( prefixes ) do
			local origin = (istable( flag ) && flag.origin) or bb
			local hops = (((istable( flag ) && tonumber( flag.hops )) or 0) + 1)
			local owned = (fromBackbone && mybb && (origin == mybb))
			if (!owned) then
				local cur = router.PrefixRoutes[ prefix ]
				// Prefer the shortest path; a refresh on the same port is fine.
				if ((!cur) || (hops < (cur.hops or 0)) || (cur.port == port)) then
					router.PrefixRoutes[ prefix ] = {
						port = port,
						mac = mac,
						time = CurTime(),
						via = bb,
						origin = origin,
						hops = hops,
					}
				end
			end
		end
	end
	return true
end

// Drop prefixes whose advertising router has gone quiet.
function PCMod.Routing.Expire( router )
	local timeout = PCMod.Routing.HelloTimeout or 20
	local now = CurTime()
	if (router.PrefixRoutes) then
		for prefix, rec in pairs( router.PrefixRoutes ) do
			if ((now - (rec.time or now)) > timeout) then router.PrefixRoutes[ prefix ] = nil end
		end
	end
	if (router:IsBackbone() && router.Neighbors) then
		for bb, port in pairs( router.Neighbors ) do
			local seen = router.HelloSeen && router.HelloSeen[ bb ]
			if ((!seen) || ((now - seen) > timeout)) then
				router.Neighbors[ bb ] = nil
				if (router.NeighborMAC) then router.NeighborMAC[ bb ] = nil end
				if (router.RouteAdv) then router.RouteAdv[ bb ] = nil end
				if (router.RecalcRoutes) then router:RecalcRoutes() end
			end
		end
	end
end

function PCMod.Routing.PrefixRoute( router, prefix )
	local rec = router.PrefixRoutes && router.PrefixRoutes[ prefix ]
	if (!rec) then return nil end
	if ((CurTime() - (rec.time or 0)) > (PCMod.Routing.HelloTimeout or 20)) then
		router.PrefixRoutes[ prefix ] = nil
		return nil
	end
	return rec
end

function PCMod.Routing.Start( router )
	if (!timer || !timer.Create) then return end
	local ent = router.Entity
	local id = "pcmod_hello_" .. tostring( ent:EntIndex() )
	if (timer.Exists && timer.Exists( id )) then return end
	timer.Create( id, PCMod.Routing.HelloInterval or 5, 0, function()
		if ((!ent) || (!ent:IsValid())) then return end
		PCMod.Routing.Expire( router )
		PCMod.Routing.Send( router, true )
	end )
end

function PCMod.Routing.Stop( router )
	if ((!timer) || (!timer.Remove)) then return end
	timer.Remove( "pcmod_hello_" .. tostring( router.Entity:EntIndex() ) )
end
