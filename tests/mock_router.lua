-- Router IPv6 subnet classification tests (plain Lua after translation).
function string.Trim( s )
	return (string.gsub( s, "^%s*(.-)%s*$", "%1" ))
end
function string.Left( s, n ) return string.sub( s, 1, n ) end
function string.Right( s, n ) return string.sub( s, math.max( 1, #s - n + 1 ) ) end
function string.Explode( sep, str )
	local out = {}
	if (str == nil) then return out end
	if (sep == "") then
		for i = 1, #str do table.insert( out, string.sub( str, i, i ) ) end
		return out
	end
	local start = 1
	while true do
		local a, b = string.find( str, sep, start, true )
		if (not a) then
			table.insert( out, string.sub( str, start ) )
			break
		end
		table.insert( out, string.sub( str, start, a - 1 ) )
		start = b + 1
	end
	return out
end
function string.Count( str, char )
	local r = 0
	for i = 1, #str do if (string.sub( str, i, i ) == char) then r = r + 1 end end
	return r
end
function table.Copy( t )
	if (type( t ) ~= "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end
function table.HasValue( t, v )
	for _, x in pairs( t ) do if (x == v) then return true end end
	return false
end

PCMod = {}
PCMod.Msg = function() end
PCMod.Warning = function() end
PCMod.Cfg = { MaxNetworkPid = 500, MaxNetworkPass = 10, WirelessRange = 0 }
PCMod.Network = { Packets = {} }
PCMod.DeriveDriver = function() return {} end
math.Clamp = function( v, a, b ) if (v < a) then return a end if (v > b) then return b end return v end
CurTime = function() return 0 end
function table.Count( t ) local n = 0 for _ in pairs( t ) do n = n + 1 end return n end

dofile( "pcmod_sh_common.lua" )
dofile( "pcmod_drv_router.lua" )

local ent = { LanPrefix = false, BackPrefix = false }
function ent:GetIPv6Prefix() return self.LanPrefix end
function ent:GetBIPv6Prefix() return self.BackPrefix end
function ent:GetIPv6() return false end
function ent:GetBIPv6() return false end
DRV.Entity = ent

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

-- LAN router: owns fd00:3:0:5::/64, part of backbone fd00:3::/32.
ent.LanPrefix = "fd00:3:0:5::/64"
ent.BackPrefix = "fd00:3::/32"
local r = DRV:ClassifyDestination( "fd00:3:0:5::3" )
assertTrue( r.IsIPv6, "own LAN is IPv6" )
assertTrue( r.LAN, "own LAN classified as LAN" )
assertTrue( r.OnLinkLAN, "own LAN is on-link" )
assertTrue( not r.Backbone, "own LAN is not backbone" )
assertEq( r.IPv4, "192.168.5.3", "own LAN translates to IPv4" )

r = DRV:ClassifyDestination( "fd00:3:0:5::99" )
assertTrue( r.OnLinkLAN, "unknown host on own LAN is still on-link (drop)" )

r = DRV:ClassifyDestination( "fd00:3:0:6::3" )
assertTrue( r.Backbone, "sibling LAN is in our backbone /32" )
assertTrue( r.OnLinkBackbone, "sibling LAN is on-link backbone" )
assertEq( r.IPv4, "192.168.6.3", "sibling LAN translates to IPv4" )

r = DRV:ClassifyDestination( "fd00:4:0:5::3" )
assertTrue( not r.LAN, "other backbone /32 is not retrofitted as LAN" )
assertTrue( not r.Backbone, "other backbone /32 is not our backbone" )

r = DRV:ClassifyDestination( "192.168.5.2" )
assertTrue( not r.IsIPv6, "IPv4 target" )
assertTrue( r.LAN, "IPv4 LAN target" )
assertTrue( not r.OnLinkLAN, "IPv4 does not use on-link drop" )

r = DRV:ClassifyDestination( "10.0.3.2" )
assertTrue( r.Backbone, "IPv4 backbone target" )
assertTrue( not r.OnLinkBackbone, "IPv4 backbone is not on-link" )

r = DRV:ClassifyDestination( "192.168.10.5" )
assertTrue( r.LAN, "192.168 with a 10 octet is LAN, not backbone" )
assertTrue( not r.Backbone, "192.168.10.5 is not backbone" )

assertTrue( DRV:HasIPv6Subnet( "fd00:3:0:5::3" ), "HasIPv6Subnet own LAN" )
assertTrue( DRV:HasIPv6Subnet( "fd00:3:0:6::3" ), "HasIPv6Subnet sibling in same /32" )
assertTrue( not DRV:HasIPv6Subnet( "fd00:4:0:5::3" ), "HasIPv6Subnet other backbone" )

-- Backbone router: owns fd00:3::/32, no LAN prefix.
ent.LanPrefix = false
ent.BackPrefix = "fd00:3::/32"
r = DRV:ClassifyDestination( "fd00:3:0:2::1" )
assertTrue( r.Backbone, "own backbone classified as backbone" )
assertTrue( r.OnLinkBackbone, "own backbone is on-link" )

r = DRV:ClassifyDestination( "fd00:4:0:2::1" )
assertTrue( not r.OnLinkBackbone, "other backbone is not on-link" )
assertTrue( not r.LAN, "other backbone is not LAN" )
assertTrue( not r.Backbone, "other backbone is not ours" )

-- Router web page (the HTTP server a future browser will fetch).
function ent:GetClass() return "pcmod_router" end
function ent:GetFullIP() return "192.168.5.1" end
function ent:GetIPv6() return "fd00:3:0:5::1" end
function ent:GetIPv6Prefix() return "fd00:3:0:5::/64" end
function ent:GetBSubnet() return 3 end
function ent:GetSourceAddress() return "192.168.5.1" end
local routData = { WirePass = "abc", IsWireless = true }
function ent:Data() return routData end
PCMod.Cfg.DHCPStart = 2
PCMod.Cfg.DHCPEnd = 250
DRV.Wireless = true
DRV.WirelessClients = { [10] = true, [11] = true }
local page = DRV:GetWebPage( "" )
assertTrue( string.find( page, "<h1>WebGear Router</h1>", 1, true ) ~= nil, "home page has an h1 heading" )
assertTrue( string.find( page, "192.168.5.1", 1, true ) ~= nil, "home page shows IPv4 LAN" )
assertTrue( string.find( page, "fd00:3:0:5::/64", 1, true ) ~= nil, "home page shows IPv6 prefix" )
assertTrue( string.find( page, "Wi-Fi clients:", 1, true ) ~= nil, "home page shows client count" )
assertTrue( string.find( page, "Status", 1, true ) ~= nil, "home page has a status section" )

local wifipage = DRV:GetWebPage( "/wifi" )
assertTrue( string.find( wifipage, "name=\"wpass\"", 1, true ) ~= nil, "wifi page has a password field" )
assertTrue( string.find( wifipage, "Wireless", 1, true ) == nil, "wifi page uses Status not raw wireless" )

local lanpage = DRV:GetWebPage( "/lan" )
assertTrue( string.find( lanpage, "name=\"dhcpstart\"", 1, true ) ~= nil, "lan page has DHCP start field" )
assertTrue( string.find( lanpage, "NAT:", 1, true ) ~= nil, "lan page shows NAT" )

local fwpage = DRV:GetWebPage( "/firewall" )
assertTrue( string.find( fwpage, "Firewall", 1, true ) ~= nil, "firewall page renders" )

-- Nav links are present and relative paths route to the right pages.
local nav = DRV:GetWebPage( "/wifi" )
assertTrue( string.find( nav, 'href="/lan"', 1, true ) ~= nil, "nav links to LAN page" )
assertTrue( string.find( nav, 'href="/firewall"', 1, true ) ~= nil, "nav links to firewall page" )

-- Query-string config application.
DRV:ApplyWebQuery( "?wireless=0&dhcpstart=5&firewall=1&wpass=random" )
assertTrue( routData.RouterCfg.Wireless == false, "wireless toggled off" )
assertTrue( routData.RouterCfg.DHCPStart == 5, "DHCP start updated" )
assertTrue( routData.RouterCfg.Firewall == true, "firewall enabled" )
assertTrue( routData.RouterCfg.WirePass ~= "abc", "password regenerated" )

-- Port-forwarding rules: add, look up, list, delete.
DRV:ApplyWebQuery( "?pfwan=8080&pfip=192.168.0.2&pfport=80" )
local pfrule = DRV:GetForwardRule( 8080 )
assertTrue( pfrule ~= nil and pfrule.ip == "192.168.0.2" and pfrule.port == 80, "forward rule added" )
assertTrue( DRV:GetForwardRule( 9999 ) == nil, "missing rule returns nil" )
local fwpage2 = DRV:GetWebPage( "/firewall" )
assertTrue( string.find( fwpage2, 'name="pfwan"', 1, true ) ~= nil, "firewall page has port-forward input fields" )
assertTrue( string.find( fwpage2, "8080", 1, true ) ~= nil, "firewall page lists the forward rule" )
DRV:ApplyWebQuery( "?delpf=8080" )
assertTrue( DRV:GetForwardRule( 8080 ) == nil, "forward rule deleted" )

-- Firewall rules: add, list, delete.
DRV:ApplyWebQuery( "?fwdir=in&fwsrc=10.0.0.9&fwdst=&fwport=75" )
assertTrue( routData.RouterCfg.FirewallRules[ 1 ].dir == "in", "firewall rule added" )
assertTrue( routData.RouterCfg.FirewallRules[ 1 ].src == "10.0.0.9", "firewall rule source" )
assertTrue( routData.RouterCfg.FirewallRules[ 1 ].port == 75, "firewall rule port" )
DRV:ApplyWebQuery( "?delfw=1" )
assertTrue( #(routData.RouterCfg.FirewallRules) == 0, "firewall rule deleted" )

-- Default-deny firewall: on blocks non-control-plane; allow rules open holes.
local function pkt( port, src, dst ) return { Port = port, Source = src, Dest = dst } end
routData.RouterCfg.Firewall = true
routData.RouterCfg.FirewallRules = {}
assertTrue( DRV:FirewallBlocks( pkt( 72, "fd00:1:0:5::2", "fd00:2:0:1::1" ), "wan" ), "firewall on blocks chat by default" )
assertTrue( not DRV:FirewallBlocks( pkt( 80, "fd00:1:0:5::2", "fd00:2:0:1::1" ), "wan" ), "web always allowed" )
assertTrue( not DRV:FirewallBlocks( pkt( 0, "fd00:1:0:5::2", "fd00:2:0:1::1" ), "wan" ), "ping always allowed" )
routData.RouterCfg.Firewall = false
assertTrue( not DRV:FirewallBlocks( pkt( 72, "fd00:1:0:5::2", "fd00:2:0:1::1" ), "wan" ), "firewall off allows" )
routData.RouterCfg.Firewall = true
DRV:AddFirewallRule( "in", "", "", 72 )
assertTrue( not DRV:FirewallBlocks( pkt( 72, "fd00:1:0:5::2", "fd00:2:0:1::1" ), "wan" ), "allow rule opens port 72" )
assertTrue( DRV:FirewallBlocks( pkt( 75, "fd00:1:0:5::2", "fd00:2:0:1::1" ), "wan" ), "other ports still blocked" )
routData.RouterCfg.FirewallRules = {}
routData.RouterCfg.Firewall = false

-- NAT flow remembers the dialled public address for the reply's source.
DRV:AddForward( 72, "192.168.0.2", 72 )
local fr = DRV:GetForwardRule( 72 )
DRV:RememberForwardFlow( fr, "fd00:1:0:5::2", 72, "fd00:2:0:1::1" )
local fl = DRV:GetForwardFlow( "192.168.0.2", 72 )
assertTrue( fl ~= nil and fl.src == "fd00:1:0:5::2" and fl.pub == "fd00:2:0:1::1", "flow stores peer + public addr" )
DRV:DeleteForward( 72 )

local sent
PCMod.Network.CreatePacket = function( src, dst, port, body ) sent = { src = src, dst = dst, port = port, body = body } end
DRV.ProcessPacket = function() end
local req = { Source = "10.0.1.2", Body = { "http", "/" } }
DRV:HandleWebRequest( req )
assertTrue( sent and sent.port == 80 and sent.body[1] == "http-response", "web reply packet created" )
assertEq( sent.src, "192.168.5.1", "web reply sourced from router" )
assertTrue( req.Delivered == true, "request marked delivered" )

-- The request path selects the sub-page.
local req2 = { Source = "10.0.1.2", Body = { "http", "/wifi" } }
DRV:HandleWebRequest( req2 )
assertTrue( string.find( sent.body[2], 'name="wpass"', 1, true ) ~= nil, "wifi sub-page served for /wifi" )

print( "ALL ROUTER IPV6 TESTS PASSED" )