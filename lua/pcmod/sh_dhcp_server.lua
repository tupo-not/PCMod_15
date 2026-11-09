// ---------------------------------------------------------------------------------------------------------
// sh_dhcp_server.lua - MAC-keyed DHCP lease engine (DORA server side)
//
// A router is just an address authority here: it hands out addresses from the
// pool that belongs to the interface the discover arrived on. It never scans
// ports or holds entity references. Leases are keyed by MAC and stored in the
// router config so the web page and map saves keep them.
// ---------------------------------------------------------------------------------------------------------

PCMod = PCMod or {}
PCMod.DHCPServer = PCMod.DHCPServer or {}

local LeaseTime = function() return PCMod.Net.LeaseTime or 3600 end
local OfferTime = function() return PCMod.Net.LeaseOfferTime or 30 end

function PCMod.DHCPServer.Cfg( router )
	local c = router:GetCfg()
	if (!istable( c.Leases )) then c.Leases = {} end
	if (!istable( c.LanStaticLeases )) then c.LanStaticLeases = {} end
	if (!istable( c.MgmtStaticLeases )) then c.MgmtStaticLeases = {} end
	if (!istable( c.StaticLeases )) then c.StaticLeases = {} end
	return c
end

function PCMod.DHCPServer.ScopeForSide( router, side )
	if (side == "wan") then
		if (router:IsBackbone()) then return "wan" end
		return nil
	end
	// A LAN router serves its private LAN; a backbone's LAN-side port is its
	// MGMNT port, which serves .2-.11 of the backbone's own /24.
	if (router:IsBackbone()) then return "mgmt" end
	if (PCMod.IsLanRouterClass && PCMod.IsLanRouterClass( router.Entity:GetClass() )) then return "lan" end
	return nil
end

function PCMod.DHCPServer.StaticList( router, scope )
	local c = PCMod.DHCPServer.Cfg( router )
	if (scope == "wan") then return c.StaticLeases end
	if (scope == "mgmt") then return c.MgmtStaticLeases end
	return c.LanStaticLeases
end

function PCMod.DHCPServer.StaticHosts( router, scope )
	local out = {}
	for _, l in ipairs( PCMod.DHCPServer.StaticList( router, scope ) or {} ) do
		local host = PCMod.DHCPServer.HostForIP( router, scope, l.ip )
		if (host) then out[ host ] = true end
	end
	return out
end

function PCMod.DHCPServer.StaticForMAC( router, scope, mac )
	mac = PCMod.Net.MACKey( mac )
	if (!mac) then return nil end
	for _, l in ipairs( PCMod.DHCPServer.StaticList( router, scope ) or {} ) do
		if (PCMod.Net.MACKey( l.mac ) == mac) then return l end
	end
	return nil
end

// Address for a host id in this scope. "wan" and "mgmt" both live in the
// backbone's own /24; "lan" is the router's private RFC1918 subnet.
function PCMod.DHCPServer.Address( router, scope, host )
	if ((scope == "wan") || (scope == "mgmt")) then
		local bb = router.Entity:GetBSubnet()
		if (!bb) then return nil end
		return PCMod.IPv4.BackboneAddress( bb, host )
	end
	return PCMod.IPv4.FromInt( router:GetLanBase() + host )
end

// Host id -> dotted address for a lease record.
function PCMod.DHCPServer.HostForIP( router, scope, ip )
	if ((scope == "wan") || (scope == "mgmt")) then
		local p = PCMod.IPv4.Parse( ip )
		if ((!p) || (p.bb != router.Entity:GetBSubnet())) then return nil end
		if ((scope == "mgmt") && ((p.host < 2) || (p.host > 11))) then return nil end
		return p.host
	end
	local value = PCMod.IPv4.ToInt( ip )
	if ((!value) || (!PCMod.IPv4.IsPrivate( value ))) then return nil end
	local base = router:GetLanBase()
	local host = value - base
	local size = (router.LanBlockSize && router:LanBlockSize()) or 65536
	if ((host < 0) || (host >= size)) then return nil end
	return host
end

