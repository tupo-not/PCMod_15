// ---------------------------------------------------------------------------------------------------------
// sh_arp.lua - ARP cache and next-hop resolution
//
// Routers no longer scan ports to find devices. They resolve a destination by
// broadcasting an ARP request on the relevant interface and caching the MAC
// that answers. Switches forward these frames like any other.
// ---------------------------------------------------------------------------------------------------------

PCMod = PCMod or {}
PCMod.ARP = PCMod.ARP or {}

function PCMod.ARP.Table( router )
	router.ArpCache = router.ArpCache or {}
	return router.ArpCache
end

function PCMod.ARP.Learn( router, ip, mac, port )
	ip = tostring( ip or "" )
	mac = PCMod.Net.MACKey( mac )
	if ((ip == "") || (!mac)) then return nil end
	local cache = PCMod.ARP.Table( router )
	local rec = { ip = ip, mac = mac, port = port, time = CurTime() }
	cache[ ip ] = rec
	return rec
end

function PCMod.ARP.Lookup( router, ip )
	local rec = PCMod.ARP.Table( router )[ tostring( ip or "" ) ]
	if (!rec) then return nil end
	local ttl = PCMod.Net.ArpTime or 60
	if ((CurTime() - (rec.time or 0)) > ttl) then
		PCMod.ARP.Table( router )[ tostring( ip ) ] = nil
		return nil
	end
	return rec
end

function PCMod.ARP.MACFor( router, ip )
	local rec = PCMod.ARP.Lookup( router, ip )
	return rec && rec.mac or nil
end

// Broadcast a request on every candidate port, then look the address up. The
// simulation is synchronous, so a reply usually lands before this returns.
function PCMod.ARP.Resolve( router, ip, ports, sourceIP )
	local rec = PCMod.ARP.Lookup( router, ip )
	if (rec) then return rec end
	if ((!ports) || (#ports == 0)) then return nil end
	local mac = router.Entity:GetMAC()
	local body = PCMod.Net.ARPRequest( ip, sourceIP or "0.0.0.0", mac )
	for _, idx in ipairs( ports ) do
		router.Entity:PushData( idx, {
			"sendpacket",
			{ sourceIP or "0.0.0.0", ip, 0, body },
			nil,
			{ SourceMAC = mac, DestMAC = PCMod.MAC.BROADCAST },
		} )
	end
	return PCMod.ARP.Lookup( router, ip )
end

// Handle an ARP frame received on `port`. Returns true when consumed.
function PCMod.ARP.Handle( router, port, body, macs )
	if (!PCMod.Net.IsARP( body )) then return false end
	local kind = body[2]
	local target = body[3]
	if (kind == "request") then
		if (!router.Entity.IsAddressedTo || !router.Entity:IsAddressedTo( target )) then return true end
		local myip = router.Entity:GetSourceAddress( target ) or router.Entity:GetFullIP() or router.Entity:GetFullBIP()
		if (!myip) then return true end
		local reply = {
			"sendpacket",
			{ myip, body[4] or "0.0.0.0", 0, PCMod.Net.ARPReply( target, myip, router.Entity:GetMAC() ) },
			nil,
			{ SourceMAC = router.Entity:GetMAC(), DestMAC = (macs && macs.SourceMAC) or PCMod.MAC.BROADCAST },
		}
		router.Entity:PushData( port, reply )
		return true
	end
	if (kind == "reply") then
		PCMod.ARP.Learn( router, target, body[5] or (macs && macs.SourceMAC), port )
		return true
	end
	return true
end
