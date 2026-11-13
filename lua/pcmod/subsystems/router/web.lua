// ---------------------------------------------------------------------------------------------------------
// router/web.lua - DHCP pool parsing, web settings and the router web UI.
// Included by subsystems/router.lua; all functions extend SUBSYSTEM.
// ---------------------------------------------------------------------------------------------------------

function SUBSYSTEM:ParsePoolBound( value, deriveBase )
	local v = tostring( value or "" )
	local abs = PCMod.IPv4.ToInt( v )
	if (!abs) then return tonumber( v ), nil end
	local base = self:GetLanBase()
	if (!deriveBase) then
		return abs - base, nil
	end
	local size = self:LanBlockSize()
	local aligned = math.floor( abs / size ) * size
	return abs - aligned, aligned
end

function SUBSYSTEM:ApplyWebSetting( key, value, deriveBase )
	local c = self:GetCfg()
	if (key == "wireless") then
		self:SetWireless( (value == "1") || (value == "on") )
	elseif (key == "wname") then
		local name = string.Trim( tostring( value or "" ) )
		if (name == "") then
			c.WireName = nil
			self:GetCfg()
		else
			c.WireName = name
		end
		self:SyncWirelessOverlay()
	elseif (key == "wpass") then
		if (value == "random") then
			c.WirePass = tostring( math.random( 100000, 999999 ) )
		else
			c.WirePass = tostring( value or "" )
		end
	elseif (key == "netmask") then
		self:SetLanNetmask( value )
	elseif (key == "lanaddr") then
		// Full network address, any RFC1918 block ("10.5.0.0", "172.20.1.0",
		// "192.168.4.0"). The subnet size comes from the netmask field.
		local v = PCMod.IPv4.ToInt( string.Trim( tostring( value or "" ) ) )
		if (v) then self:SetLanBase( v ) end
	elseif (key == "lannet") then
		self:SetLanNet( value )
	elseif (key == "dhcpstart") then
		local host, base = self:ParsePoolBound( value, true )
		if (base != nil) then self:SetLanBase( base ) end
		if (host != nil) then c.DHCPStart = host end
		self:ClampDHCPPool()
	elseif (key == "dhcpend") then
		// The first bound normally chooses the network; a dotted last bound
		// may choose it too when the first one is a bare host id.
		local host, base = self:ParsePoolBound( value, deriveBase == true )
		if (base != nil) then self:SetLanBase( base ) end
		if (host != nil) then c.DHCPEnd = host end
		self:ClampDHCPPool()
	elseif (key == "firewall") then
		c.Firewall = (value == "1") || (value == "on")
	elseif (key == "nat") then
		c.NAT = (value == "1") || (value == "on")
	end
end

// Strip a query string and leading/trailing slashes off a request path to get
// the page id ("" = home, "wifi"/"lan"/"firewall" = sub-pages).
function SUBSYSTEM:WebPage( path )
	path = tostring( path or "" )
	path = string.gsub( path, "%?.*$", "" )
	path = string.gsub( path, "/+", "/" )
	path = string.gsub( path, "^/", "" )
	path = string.gsub( path, "/$", "" )
	return path
end

// Shared navigation bar linking the pages. A backbone has no LAN, Wi-Fi or
// firewall/port-forwarding: it only exposes its management segment and leases.
function SUBSYSTEM:WebNav( current )
	local items
	if (self:IsBackbone()) then
		items = { { "", "Home" }, { "lan", "Management" }, { "static", "DHCP Leases" } }
	else
		items = { { "", "Home" }, { "wifi", "Wi-Fi" }, { "lan", "LAN" }, { "firewall", "Firewall" }, { "static", "DHCP Leases" } }
	end
	local parts = {}
	for _, it in ipairs( items ) do
		table.insert( parts, '<a href="/' .. it[ 1 ] .. '">' .. it[ 2 ] .. '</a>' )
	end
	return "<p>Navigation: " .. table.concat( parts, " | " ) .. "</p>"
end

