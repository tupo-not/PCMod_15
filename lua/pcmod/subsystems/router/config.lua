// ---------------------------------------------------------------------------------------------------------
// router/config.lua - Per-router configuration, Wi-Fi state and firewall helpers.
// Included by subsystems/router.lua; all functions extend SUBSYSTEM.
// ---------------------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Router configuration (editable from the web page). Stored per-router in the
// entity data, seeded from cfg defaults / setup data on first read.
// ---------------------------------------------------------------------------
function SUBSYSTEM:GetCfg()
	local d = self.Entity:Data()
	d.RouterCfg = d.RouterCfg or {}
	local c = d.RouterCfg
	if (c.Wireless == nil) then c.Wireless = (self.Wireless == true) end
	if (c.WirePass == nil) then c.WirePass = d.WirePass or "123" end
	if (c.WireName == nil) then
		// Stable default SSID. Users can rename the network from the Wi-Fi page.
		local idx = (self.Entity.EntIndex && self.Entity:EntIndex()) or 0
		c.WireName = d.WireName or ("WebGear-" .. tostring( idx ))
	end
	if (c.DHCPStart == nil) then c.DHCPStart = tonumber( PCMod.Cfg.DHCPStart ) or 2 end
	if (c.DHCPEnd == nil) then c.DHCPEnd = tonumber( PCMod.Cfg.DHCPEnd ) or 254 end
	// MGMNT segment on a backbone: hosts .2-.11 of the backbone's own /24.
	if (c.MgmtDHCPStart == nil) then c.MgmtDHCPStart = 2 end
	if (c.MgmtDHCPEnd == nil) then c.MgmtDHCPEnd = 11 end
	if (c.MgmtStaticLeases == nil) then c.MgmtStaticLeases = {} end
	// Default backbone rule: the web panel is management-only; the fibre DHCP
	// pool (hosts 12-254) cannot reach it. Set to false to open it up.
	if (c.WebGuard == nil) then c.WebGuard = true end
	// Backbone-side pool (hosts 12..254; .2-.11 belong to the MGMNT port).
	if (c.WanDHCPStart == nil) then c.WanDHCPStart = 12 end
	if (c.WanDHCPEnd == nil) then c.WanDHCPEnd = 254 end
	// Static backbone reservations, each { ip = "<octet>.x.x.y", mac = "AA:..." }.
	if (c.StaticLeases == nil) then c.StaticLeases = {} end
	// Per-router LAN size (16-32) and full 32-bit base. Older saves stored only
	// the 192.168 third/fourth octets (LanNet/LanLow); migrate them into
	// LanBase once, then keep both forms in sync for displays and old tools.
	if (c.LanNetmask == nil) then c.LanNetmask = tonumber( PCMod.Cfg.LanNetmask ) or 24 end
	c.LanNetmask = math.Clamp( math.floor( tonumber( c.LanNetmask ) or 24 ), 16, 32 )
	if (c.LanBase == nil) then
		local net = math.Clamp( math.floor( tonumber( c.LanNet ) or 0 ), 0, 255 )
		local low = math.Clamp( math.floor( tonumber( c.LanLow ) or 0 ), 0, 255 )
		c.LanBase = (192 * 16777216) + (168 * 65536) + (net * 256) + low
	end
	c.LanBase = math.max( 0, math.floor( tonumber( c.LanBase ) or 0 ) )
	if (c.LanNet == nil) then c.LanNet = math.floor( c.LanBase / 256 ) % 256 end
	if (c.LanLow == nil) then c.LanLow = c.LanBase % 256 end
	if (c.Firewall == nil) then c.Firewall = false end
	if (c.NAT == nil) then c.NAT = true end
	if (c.Forwards == nil) then c.Forwards = {} end
	if (c.FirewallRules == nil) then c.FirewallRules = {} end
	return c
end

function SUBSYSTEM:SetWireless( on )
	on = (on == true)
	self.Wireless = on
	local d = self.Entity:Data()
	d.IsWireless = on
	local c = self:GetCfg()
	c.Wireless = on
	if (self.Entity.SetGVar) then self.Entity:SetGVar( "wireless", on ) end
	self:SyncWirelessOverlay()
