// ---------------------------------------------------------------------------------------------------------
// sh_dhcp.lua - DHCP / IPv4 lease mechanics
//
// This is the single place that decides how a device gets an address. A scope
// selects the lease table and pool:
//   "lan" -> router.Leases  + DHCPStart/DHCPEnd        (192.168.x.y)
//   "wan" -> router.BLeases + WanDHCPStart/WanDHCPEnd  (10.x.x.y)
//
// The routines operate on a router object (the webgr_router driver), but all
// allocation and bookkeeping lives here, so the driver only wires ports and
// forwards packets.
// ---------------------------------------------------------------------------------------------------------

PCMod.DHCP = PCMod.DHCP or {}

// Per-scope parameters. The mechanism is shared; each scope names its own
// lease table and pool fields.
PCMod.DHCP.Settings = {
	lan = { table = "Leases", startKey = "DHCPStart", endKey = "DHCPEnd", defaultStart = 2, defaultEnd = 254 },
	wan = { table = "BLeases", startKey = "WanDHCPStart", endKey = "WanDHCPEnd", defaultStart = 12, defaultEnd = 254 },
}

function PCMod.DHCP.Config( scope )
	return PCMod.DHCP.Settings[ scope ] or PCMod.DHCP.Settings.lan
end

// ---------------------------------------------------------------------------------------------------------
// Low-level lease-table helpers. `leases` maps a host id to an entity.
// ---------------------------------------------------------------------------------------------------------

function PCMod.DHCP.FindHost( leases, pc )
	for h, ent in pairs( leases or {} ) do
		if (ent == pc) then return h end
	end
	return nil
end

// Return the host `pc` already holds, or reserve the first free host in
// [start, finish]. `blocked` is an optional set of host ids to skip (static
// reservations).
function PCMod.DHCP.AllocHost( leases, pc, start, finish, blocked )
	local existing = PCMod.DHCP.FindHost( leases, pc )
	if (existing) then return existing end
	for h = start, finish do
		if ((!leases[ h ]) && (!(blocked && blocked[ h ]))) then
			leases[ h ] = pc
			return h
		end
	end
	return nil
end

function PCMod.DHCP.DropHost( leases, pc )
	local h = PCMod.DHCP.FindHost( leases, pc )
	if (h) then leases[ h ] = nil end
	return h
end

// ---------------------------------------------------------------------------------------------------------
// Scoped view: which table and pool a scope uses.
// ---------------------------------------------------------------------------------------------------------

function PCMod.DHCP.Table( router, scope )
	local cfg = PCMod.DHCP.Config( scope )
	if (!router[ cfg.table ]) then router[ cfg.table ] = {} end
	return router[ cfg.table ]
end

// First/last host id and the largest usable host for a scope. The LAN pool is
// clamped to the current subnet; the backbone pool is clamped to its /24
// (hosts 2..11 belong to attached LAN routers).
function PCMod.DHCP.Pool( router, scope )
	local cfg = PCMod.DHCP.Config( scope )
	local c = router:GetCfg()
	local start = math.floor( tonumber( c[ cfg.startKey ] ) or cfg.defaultStart )
	local finish = math.floor( tonumber( c[ cfg.endKey ] ) or cfg.defaultEnd )
	if (scope == "wan") then
		start = math.Clamp( start, 12, 254 )
		finish = math.Clamp( finish, start, 254 )
		return start, finish, 254
	end
	local maxHost = router:LanBlockSize() - 2
	if (maxHost < 2) then return nil end
	if (finish > maxHost) then finish = maxHost end
	return start, finish, maxHost
end

function PCMod.DHCP.LeaseHost( router, scope, pc )
	return PCMod.DHCP.FindHost( PCMod.DHCP.Table( router, scope ), pc )
end