// First and last address of a DHCP pool in dotted-quad form. The scope picks
// the network (LAN RFC1918 or the configured backbone /8).
function SUBSYSTEM:DHCPPoolRange( scope )
	local start, finish = PCMod.DHCPServer.Pool( self, scope )
	if (!start) then return nil end
	return PCMod.DHCPServer.Address( self, scope, start ), PCMod.DHCPServer.Address( self, scope, finish )
end

function SUBSYSTEM:PoolRange()
	return self:DHCPPoolRange( "lan" )
end

function SUBSYSTEM:PageHome()
	local e = self.Entity
	local c = self:GetCfg()
	local bb = e:GetBSubnet()
	local lines = {}
	table.insert( lines, "<h1>WebGear Router</h1>" )
	table.insert( lines, self:WebNav( "" ) )
	table.insert( lines, "<hr>" )
	table.insert( lines, "<h2>Status</h2>" )
	table.insert( lines, "<p><b>Model:</b> " .. tostring( e:GetClass() ) .. "</p>" )
	if (self:IsBackbone()) then
		table.insert( lines, "<p><b>IPv4 WAN / MGMNT:</b> " .. tostring( e:GetFullBIP() or "unassigned" ) .. " in " .. tostring( PCMod.IPv4.BackbonePrefix( bb ) ) .. "</p>" )
	else
		table.insert( lines, "<p><b>IPv4 LAN:</b> " .. tostring( e:GetFullIP() or "unassigned" ) .. " on " .. self:GetLanPrefix() .. "</p>" )
		local wan = (e.GetFullBIP && e:GetFullBIP())
		if (wan) then table.insert( lines, "<p><b>IPv4 WAN /32 (NAT):</b> " .. tostring( wan ) .. " in " .. tostring( PCMod.IPv4.BackbonePrefix( bb ) ) .. "</p>" ) end
	end
	table.insert( lines, "<p><b>IPv6:</b> " .. tostring( e:GetIPv6() or "unassigned" ) .. "</p>" )
	if (e.GetIPv6Prefix && e:GetIPv6Prefix()) then table.insert( lines, "<p><b>Prefix:</b> " .. tostring( e:GetIPv6Prefix() ) .. "</p>" ) end
	if (bb) then table.insert( lines, "<p><b>Backbone:</b> " .. tostring( PCMod.IPv6.BackbonePrefix( bb ) ) .. "</p>" ) else table.insert( lines, "<p><b>Backbone:</b> none (standalone)</p>" ) end
	if (self:IsBackbone()) then
		// A backbone only has the backbone pool and its management pool. It has
		// no Wi-Fi, firewall or NAT to report.
		local wfirst, wlast = self:DHCPPoolRange( "wan" )
		local ws, wf = self:DHCPPool( "wan" )
		if (wfirst) then
			table.insert( lines, "<p><b>Backbone DHCP pool:</b> " .. wfirst .. " - " .. wlast .. " (" .. tostring( wf - ws + 1 ) .. " hosts)</p>" )
		end
		local mfirst, mlast = self:DHCPPoolRange( "mgmt" )
		local ms, mf = self:DHCPPool( "mgmt" )
		if (mfirst) then
			table.insert( lines, "<p><b>MGMNT DHCP pool:</b> " .. mfirst .. " - " .. mlast .. " (" .. tostring( mf - ms + 1 ) .. " hosts)</p>" )
		end
		table.insert( lines, '<p><b>DHCP leases:</b> ' .. tostring( #self:DynamicLeases() ) .. ' backbone, ' .. tostring( #PCMod.DHCPServer.List( self, "mgmt" ) ) .. ' management <a href="/static">[Manage]</a></p>' )
	else
		table.insert( lines, "<p><b>Wi-Fi:</b> " .. (c.Wireless and "enabled" or "disabled") .. "</p>" )
		table.insert( lines, "<p><b>Firewall:</b> " .. (c.Firewall and "on" or "off") .. "</p>" )
		table.insert( lines, "<p><b>NAT:</b> " .. (c.NAT and "on" or "off") .. "</p>" )
		local first, last = self:DHCPPoolRange( "lan" )
		local startHost, finishHost = self:DHCPPool( "lan" )
		if (first) then
			table.insert( lines, "<p><b>DHCP pool:</b> " .. first .. " - " .. last .. " (" .. tostring( finishHost - startHost + 1 ) .. " hosts)</p>" )
		end
		table.insert( lines, '<p><b>DHCP leases:</b> ' .. tostring( #self:DynamicLeases() ) .. ' active, ' .. tostring( #self:StaticLeases() ) .. ' static <a href="/static">[Manage]</a></p>' )
		local wc = 0
		for _, v in pairs( self.WirelessClients or {} ) do if (v) then wc = wc + 1 end end
		table.insert( lines, "<p><b>Wi-Fi clients:</b> " .. tostring( wc ) .. "</p>" )
	end

	table.insert( lines, "<hr>" )
	table.insert( lines, "<h2>Network</h2>" )
	local links = {}
	if (self:IsBackbone()) then
		for lanid, port in pairs( self.ChildLan or {} ) do
			local child = port && port.ConEnt
			local name = "LAN router #" .. tostring( (child && child:IsValid() && child:EntIndex()) or "?" )
			table.insert( links, '<li><a href="fd00:' .. tostring( bb ) .. ':0:' .. tostring( lanid ) .. '::1">' .. name .. '</a></li>' )
		end
		// Child /64s learned from routing hellos.
		for prefix, rec in pairs( self.PrefixRoutes or {} ) do
			if (rec && rec.port) then
				table.insert( links, '<li>' .. tostring( prefix ) .. ' via port ' .. tostring( rec.port ) .. '</li>' )
			end
		end
		for nbb, port in pairs( self.Neighbors or {} ) do
			table.insert( links, '<li><a href="fd00:' .. tostring( nbb ) .. '::1">Backbone fd00:' .. tostring( nbb ) .. '::/32</a></li>' )
		end
	else
		if (bb) then
			table.insert( links, '<li><a href="fd00:' .. tostring( bb ) .. '::1">Upstream backbone fd00:' .. tostring( bb ) .. '::/32</a></li>' )
		end
	end
	if (#links == 0) then table.insert( links, "<li>No links.</li>" ) end
	table.insert( lines, "<ul>" )
	for _, l in ipairs( links ) do table.insert( lines, l ) end
	table.insert( lines, "</ul>" )

	return table.concat( lines, "\n" )
end

function SUBSYSTEM:PageWifi()
	local c = self:GetCfg()
	local lines = {}
	table.insert( lines, "<h1>Wi-Fi</h1>" )
	table.insert( lines, self:WebNav( "wifi" ) )
	if (c.Wireless) then
		table.insert( lines, '<p><b>Status:</b> enabled <a href="?wireless=0">[Disable]</a></p>' )
	else
		table.insert( lines, '<p><b>Status:</b> disabled <a href="?wireless=1">[Enable]</a></p>' )
	end
	table.insert( lines, '<p><b>Name:</b> <input type="text" name="wname" value="' .. tostring( c.WireName ) .. '"> <input type="submit" value="Set Name"></p>' )
	table.insert( lines, '<p><b>Password:</b> <input type="text" name="wpass" value="' .. tostring( c.WirePass ) .. '"> <input type="submit" value="Set Password"></p>' )
	return table.concat( lines, "\n" )
end

// Backbone management page. The MGMNT port is a separate physical segment but
// shares the backbone's own /24, so the web panel is reached at the router's
// backbone address (.1) and DHCP hands out .2-.11 on that port.
function SUBSYSTEM:PageManagement()
	local bb = self.Entity:GetBSubnet()
	local lines = {}
	table.insert( lines, "<h1>Management</h1>" )
	table.insert( lines, self:WebNav( "lan" ) )
	table.insert( lines, "<p>The MGMNT port is an isolated management segment on the backbone's own /24. This router is host .1 and hands out .2 through .11 over DHCP.</p>" )
	table.insert( lines, "<hr>" )
	table.insert( lines, "<h2>Addressing</h2>" )
	table.insert( lines, "<p><b>Network:</b> " .. tostring( PCMod.IPv4.BackbonePrefix( bb ) ) .. "</p>" )
	table.insert( lines, "<p><b>MGMNT address:</b> " .. tostring( self.Entity:GetFullBIP() or "unassigned" ) .. "</p>" )
	table.insert( lines, "<hr>" )
	table.insert( lines, "<h2>DHCP pool</h2>" )
	local first, last = self:DHCPPoolRange( "mgmt" )
	local s, f = self:DHCPPool( "mgmt" )
	if (first) then
		table.insert( lines, "<p><b>Range:</b> " .. first .. " - " .. last .. " (" .. tostring( f - s + 1 ) .. " hosts)</p>" )
	end
	table.insert( lines, "<p><b>Note:</b> hosts .2-.11 are reserved for the MGMNT port; .12-.254 are handed out on the fibre ports.</p>" )
	table.insert( lines, "<p><b>Web access:</b> management only (MGMNT .2-.11). Backbone pool hosts (.12-.254) are blocked from this panel by default.</p>" )
	return table.concat( lines, "\n" )
end

function SUBSYSTEM:PageLAN()
	local c = self:GetCfg()
	local lines = {}
	table.insert( lines, "<h1>LAN / DHCP</h1>" )
	table.insert( lines, self:WebNav( "lan" ) )
	table.insert( lines, "<hr>" )
	table.insert( lines, "<h2>Addressing</h2>" )
	table.insert( lines, "<p><b>Network:</b> " .. self:GetLanPrefix() .. "</p>" )
	table.insert( lines, '<p><b>LAN address:</b> <input type="text" name="lanaddr" value="' .. PCMod.IPv4.FromInt( self:GetLanBase() ) .. '"> (RFC1918: 10.x, 172.16-31.x or 192.168.x)</p>' )
	table.insert( lines, '<p><b>Netmask size:</b> <input type="text" name="netmask" value="' .. tostring( self:GetLanNetmask() ) .. '"> (16-32)</p>' )
	table.insert( lines, '<p><b>Quick:</b> <a href="?netmask=16">[/16]</a> <a href="?netmask=24">[/24]</a> <a href="?netmask=30">[/30]</a></p>' )
	table.insert( lines, "<hr>" )
	table.insert( lines, "<h2>DHCP pool</h2>" )
	local first, last = self:PoolRange()
	// Bounds are shown as full addresses; typing a different RFC1918 network
	// here also moves the LAN's subnet.
	table.insert( lines, '<p><b>First address:</b> <input type="text" name="dhcpstart" value="' .. first .. '"></p>' )
	table.insert( lines, '<p><b>Last address:</b> <input type="text" name="dhcpend" value="' .. last .. '"></p>' )
	local startHost, finishHost = self:DHCPPool( "lan" )
	local hosts = 0
	if (startHost) then hosts = math.max( 0, finishHost - startHost + 1 ) end
	table.insert( lines, "<p><b>Range:</b> " .. first .. " - " .. last .. " (" .. tostring( hosts ) .. " hosts)</p>" )
	table.insert( lines, "<p><b>Note:</b> host ids run 2-" .. tostring( self:PoolMax() ) .. " (.1 is the router). Type a full RFC1918 address to choose the network.</p>" )
	if (c.NAT) then
		table.insert( lines, '<p><b>NAT:</b> on <a href="?nat=0">[Disable]</a></p>' )
	else
		table.insert( lines, '<p><b>NAT:</b> off <a href="?nat=1">[Enable]</a></p>' )
	end
	table.insert( lines, '<p><input type="submit" value="Apply"></p>' )
	return table.concat( lines, "\n" )
end

// DHCP page: active (dynamic) leases plus static IP <-> MAC reservations.
// The scope follows the router role, so LAN and backbone pages look the same.
function SUBSYSTEM:PageStaticLeases()
	local scope = self:LeaseScope()
	local isWan = (scope == "wan")
	local bb = self.Entity:GetBSubnet()
	local lines = {}
	table.insert( lines, "<h1>" .. (isWan and "Backbone" or "LAN") .. " DHCP leases</h1>" )
	table.insert( lines, self:WebNav( "static" ) )
	table.insert( lines, "<hr>" )

	local dyn = self:DynamicLeases()
	table.insert( lines, "<h2>Active leases</h2>" )
	if (#dyn == 0) then
		table.insert( lines, "<p>No active leases.</p>" )
	else
		for _, rec in ipairs( dyn ) do
			local expires = tonumber( rec.expires ) or 0
			local left = math.max( 0, math.floor( (expires - PCMod.Net.Now()) / 60 ) )
			table.insert( lines, '<p>' .. tostring( rec.ip ) .. ' -> ' .. tostring( rec.mac )
				.. ' <i>' .. tostring( rec.static and "static" or "dynamic" ) .. '</i>'
				.. ' (' .. tostring( left ) .. ' min)</p>' )
		end
	end

	if (isWan) then
		local mgmt = PCMod.DHCPServer.List( self, "mgmt" )
		if (#mgmt > 0) then
			table.insert( lines, "<h2>Management leases (MGMNT)</h2>" )
			for _, rec in ipairs( mgmt ) do
				local expires = tonumber( rec.expires ) or 0
				local left = math.max( 0, math.floor( (expires - PCMod.Net.Now()) / 60 ) )
				table.insert( lines, '<p>' .. tostring( rec.ip ) .. ' -> ' .. tostring( rec.mac )
					.. ' <i>' .. tostring( rec.static and "static" or "dynamic" ) .. '</i>'
					.. ' (' .. tostring( left ) .. ' min)</p>' )
			end
		end
	end

	table.insert( lines, "<hr>" )
	table.insert( lines, "<p>Reserve an IPv4 for a MAC address. The reservation is handed out when that device asks for a lease.</p>" )
	if (isWan) then
		table.insert( lines, "<p><b>Backbone:</b> " .. tostring( PCMod.IPv4.BackbonePrefix( bb ) ) .. " (hosts 12-254)</p>" )
	else
		table.insert( lines, "<p><b>LAN:</b> " .. self:GetLanPrefix() .. " (hosts 2-" .. tostring( self:PoolMax() ) .. ")</p>" )
	end

	local list = self:StaticLeases()
	if (#list == 0) then
		table.insert( lines, "<p>No static leases.</p>" )
	else
		table.insert( lines, "<h2>Reservations</h2>" )
		for i, l in ipairs( list ) do
			table.insert( lines, '<p>' .. tostring( l.ip ) .. ' -> ' .. tostring( l.mac )
				.. ' <a href="?dellease=' .. i .. '">[Delete]</a></p>' )
		end
	end

	table.insert( lines, "<h2>Add / replace</h2>" )
	table.insert( lines, "<form>" )
	table.insert( lines, '<p>IPv4 <input type="text" name="sip" value=""></p>' )
	table.insert( lines, '<p>MAC <input type="text" name="smac" value=""></p>' )
	table.insert( lines, '<p><input type="submit" value="Save Lease"></p>' )
	table.insert( lines, "</form>" )
	return table.concat( lines, "\n" )
end

function SUBSYSTEM:PageFirewall()
	local c = self:GetCfg()
	local lines = {}
	table.insert( lines, "<h1>Firewall & Port Forwarding</h1>" )
	table.insert( lines, self:WebNav( "firewall" ) )

	if (c.Firewall) then
		table.insert( lines, '<p><b>Firewall:</b> on <a href="?firewall=0">[Disable]</a></p>' )
	else
		table.insert( lines, '<p><b>Firewall:</b> off <a href="?firewall=1">[Enable]</a></p>' )
	end
	table.insert( lines, "<p>When on, traffic is blocked by default; add allow rules below (web/ping and NAT replies always pass).</p>" )

	table.insert( lines, "<h2>Allow rules</h2>" )
	local rc = 0
	for i, r in ipairs( c.FirewallRules or {} ) do
		rc = rc + 1
		local desc = tostring( r.dir ) .. " "
		if (r.src ~= "") then desc = desc .. r.src else desc = desc .. "any" end
		desc = desc .. " -> "
		if (r.dst ~= "") then desc = desc .. r.dst else desc = desc .. "any" end
		if (r.port ~= 0) then desc = desc .. ":" .. r.port end
		table.insert( lines, '<p>' .. desc .. ' <a href="?delfw=' .. i .. '">[Delete]</a></p>' )
	end
	if (rc == 0) then table.insert( lines, "<p>No rules (everything except web/ping is blocked).</p>" ) end
	table.insert( lines, "<h3>Add allow rule</h3>" )
	table.insert( lines, "<form>" )
	table.insert( lines, '<p>Direction (in/out) <input type="text" name="fwdir" value=""></p>' )
	table.insert( lines, '<p>Source IP (blank=any) <input type="text" name="fwsrc" value=""></p>' )
	table.insert( lines, '<p>Dest IP (blank=any) <input type="text" name="fwdst" value=""></p>' )
	table.insert( lines, '<p>Port (blank=any) <input type="text" name="fwport" value=""></p>' )
	table.insert( lines, '<p><input type="submit" value="Add Allow Rule"></p>' )
	table.insert( lines, "</form>" )

	table.insert( lines, "<h2>Port Forwarding</h2>" )
	local pc = 0
	for wan, r in pairs( c.Forwards or {} ) do
		pc = pc + 1
		table.insert( lines, '<p>' .. tostring( wan ) .. ' -> ' .. tostring( r.ip ) .. ':' .. tostring( r.port ) .. ' <a href="?delpf=' .. tostring( wan ) .. '">[Delete]</a></p>' )
	end
	if (pc == 0) then table.insert( lines, "<p>No rules.</p>" ) end
	table.insert( lines, "<form>" )
	table.insert( lines, '<p>WAN port <input type="text" name="pfwan" value=""></p>' )
	table.insert( lines, '<p>Local IP <input type="text" name="pfip" value=""></p>' )
	table.insert( lines, '<p>Local port <input type="text" name="pfport" value=""></p>' )
	table.insert( lines, '<p><input type="submit" value="Add Forward"></p>' )
	table.insert( lines, "</form>" )

	return table.concat( lines, "\n" )
end

// A config/status "web page" served to the in-game browser (port 80).
function SUBSYSTEM:GetWebPage( path )
	local page = self:WebPage( path )
	// A backbone has no Wi-Fi or firewall/port-forwarding UI; those paths fall
	// back to the home page instead of exposing controls that do nothing.
	if (self:IsBackbone() && ((page == "wifi") || (page == "firewall"))) then
		return self:PageHome()
	end
	if (page == "wifi") then return self:PageWifi() end
	if (page == "lan") then
		if (self:IsBackbone()) then return self:PageManagement() end
		return self:PageLAN()
	end
	if (page == "firewall") then return self:PageFirewall() end
	if (page == "static") then return self:PageStaticLeases() end
	return self:PageHome()
end

// Reply to an in-game HTTP request: apply any ?query settings, then serve.
function SUBSYSTEM:HandleWebRequest( packet )
	local path = (packet.Body && packet.Body[2]) or ""
	self:ApplyWebQuery( path )
	local page = self:GetWebPage( path )
	// Reply from the exact interface address the client contacted, so a
	// request over the backbone answers from the WAN /32 and one over the
	// MGMNT port answers from the management address.
	local src = packet.Dest
	if ((!src) || (!self.Entity.IsAddressedTo) || (!self.Entity:IsAddressedTo( src ))) then
		src = self.Entity:GetSourceAddress( packet.Source ) or self.Entity:GetFullIP() or self.Entity:GetFullBIP()
	end
	if (!src) then return false end
	packet.Delivered = true
	local pid = PCMod.Network.CreatePacket( src, packet.Source, 80, { "http-response", page }, nil, self.Entity:GetMAC(), packet.SourceMAC )
	if (pid) then self:ProcessPacket( pid ) end
	return true
end