end

// Publish the look-at overlay state. The overlay is client-side, so the SSID
// travels as a network string: non-empty means Wi-Fi is on. This is what makes
// the overlay follow the web panel instead of the spawn-time checkbox.
function SUBSYSTEM:SyncWirelessOverlay()
	local ent = self.Entity
	if ((!ent) || (!ent.SetNWString)) then return end
	local c = self:GetCfg()
	self.Wireless = (c.Wireless == true)
	local ssid = ""
	if (self.Wireless) then ssid = tostring( c.WireName or "" ) end
	ent:SetNWString( "WifiSSID", ssid )
	if (ent.SetGVar) then ent:SetGVar( "wireless", self.Wireless ) end
end

// Rules-based firewall (allow-list). When enabled (default deny) everything is
// dropped except the router's control plane (web 80 / ping 0), an established
// NAT reply, and traffic matching an allow rule (direction + optional
// source/dest IP + optional port). This is the classic "protect the LAN" model:
// to expose a service behind the router you open it with an allow rule (or a
// port-forward rule, which the firewall also gates).
function SUBSYSTEM:FirewallBlocks( packet, side )
	local c = self:GetCfg()
	if (!c.Firewall) then return false end
	local dir = (side == "wan") and "in" or "out"
	// Control plane always reachable (else the config UI dies).
	if ((packet.Port == 0) || (packet.Port == 80)) then return false end
	// An established NAT reply flows back automatically (stateful pass).
	if (self:GetForwardFlow( packet.Port )) then return false end
	if (self:GetNatOut( packet.Port )) then return false end
	for _, r in ipairs( c.FirewallRules or {} ) do
		if ((r.dir == dir) || (r.dir == "any")) then
			local m = true
			if ((r.src != "") && (r.src != packet.Source)) then m = false end
			if ((r.dst != "") && (r.dst != packet.Dest)) then m = false end
			if ((r.port != 0) && (r.port != packet.Port)) then m = false end
			if (m) then return false end
		end
	end
	// Default deny.
	return true
end

// IPv6 has no NAT, so the LAN edge needs its own stateful boundary. A packet
// arriving from the WAN may only reach an address inside this router's LAN
// /64 when it belongs to a flow the LAN started, or when an inbound firewall
// rule explicitly opens it. This mirrors IPv4's "LAN is private" behaviour and
// keeps freshly spawned routers closed by default.
function SUBSYSTEM:IsLanIPv6( addr )
	local lp = self:GetIPv6Prefix()
	if (!lp) then return false end
	return PCMod.IPv6.InSubnet( addr, lp )
end

// Is addr one of this router's private LAN identities (its gateway IPv4/IPv6)?
// On the WAN side these must not be treated as local addresses; otherwise a
// shared L2 segment could reach the LAN admin interface by its private IP.
function SUBSYSTEM:IsLanSelfAddress( addr )
	local v4 = self.Entity.GetLanIPv4 && self.Entity:GetLanIPv4()
	local v6 = self.Entity.GetIPv6 && self.Entity:GetIPv6()
	return PCMod.IPv6.Matches( addr, v4, v6 )
end

function SUBSYSTEM:RememberV6Flow( packet )
	if ((!packet) || (!packet.Source) || (!packet.Dest)) then return end
	self.V6Flows = self.V6Flows or {}
	local key = tostring( packet.Source ) .. "|" .. tostring( packet.Dest ) .. "|" .. tostring( packet.Port or 0 )
	self.V6Flows[ key ] = {
		localAddr = packet.Source,
		remote = packet.Dest,
		port = packet.Port or 0,
		time = CurTime(),
	}
end

// Is this WAN packet a reply to a flow the LAN started? Traceroute hop reports
// come from routers along the path rather than the final destination, so a
// port-0 trace flow also accepts netTraceHop replies.
function SUBSYSTEM:V6ReplyAllowed( packet )
	self.V6Flows = self.V6Flows or {}
	local now = CurTime()
	local port = packet.Port or 0
	for key, flow in pairs( self.V6Flows ) do
		if ((now - (flow.time or now)) > 3600) then
			self.V6Flows[ key ] = nil
		elseif ((flow.localAddr == packet.Dest) && (flow.port == port)) then
			if (flow.remote == packet.Source) then
				// Keep an active conversation alive while it is in use.
				flow.time = now
				return true
			end
			if ((port == 0) && (packet.Body) && (packet.Body[1] == "netTraceHop")) then return true end
		end
	end
	return false