function PCMod.DHCP.AllocLease( router, scope, pc )
	local start, finish = PCMod.DHCP.Pool( router, scope )
	if (!start) then return nil end
	local blocked = nil
	if (scope == "wan") then blocked = PCMod.DHCP.StaticHosts( router ) end
	return PCMod.DHCP.AllocHost( PCMod.DHCP.Table( router, scope ), pc, start, finish, blocked )
end

function PCMod.DHCP.DropLease( router, scope, pc )
	return PCMod.DHCP.DropHost( PCMod.DHCP.Table( router, scope ), pc )
end

function PCMod.DHCP.Has( router, scope, pc )
	return (PCMod.DHCP.LeaseHost( router, scope, pc ) != nil)
end

// ---------------------------------------------------------------------------------------------------------
// Static backbone reservations ("IP <> MAC"). They live in RouterCfg so they
// are saved with the router and editable from the backbone admin page.
// ---------------------------------------------------------------------------------------------------------

function PCMod.DHCP.StaticLeases( router )
	local c = router:GetCfg()
	c.StaticLeases = c.StaticLeases or {}
	return c.StaticLeases
end

function PCMod.DHCP.StaticLeaseForMAC( router, mac )
	local norm = PCMod.MAC.Normalize( mac )
	if (!norm) then return nil end
	for _, l in ipairs( PCMod.DHCP.StaticLeases( router ) ) do
		if (PCMod.MAC.Normalize( l.mac ) == norm) then return l end
	end
	return nil
end

// Hosts reserved by a static lease in this router's /24. The dynamic pool must
// not hand them to another MAC.
function PCMod.DHCP.StaticHosts( router )
	local out = {}
	local bb = router.Entity:GetBSubnet()
	for _, l in ipairs( PCMod.DHCP.StaticLeases( router ) ) do
		local p = PCMod.IPv4.Parse( l.ip )
		if (p && (p.bb == bb)) then out[ p.host ] = true end
	end
	return out
end