// First/last host + a blocking set of statically reserved host ids.
function PCMod.DHCPServer.Pool( router, scope )
	local c = PCMod.DHCPServer.Cfg( router )
	local start, finish
	if (scope == "wan") then
		start = math.Clamp( math.floor( tonumber( c.WanDHCPStart ) or 12 ), 12, 254 )
		finish = math.Clamp( math.floor( tonumber( c.WanDHCPEnd ) or 254 ), start, 254 )
	elseif (scope == "mgmt") then
		// The MGMNT port always serves .2-.11 of the backbone /24.
		start = math.Clamp( math.floor( tonumber( c.MgmtDHCPStart ) or 2 ), 2, 11 )
		finish = math.Clamp( math.floor( tonumber( c.MgmtDHCPEnd ) or 11 ), start, 11 )
	else
		start = math.floor( tonumber( c.DHCPStart ) or 2 )
		finish = math.floor( tonumber( c.DHCPEnd ) or 254 )
		local max = (router.PoolMax && router:PoolMax()) or 254
		start = math.Clamp( start, 2, max )
		finish = math.Clamp( finish, start, max )
	end
	return start, finish, PCMod.DHCPServer.StaticHosts( router, scope )
end

function PCMod.DHCPServer.Find( router, scope, mac )
	local c = PCMod.DHCPServer.Cfg( router )
	local rec = c.Leases[ mac ]
	if (!rec) then return nil end
	if (rec.scope != scope) then return nil end
	if ((!rec.static) && (rec.offered != true) && (rec.expires or 0) < PCMod.Net.Now()) then
		c.Leases[ mac ] = nil
		return nil
	end
	return rec
end

function PCMod.DHCPServer.FindHost( router, scope, host )
	local c = PCMod.DHCPServer.Cfg( router )
	for mac, rec in pairs( c.Leases ) do
		if ((rec.scope == scope) && (rec.host == host)) then
			if ((!rec.static) && (rec.offered != true) && ((rec.expires or 0) < PCMod.Net.Now())) then
				c.Leases[ mac ] = nil
			else
				return rec
			end
		end
	end
	return nil
end

function PCMod.DHCPServer.AllocHost( router, scope, mac )
	local start, finish, blocked = PCMod.DHCPServer.Pool( router, scope )
	if (!start) then return nil end
	for h = start, finish do
		if ((!blocked[ h ]) && (!PCMod.DHCPServer.FindHost( router, scope, h ))) then
			// Do not hand out an address something on the segment still uses
			// (a static host, a lease from another DHCP server, or an old
			// client that has not expired yet). ARP is the only authority that
			// works without any topology knowledge.
			local ip = PCMod.DHCPServer.Address( router, scope, h )
			if (ip && (!PCMod.DHCPServer.InUse( router, scope, ip ))) then return h end
		end
	end
	return nil
end