end

// Explicit inbound allow rule. IPv6 has no port-forward/NAT fallback, so these
// rules are honoured for LAN ingress even when the general firewall is off.
function SUBSYSTEM:V6RuleAllowed( packet )
	local c = self:GetCfg()
	for _, r in ipairs( c.FirewallRules or {} ) do
		if ((r.dir == "in") || (r.dir == "any")) then
			local m = true
			if ((r.src != "") && (r.src != packet.Source)) then m = false end
			if ((r.dst != "") && (r.dst != packet.Dest)) then m = false end
			if ((r.port != 0) && (r.port != (packet.Port or 0))) then m = false end
			if (m) then return true end
		end
	end
	return false
end

function SUBSYSTEM:WanToLanAllowed( packet )
	return self:V6ReplyAllowed( packet ) || self:V6RuleAllowed( packet )
end

function SUBSYSTEM:AddFirewallRule( dir, src, dst, port )
	if ((dir != "in") && (dir != "out") && (dir != "any")) then return false end
	src = tostring( src or "" )
	dst = tostring( dst or "" )
	if ((src != "") && (!PCMod.IPv6.IsIP( src ))) then return false end
	if ((dst != "") && (!PCMod.IPv6.IsIP( dst ))) then return false end
	local p = tonumber( port ) or 0
	if (p < 0) then p = 0 end
	local c = self:GetCfg()
	c.FirewallRules = c.FirewallRules or {}
	table.insert( c.FirewallRules, { dir = dir, src = src, dst = dst, port = p } )
	return true
end

function SUBSYSTEM:DeleteFirewallRule( idx )
	local c = self:GetCfg()
	c.FirewallRules = c.FirewallRules or {}
	table.remove( c.FirewallRules, idx )
end

function SUBSYSTEM:ApplyWebQuery( path )
	path = tostring( path or "" )
	local q = string.match( path, "%?(.*)$" )
	if (!q) then return end
	local parsed = {}
	for _, pair in ipairs( string.Explode( "&", q ) ) do
		local k, v = string.match( pair, "^(.-)=(.*)$" )
		if (k) then parsed[ k ] = v end
	end
	// Port-forwarding rules are multi-field; handle atomically before the
	// generic single-key settings.
	if (parsed.delpf) then self:DeleteForward( parsed.delpf ) end
	if (parsed.pfwan && parsed.pfip && parsed.pfport) then
		self:AddForward( parsed.pfwan, parsed.pfip, parsed.pfport )
	end
	if (parsed.delfw) then self:DeleteFirewallRule( tonumber( parsed.delfw ) ) end
	if (parsed.fwdir) then
		self:AddFirewallRule( parsed.fwdir, parsed.fwsrc or "", parsed.fwdst or "", parsed.fwport or "" )
	end
	if (parsed.dellease) then self:DeleteStaticLease( parsed.dellease ) end
	if (parsed.sip && parsed.smac) then
		self:AddStaticLease( parsed.sip, parsed.smac )
	end
	// Apply single-key settings in a fixed order: the network and mask first,
	// then the pool that is clamped against it. pairs() order is not
	// deterministic, which would make multi-key queries flaky.
	local order = { "wireless", "netmask", "lanaddr", "lannet", "dhcpstart", "dhcpend", "firewall", "nat", "wname", "wpass" }
	// When the first pool bound is a bare host id, a dotted last bound is the
	// one that names the network, so let it derive the subnet.
	local startDotted = parsed.dhcpstart && (string.find( parsed.dhcpstart, "%." ) != nil)
	for _, k in ipairs( order ) do
		if (parsed[ k ] != nil) then
			local derive = (k == "dhcpend") && (!startDotted)
			self:ApplyWebSetting( k, parsed[ k ], derive )
		end
	end
end

// Port forwarding (DNAT): wanPort -> lanIP:lanPort. A matching inbound packet