// Add or replace a reservation. Returns true, or false plus a reason.
function PCMod.DHCP.AddStaticLease( router, ip, mac )
	if (!router:IsBackbone()) then return false, "Only a backbone router can reserve backbone leases" end
	local bb = router.Entity:GetBSubnet()
	local p = PCMod.IPv4.Parse( string.Trim( tostring( ip or "" ) ) )
	if ((!p) || (p.bb != bb)) then return false, "IP must be inside this backbone's /24" end
	// Host 1 is the gateway and 2..11 belong to attached LAN routers.
	if ((p.host < 12) || (p.host > 254)) then return false, "Reserved host range is 12-254" end
	local norm = PCMod.MAC.Normalize( mac )
	if (!norm) then return false, "Invalid MAC address" end
	local list = PCMod.DHCP.StaticLeases( router )
	local full = PCMod.IPv4.BackboneAddress( bb, p.host )
	// A reservation is unique by MAC and by IP: replace any collision.
	for i = #list, 1, -1 do
		local l = list[ i ]
		if ((PCMod.MAC.Normalize( l.mac ) == norm) || (l.ip == full)) then
			table.remove( list, i )
		end
	end
	list[ #list + 1 ] = { ip = full, mac = norm }
	return true
end

function PCMod.DHCP.DeleteStaticLease( router, idx )
	idx = tonumber( idx )
	local list = PCMod.DHCP.StaticLeases( router )
	if (!idx || (!list[ idx ])) then return false end
	table.remove( list, idx )
	return true
end

// ---------------------------------------------------------------------------------------------------------
// Address application / release.
// ---------------------------------------------------------------------------------------------------------

// Put an already-reserved host onto a device. Returns false when another
// device owns that host.
function PCMod.DHCP.Apply( router, scope, pc, host, port )
	if (!pc) then return false end
	if (scope == "wan") then
		local leases = PCMod.DHCP.Table( router, "wan" )
		local old = PCMod.DHCP.FindHost( leases, pc )
		if (old && (old != host)) then leases[ old ] = nil end
		local holder = leases[ host ]
		if (holder && (holder != pc)) then return false end
		leases[ host ] = pc
		if (!router.BLeasePort) then router.BLeasePort = {} end
		if (port) then router.BLeasePort[ pc:EntIndex() ] = port end
		// A backbone address is the primary IPv4: clear a private LAN lease
		// so it cannot hide behind NAT.
		if (pc.SetLanAddress) then pc:SetLanAddress( false ) end
		if (pc.SetBSubnet) then pc:SetBSubnet( router.Entity:GetBSubnet() ) end
		if (pc.SetBIP) then pc:SetBIP( host - 1 ) end
		return true
	end

	// LAN: host ids are offsets inside the subnet block; the block base
	// supplies the third/fourth octets (192.168.<sub>.<add>).
	local addr = router:GetLanBase() + host
	local sub = math.floor( addr / 256 )
	local add = addr % 256
	local full = "192.168." .. tostring( sub ) .. "." .. tostring( add )
	local ipdata = pc.Data && pc:Data() && pc:Data().IP
	local rip = router.Entity:Data().IP
	if (ipdata && ipdata.Static) then
		// Re-apply the configured LAN address: the device may have just left
		// a backbone segment, where its LAN address was cleared.
		if (pc.SetLanAddress) then pc:SetLanAddress( ipdata.Static ) end
		if (pc.SetUpBB) then pc:SetUpBB( rip.UpBB or 0 ) end
		if (pc.SetLanID) then pc:SetLanID( rip.LanID or 0 ) end
		return true
	end
	local hasPrimary = ipdata && PCMod.IPv4.ParseLan( ipdata.LAN )
	// Same subnet = same LAN under a (possibly replaced) router: promote the
	// lease instead of stacking a duplicate secondary address on top.
	local sameLan = hasPrimary && PCMod.IPv4.SameLan( ipdata.LAN, full, ipdata.MaskBits or 24 )
	if (hasPrimary && (!sameLan)) then
		// The primary belongs to a genuinely different network: take a
		// secondary address.
		if (pc.AddExtraIP) then
			pc:AddExtraIP( full, rip.UpBB or 0, rip.LanID or 0, router.Entity:EntIndex() )
		else
			// Legacy client without secondary support: reuse the primary slot.
			pc:SetSubnet( sub )
			pc:SetIP( add )
		end
	else
		if (pc.ReleaseExtraIP) then pc:ReleaseExtraIP( full ) end
		// First lease this client holds (or the same LAN came back): it
		// becomes the primary address.
		pc:SetSubnet( sub )
		pc:SetIP( add )
		if (ipdata) then ipdata.Router = router.Entity:EntIndex() end
		if (pc.SetUpBB) then pc:SetUpBB( rip.UpBB or 0 ) end
		if (pc.SetLanID) then pc:SetLanID( rip.LanID or 0 ) end
	end
	return true
end

// Unified lease request. Returns the host id, or nil. The LAN keeps an
// existing lease as-is; the backbone honours a static IP<->MAC reservation.
function PCMod.DHCP.Assign( router, scope, pc, port )
	if ((!pc) || (!pc:IsValid())) then return nil end
	if (scope == "wan") then
		if (!router:IsBackbone()) then return nil end
		local mac = pc.GetMAC && pc:GetMAC()
		local static = PCMod.DHCP.StaticLeaseForMAC( router, mac )
		if (static) then
			local p = PCMod.IPv4.Parse( static.ip )
			if (p && (p.bb == router.Entity:GetBSubnet())) then
				if (PCMod.DHCP.Apply( router, "wan", pc, p.host, port )) then return p.host end
			end
		end
	else
		// Already leased by us (reconnect, or Wi-Fi sharing a wired lease):
		// keep the address it has instead of re-applying it as a secondary.
		local existing = PCMod.DHCP.LeaseHost( router, "lan", pc )
		if (existing) then return existing end
	end
	local host = PCMod.DHCP.AllocLease( router, scope, pc )
	if (!host) then return nil end
	if (!PCMod.DHCP.Apply( router, scope, pc, host, port )) then
		PCMod.DHCP.DropLease( router, scope, pc )
		return nil
	end
	return host
end

// Unified lease release. LAN releases distinguish a primary this router owns
// from a secondary handed out for another network.
function PCMod.DHCP.Release( router, scope, pc, mask, net, low )
	if (!pc) then return end
	if (scope == "wan") then
		local host = PCMod.DHCP.DropLease( router, "wan", pc )
		if (!host) then return end
		if (router.BLeasePort) then router.BLeasePort[ pc:EntIndex() ] = nil end
		if (pc.GetBSubnet && (pc:GetBSubnet() == router.Entity:GetBSubnet())) then
			if (pc.SetBSubnet) then pc:SetBSubnet( false ) end
			if (pc.SetBIP) then pc:SetBIP( false ) end
		end
		return host
	end

	local host = PCMod.DHCP.LeaseHost( router, "lan", pc )
	if (!host) then return end
	PCMod.DHCP.DropLease( router, "lan", pc )
	// The decomposition used to issue the lease. Callers that just changed
	// the addressing pass the OLD values so this still finds the address.
	local base = router:ComputeLanBase( mask, net, low )
	local addr = base + host
	local sub = math.floor( addr / 256 )
	local add = addr % 256
	// Whose address was this lease? When we assigned the client's primary,
	// take it away; otherwise drop only the secondary we handed out (the
	// primary belongs to another router).
	local ipdata = pc.Data && pc:Data() && pc:Data().IP
	local mine = false
	if (ipdata) then
		if (ipdata.Static) then
			// Never take away a manually configured address.
			mine = false
		elseif (ipdata.Router == router.Entity:EntIndex()) then
			mine = true
		elseif ((ipdata.Router == nil) || (ipdata.Router == false)) then
			// No lease owner recorded: fall back to an address match.
			mine = (ipdata.LAN == ("192.168." .. tostring( sub ) .. "." .. tostring( add )))
		end
	end
	if (mine) then
		pc:SetSubnet( false )
		pc:SetIP( false )
		if (ipdata) then ipdata.Router = false end
	elseif (pc.ReleaseExtraIP) then
		pc:ReleaseExtraIP( "192.168." .. tostring( sub ) .. "." .. tostring( add ) )
	else
		pc:SetSubnet( false )
		pc:SetIP( false )
	end
	return host
end

function PCMod.DHCP.Renew( router, scope, pc )
	if ((!pc) || (!pc:IsValid())) then return nil end
	if (!PCMod.DHCP.LeaseHost( router, scope, pc )) then return PCMod.DHCP.Assign( router, scope, pc ) end
	PCMod.DHCP.Release( router, scope, pc )
	return PCMod.DHCP.Assign( router, scope, pc )
end

// Drop every lease on a port (its modem/switch was unplugged).
function PCMod.DHCP.ReleaseOnPort( router, scope, port )
	if (!port) then return end
	local gone = {}
	for _, pc in pairs( PCMod.DHCP.Table( router, scope ) ) do
		if (router.BLeasePort && (router.BLeasePort[ pc:EntIndex() ] == port)) then
			gone[ #gone + 1 ] = pc
		end
	end
	for _, pc in ipairs( gone ) do PCMod.DHCP.Release( router, scope, pc ) end
end

// First and last address of a pool in dotted-quad form.
function PCMod.DHCP.PoolRange( router, scope )
	local start, finish = PCMod.DHCP.Pool( router, scope )
	if (!start) then return nil end
	if (scope == "wan") then
		local bb = router.Entity:GetBSubnet()
		return PCMod.IPv4.BackboneAddress( bb, start ), PCMod.IPv4.BackboneAddress( bb, finish )
	end
	local base = router:GetLanBase()
	local function addr( off )
		return "192.168." .. tostring( math.floor( off / 256 ) ) .. "." .. tostring( off % 256 )
	end
	return addr( base + start ), addr( base + finish )
end
