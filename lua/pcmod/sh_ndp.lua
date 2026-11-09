// ---------------------------------------------------------------------------------------------------------
// sh_ndp.lua - IPv6 neighbor discovery
//
// IPv6 delivery needs the peer's MAC just like IPv4 does, but ARP is IPv4-only.
// This is the IPv6 counterpart: a solicitation carries the address to resolve,
// the owner answers with an advertisement, and routers/hosts cache the result.
// Frames are still broadcast at L2; switches flood them like any other frame.
// ---------------------------------------------------------------------------------------------------------

PCMod = PCMod or {}
PCMod.NDP = PCMod.NDP or {}

function PCMod.NDP.Table( router )
	router.NdpCache = router.NdpCache or {}
	return router.NdpCache
end

function PCMod.NDP.Learn( router, ip, mac, port )
	local key = PCMod.IPv6.Normalize( ip )
	mac = PCMod.Net.MACKey( mac )
	if ((!key) || (key == "") || (!mac)) then return nil end
	local rec = { ip = key, mac = mac, port = port, time = CurTime() }
	PCMod.NDP.Table( router )[ key ] = rec
	return rec
end

function PCMod.NDP.Lookup( router, ip )
	local key = PCMod.IPv6.Normalize( ip )
	if ((!key) || (key == "")) then return nil end
	local cache = PCMod.NDP.Table( router )
	local rec = cache[ key ]
	if (!rec) then return nil end
	local ttl = PCMod.Net.NdpTime or 60
	if ((CurTime() - (rec.time or 0)) > ttl) then
		cache[ key ] = nil
		return nil
	end
	return rec
end

function PCMod.NDP.MACFor( router, ip )
	local rec = PCMod.NDP.Lookup( router, ip )
	return rec && rec.mac or nil
end

// Broadcast a solicitation on every candidate port, then look the address up.
// The simulation is synchronous, so an advertisement usually lands before this
// returns.
function PCMod.NDP.Resolve( router, target, ports, sourceIP )
	local rec = PCMod.NDP.Lookup( router, target )
	if (rec) then return rec end
	if ((!ports) || (#ports == 0)) then return nil end
	local ent = router.Entity
	if ((!ent) || (!ent.PushData) || (!ent.GetMAC)) then return nil end
	local mac = ent:GetMAC()
	local source = sourceIP or "::"
	local body = PCMod.Net.NDPSolicit( target, source, mac )
	for _, idx in ipairs( ports ) do
		ent:PushData( idx, {
			"sendpacket",
			{ source, PCMod.Net.NDPAllNodes or "ff02::1", 0, body },
			nil,
			{ SourceMAC = mac, DestMAC = PCMod.MAC.BROADCAST },
		} )
	end
	return PCMod.NDP.Lookup( router, target )
end

// Handle a solicitation or advertisement received on `port`.
function PCMod.NDP.Handle( router, port, body, macs )
	if (!PCMod.Net.IsNDP( body )) then return false end
	local ent = router.Entity
	if ((!ent) || (!ent.IsAddressedTo)) then return true end
	local kind = body[2]
	local target = body[3]
	if (kind == "solicit") then
		if ((!target) || (!ent:IsAddressedTo( target ))) then return true end
		local myip = (ent.GetSourceAddress && ent:GetSourceAddress( target )) or target
		local reply = {
			"sendpacket",
			{ myip, body[4] or PCMod.Net.NDPAllNodes or "ff02::1", 0, PCMod.Net.NDPAdvertise( target, myip, ent:GetMAC() ) },
			nil,
			{ SourceMAC = ent:GetMAC(), DestMAC = (macs && macs.SourceMAC) or PCMod.MAC.BROADCAST },
		}
		ent:PushData( port, reply )
		return true
	end
	if (kind == "advertise") then
		local mac = body[5] or (macs && macs.SourceMAC)
		PCMod.NDP.Learn( router, target, mac, port )
		return true
	end
	return true
end