// True when an address already answers ARP on the scope's segment.
function PCMod.DHCPServer.InUse( router, scope, ip )
	if ((!PCMod.ARP) || (!PCMod.ARP.Resolve) || (!router) || (!router.Entity)) then return false end
	local ports = (scope == "wan") and router.OPorts or router.NPorts
	if ((!ports) || (#ports == 0) || (!router.Entity.PushData)) then return false end
	local sip
	if (router.InterfaceIP) then sip = router:InterfaceIP( (scope == "wan") and "wan" or "lan" ) end
	return (PCMod.ARP.Resolve( router, ip, ports, sip ) != nil)
end

function PCMod.DHCPServer.Ensure( router )
	local c = PCMod.DHCPServer.Cfg( router )
	for mac, rec in pairs( c.Leases ) do
		if ((!rec.static) && (rec.offered != true) && ((rec.expires or 0) < PCMod.Net.Now())) then
			c.Leases[ mac ] = nil
		elseif (rec.offered && ((rec.expires or 0) < PCMod.Net.Now())) then
			c.Leases[ mac ] = nil
		end
	end
end

// Acquire the record for a MAC: reuse the live one, honour a static
// reservation, or allocate the next free host. Shared by the DORA offer and
// the internal synchronous lease.
function PCMod.DHCPServer.Acquire( router, scope, mac, port )
	PCMod.DHCPServer.Ensure( router )
	local c = PCMod.DHCPServer.Cfg( router )
	local rec = c.Leases[ mac ]
	if ((rec) && (rec.scope == scope)) then
		if (port ~= nil) then
			rec.port = port
			if ((port != 0) && (scope ~= "wan")) then rec.wired = true end
		end
		return rec
	end
	local static = PCMod.DHCPServer.StaticForMAC( router, scope, mac )
	local host = static && PCMod.DHCPServer.HostForIP( router, scope, static.ip )
	if ((!host) && static) then return nil end
	if (!host) then host = PCMod.DHCPServer.AllocHost( router, scope, mac ) end
	if (!host) then return nil end
	local ip = PCMod.DHCPServer.Address( router, scope, host )
	if (!ip) then return nil end
	local ipd = router.Entity:Data().IP or {}
	rec = {
		mac = mac, scope = scope, host = host, ip = ip,
		bb = router.Entity:GetBSubnet(),
		upbb = (ipd.UpBB or 0),
		lanid = (ipd.LanID or 0),
		expires = 0,
		offered = false, static = (static != nil),
		port = port,
		wired = ((scope ~= "wan") && port && (port != 0)) or false,
	}
	c.Leases[ mac ] = rec
	return rec
end

// Handle a discover: reserve an offer and return its record. `port` is the
// ingress port (0 = Wi-Fi), recorded so lease handling can tell a wired link
// from an association without scanning the topology.
function PCMod.DHCPServer.Offer( router, side, mac, xid, port )
	mac = PCMod.Net.MACKey( mac )
	if ((!mac) || (!xid)) then return nil end
	local scope = PCMod.DHCPServer.ScopeForSide( router, side )
	if (!scope) then return nil end
	local rec = PCMod.DHCPServer.Acquire( router, scope, mac, port )
	if (!rec) then return nil end
	rec.xid = xid
	rec.offered = true
	rec.expires = PCMod.Net.Now() + OfferTime()
	return rec
end

// Synchronous lease for internal callers (renumbering, control panel): no
// DORA round trip, but the same allocator, reservations and expiry.
function PCMod.DHCPServer.Lease( router, scope, mac, port )
	mac = PCMod.Net.MACKey( mac )
	if (!mac) then return nil end
	if (((scope == "wan") || (scope == "mgmt")) && (!router:IsBackbone())) then return nil end
	local rec = PCMod.DHCPServer.Acquire( router, scope, mac, port )
	if (!rec) then return nil end
	rec.offered = false
	rec.expires = PCMod.Net.Now() + LeaseTime()
	return rec
end

// Confirm an offer (request) and extend the lease.
function PCMod.DHCPServer.Ack( router, mac, xid, server )
	mac = PCMod.Net.MACKey( mac )
	PCMod.DHCPServer.Ensure( router )
	local rec = mac && PCMod.DHCPServer.Cfg( router ).Leases[ mac ]
	if ((!rec) || (rec.xid != xid)) then return nil end
	if ((server) && (tonumber( server ) != router.Entity:EntIndex())) then return nil end
	rec.offered = false
	rec.expires = PCMod.Net.Now() + LeaseTime()
	return rec
end

function PCMod.DHCPServer.Release( router, mac )
	mac = PCMod.Net.MACKey( mac )
	if (!mac) then return false end
	local c = PCMod.DHCPServer.Cfg( router )
	if (!c.Leases[ mac ]) then return false end
	c.Leases[ mac ] = nil
	return true
end

// Recompute every record's address after the LAN network moved. Addresses are
// derived from the host id, so only the cached ip needs to change.
function PCMod.DHCPServer.Readdress( router, scope )
	local c = PCMod.DHCPServer.Cfg( router )
	for _, rec in pairs( c.Leases ) do
		if (rec.scope == scope) then
			local ip = PCMod.DHCPServer.Address( router, scope, rec.host )
			if (ip) then rec.ip = ip end
			if (scope == "wan") then rec.bb = router.Entity:GetBSubnet() end
		end
	end
end

// Drop or move leases that no longer fit the pool after it shrank. Returns the
// records that had to be dropped so the caller can clear their devices.
function PCMod.DHCPServer.Reflow( router, scope )
	local c = PCMod.DHCPServer.Cfg( router )
	local start, finish, blocked = PCMod.DHCPServer.Pool( router, scope )
	if (!start) then return {} end
	local move = {}
	for mac, rec in pairs( c.Leases ) do
		if ((rec.scope == scope) && (!rec.static) && ((rec.host < start) || (rec.host > finish))) then
			move[ #move + 1 ] = mac
		end
	end
	table.sort( move )
	local dropped = {}
	for _, mac in ipairs( move ) do
		local rec = c.Leases[ mac ]
		c.Leases[ mac ] = nil
		local host
		for h = start, finish do
			if ((!blocked[ h ]) && (!PCMod.DHCPServer.FindHost( router, scope, h ))) then
				host = h
				break
			end
		end
		if (host) then
			rec.host = host
			rec.ip = PCMod.DHCPServer.Address( router, scope, host )
			c.Leases[ mac ] = rec
		else
			dropped[ #dropped + 1 ] = { mac = mac, rec = rec }
		end
	end
	return dropped
end

// Drop every lease that arrived on a port (its modem/switch was unplugged).
function PCMod.DHCPServer.ReleasePort( router, scope, port )
	if (!port) then return end
	local c = PCMod.DHCPServer.Cfg( router )
	local gone = {}
	for mac, rec in pairs( c.Leases ) do
		if ((rec.scope == scope) && (rec.port == port)) then gone[ #gone + 1 ] = mac end
	end
	for _, mac in ipairs( gone ) do c.Leases[ mac ] = nil end
end

// The configuration table carried in offer/ack. Every client receives the
// whole context; hosts use the address, routers additionally use upbb/lanid
// for their LAN /64. DHCP never asks what kind of device it is.
function PCMod.DHCPServer.Config( router, rec )
	if (!rec) then return nil end
	local ipdata = router.Entity:Data().IP or {}
	local cfg = {
		scope = rec.scope,
		ip = rec.ip,
		server = router.Entity:EntIndex(),
		// The client checks this so a broadcast offer meant for another
		// station can never be applied to the wrong machine.
		mac = rec.mac,
	}
	if ((rec.scope == "wan") || (rec.scope == "mgmt")) then
		cfg.bb = rec.bb or router.Entity:GetBSubnet()
		cfg.host = rec.host
		cfg.upbb = cfg.bb
		cfg.lanid = rec.host
		cfg.gateway = router.Entity.GetFullBIP && router.Entity:GetFullBIP() or nil
		cfg.netmask = "255.255.255.0"
		cfg.maskbits = 24
	else
		cfg.upbb = ipdata.UpBB or 0
		cfg.lanid = ipdata.LanID or 0
		cfg.gateway = router.Entity.GetFullIP && router.Entity:GetFullIP() or nil
		cfg.maskbits = router.GetLanNetmask && router:GetLanNetmask() or 24
		cfg.netmask = (PCMod.IPv4.BitsToMask && PCMod.IPv4.BitsToMask( cfg.maskbits )) or "255.255.255.0"
	end
	return cfg
end

function PCMod.DHCPServer.List( router, scope )
	PCMod.DHCPServer.Ensure( router )
	local out = {}
	local c = PCMod.DHCPServer.Cfg( router )
	for mac, rec in pairs( c.Leases ) do
		if ((!scope) || (rec.scope == scope)) then out[ #out + 1 ] = rec end
	end
	table.sort( out, function( a, b ) return tostring( a.ip ) < tostring( b.ip ) end )
	return out
end

function PCMod.DHCPServer.AddStatic( router, scope, ip, mac )
	mac = PCMod.Net.MACKey( mac )
	if (!mac) then return false, "Invalid MAC address" end
	ip = string.Trim( tostring( ip or "" ) )
	local host, full
	if ((scope == "wan") || (scope == "mgmt")) then
		if (!router:IsBackbone()) then return false, "Only a backbone router can reserve backbone leases" end
		local p = PCMod.IPv4.Parse( ip )
		if ((!p) || (p.bb != router.Entity:GetBSubnet())) then return false, "IP must be inside this backbone's /24" end
		local lo, hi = 12, 254
		if (scope == "mgmt") then lo, hi = 2, 11 end
		if ((p.host < lo) || (p.host > hi)) then return false, "Reserved host range is " .. tostring( lo ) .. "-" .. tostring( hi ) end
		host = p.host
		full = PCMod.IPv4.BackboneAddress( p.bb, p.host )
	else
		local p = PCMod.IPv4.ParseLan( ip )
		if (!p) then return false, "IP must be an RFC1918 LAN address" end
		local base = router:GetLanBase()
		host = p.value - base
		local size = (router.LanBlockSize && router:LanBlockSize()) or 65536
		if ((host < 0) || (host >= size)) then return false, "IP must be inside this router's LAN" end
		if ((host < 2) || (host > router:PoolMax())) then return false, "Reserved host range is 2..pool end" end
		full = p.full
	end
	local list = PCMod.DHCPServer.StaticList( router, scope )
	for i = #list, 1, -1 do
		local l = list[ i ]
		if ((PCMod.Net.MACKey( l.mac ) == mac) || (l.ip == full)) then table.remove( list, i ) end
	end
	list[ #list + 1 ] = { ip = full, mac = mac }
	return true
end

function PCMod.DHCPServer.DeleteStatic( router, scope, idx )
	idx = tonumber( idx )
	local list = PCMod.DHCPServer.StaticList( router, scope )
	if ((!idx) || (!list[ idx ])) then return false end
	table.remove( list, idx )
	return true
end
