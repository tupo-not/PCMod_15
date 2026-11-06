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
function ent:GetMAC() return "AA:BB:CC:DD:EE:FF" end
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
local routData = { WirePass = "abc", IsWireless = true, IP = { UpBB = 3, LanID = 5 } }
function ent:GetClass() return "pcmod_router" end
function ent:GetFullIP() return "192.168.5.1" end
function ent:GetIPv6() return "fd00:3:0:5::1" end
function ent:GetIPv6Prefix() return "fd00:3:0:5::/64" end
function ent:GetBSubnet() return 3 end
function ent:GetSourceAddress() return "192.168.5.1" end
// The real entity re-syncs its address text here; the mock just records it.
function ent:SetSubnet( s ) routData.IP = routData.IP or {} routData.IP.Sub = s end
function ent:SetIP( h ) routData.IP = routData.IP or {} routData.IP.Add = h end
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
assertTrue( string.find( lanpage, "Netmask", 1, true ) ~= nil, "lan page shows the netmask row" )
assertTrue( string.find( lanpage, "192.168.0.2", 1, true ) ~= nil, "lan page shows the dotted pool start" )
assertTrue( string.find( lanpage, "192.168.0.0/24", 1, true ) ~= nil, "lan page shows the /24 network" )

-- Netmask + third octet query settings, with the pool clamped to the mask.
DRV:ApplyWebQuery( "?netmask=16&dhcpend=99999" )
assertEq( routData.RouterCfg.LanNetmask, 16, "netmask query applied" )
assertEq( routData.RouterCfg.DHCPEnd, 65534, "pool end clamped to /16 maximum" )
local lan16 = DRV:GetWebPage( "/lan" )
assertTrue( string.find( lan16, "192.168.0.0/16", 1, true ) ~= nil, "lan page shows the /16 network" )
DRV:ApplyWebQuery( "?netmask=24&lannet=7" )
assertEq( routData.RouterCfg.LanNetmask, 24, "netmask query back to /24" )
assertEq( routData.RouterCfg.LanNet, 7, "third octet query applied" )
assertEq( routData.RouterCfg.DHCPEnd, 254, "pool end clamped back to /24 maximum" )
local lan7 = DRV:GetWebPage( "/lan" )
assertTrue( string.find( lan7, "192.168.7.0/24", 1, true ) ~= nil, "lan page shows the custom /24 network" )
local home7 = DRV:GetWebPage( "" )
assertTrue( string.find( home7, "192.168.7.", 1, true ) ~= nil, "home page pool uses the third octet" )
assertTrue( string.find( home7, "/24", 1, true ) ~= nil, "home page shows the LAN prefix" )
DRV:ApplyWebQuery( "?lannet=0" )
assertEq( routData.RouterCfg.LanNet, 0, "third octet reset" )

-- In /24 mode a full dotted pool bound also selects the third octet.
DRV:ApplyWebQuery( "?dhcpstart=192.168.9.20&dhcpend=192.168.9.40" )
assertEq( routData.RouterCfg.LanNet, 9, "dotted pool bound selects the third octet" )
assertEq( routData.RouterCfg.DHCPStart, 20, "dotted pool start keeps its host id" )
assertEq( routData.RouterCfg.DHCPEnd, 40, "dotted pool end keeps its host id" )
local lan9 = DRV:GetWebPage( "/lan" )
assertTrue( string.find( lan9, "192.168.9.20", 1, true ) ~= nil, "lan page shows the dotted pool start" )
assertTrue( string.find( lan9, "192.168.9.40", 1, true ) ~= nil, "lan page shows the dotted pool end" )

-- Typing the gateway address (192.168.4.1) as a bound sets the octet to 4,
-- while .1 stays reserved for the router and clients start at .2.
DRV:ApplyWebQuery( "?dhcpstart=192.168.4.1&dhcpend=192.168.4.100" )
assertEq( routData.RouterCfg.LanNet, 4, "gateway-style pool bound sets the third octet" )
assertEq( routData.RouterCfg.DHCPStart, 2, "gateway address .1 is reserved for the router" )
assertEq( routData.RouterCfg.DHCPEnd, 100, "dotted pool end keeps its host id" )
DRV:ApplyWebQuery( "?lannet=0&dhcpstart=2&dhcpend=254" )
assertEq( routData.RouterCfg.LanNet, 0, "network reset after dotted pool test" )

-- Arbitrary netmask sizes via the web page (16-32).
DRV:ApplyWebQuery( "?netmask=26" )
assertEq( routData.RouterCfg.LanNetmask, 26, "/26 query applied" )
assertEq( routData.RouterCfg.DHCPEnd, 62, "/26 pool clamps to the block" )
assertEq( DRV:GetLanPrefix(), "192.168.0.0/26", "/26 prefix" )
local lan26 = DRV:GetWebPage( "/lan" )
assertTrue( string.find( lan26, "name=\"netmask\"", 1, true ) ~= nil, "lan page has the netmask field" )
assertTrue( string.find( lan26, "192.168.0.0/26", 1, true ) ~= nil, "lan page shows the /26 network" )
assertTrue( string.find( lan26, "192.168.0.2", 1, true ) ~= nil, "lan page shows the /26 pool start" )

-- A dotted pool bound can pick a network inside the larger address space
-- (192.168.4.x is valid inside 192.168.0.0/20).
DRV:ApplyWebQuery( "?netmask=20&dhcpstart=192.168.4.2&dhcpend=192.168.4.200" )
assertEq( routData.RouterCfg.LanNetmask, 20, "/20 query applied" )
assertEq( DRV:GetLanPrefix(), "192.168.0.0/20", "/20 prefix" )
assertEq( routData.RouterCfg.DHCPStart, 1026, "/20 dotted start is a host offset" )
assertEq( routData.RouterCfg.DHCPEnd, 1224, "/20 dotted end is a host offset" )

-- Quick /30 link (no pool fields) clamps the pool to one client.
DRV:ApplyWebQuery( "?netmask=30" )
assertEq( DRV:GetLanPrefix(), "192.168.0.0/30", "/30 prefix" )
assertEq( routData.RouterCfg.DHCPEnd, 2, "/30 pool clamps to one client" )

DRV:ApplyWebQuery( "?netmask=24&lannet=0&dhcpstart=2&dhcpend=254" )
assertEq( routData.RouterCfg.LanNetmask, 24, "netmask reset to /24" )

-- A dotted last bound alone also picks the network.
DRV:ApplyWebQuery( "?dhcpstart=2&dhcpend=192.168.12.50" )
assertEq( routData.RouterCfg.LanNet, 12, "dotted last bound sets the network" )
assertEq( routData.RouterCfg.DHCPStart, 2, "bare first bound stays a host id" )
assertEq( routData.RouterCfg.DHCPEnd, 50, "dotted last bound keeps its host id" )
DRV:ApplyWebQuery( "?lannet=0&dhcpstart=2&dhcpend=254" )
assertEq( routData.RouterCfg.LanNet, 0, "network reset after the last-bound test" )

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

-- PAT forward flow: keyed by the ephemeral port the router presents internally.
DRV:RememberForwardFlow( 40001, "10.0.1.2", 40010, "10.0.2.2" )
local fl = DRV:GetForwardFlow( 40001 )
assertTrue( fl ~= nil and fl.src == "10.0.1.2" and fl.port == 40010 and fl.pub == "10.0.2.2", "forward flow stores peer + public addr" )
assertTrue( DRV:GetForwardFlow( 72 ) == nil, "unrelated port has no forward flow" )

-- Outbound masquerade (PAT) flow: remember the internal host by ephemeral port.
DRV:RememberNatOut( 40011, "192.168.0.2", 72 )
local nf = DRV:GetNatOut( 40011 )
assertTrue( nf ~= nil and nf.ip == "192.168.0.2" and nf.port == 72, "masquerade flow stores internal host + port" )
assertTrue( DRV:GetNatOut( 58 ) == nil, "unrelated port has no masquerade flow" )

-- With the firewall on, an established NAT reply still passes (stateful), even
-- without an allow rule for the ephemeral port.
routData.RouterCfg.Firewall = true
routData.RouterCfg.FirewallRules = {}
assertTrue( not DRV:FirewallBlocks( { Port = 40001, Source = "192.168.0.2", Dest = "192.168.0.1" }, "lan" ), "forwarded reply passes firewall (stateful flow)" )
assertTrue( not DRV:FirewallBlocks( { Port = 40011, Source = "10.0.2.2", Dest = "10.0.1.2" }, "wan" ), "masquerade reply passes firewall (stateful NAT)" )
routData.RouterCfg.Firewall = false

-- Ephemeral ports are unique and wrap within the PAT range.
local e1 = DRV:AllocEph()
local e2 = DRV:AllocEph()
assertTrue( e1 ~= e2, "ephemeral ports differ" )
assertTrue( e1 >= 40000 and e1 <= 65000, "ephemeral in PAT range" )

-- A router answers a ping addressed to its own address, replying from the
-- address that was pinged and preserving the source port (NAT-safe).
PCMod.Msg = function() end
local pingDrv = {}
for k, v in pairs( DRV ) do pingDrv[ k ] = v end
local pingEnt = {}
function pingEnt:Memory() return {} end
function pingEnt:UpdateMemory() end
function pingEnt:Data() return {} end
function pingEnt:IsAddressedTo( a ) return a == "10.0.1.4" end
pingDrv.Entity = pingEnt
local replied
pingDrv.Process = function( self, data ) replied = data return true end
PCMod.Network.Packets[ 200 ] = {
	Source = "10.0.1.3", Dest = "10.0.1.4", Port = 0, SourcePort = 40001,
	Body = { "netPing", "nettools" },
}
pingDrv:ProcessPacket( 200, nil, nil )
assertTrue( replied and replied[ 1 ] == "sendpacket", "router replies to a ping" )
assertEq( replied[ 2 ][ 1 ], "10.0.1.4", "ping reply comes from the pinged address" )
assertEq( replied[ 2 ][ 2 ], "10.0.1.3", "ping reply goes back to the sender" )
assertEq( replied[ 2 ][ 3 ], 40001, "ping reply preserves the source port for NAT" )
assertEq( replied[ 2 ][ 4 ][ 1 ], "netPingResponse", "ping reply body" )

-- TTL: routers decrement once per hop and expire at zero.
PCMod.Cfg.DefaultTTL = 64
local traceDrv = {}
for k, v in pairs( DRV ) do traceDrv[ k ] = v end
local traceEnt = {}
function traceEnt:Memory() return {} end
function traceEnt:UpdateMemory() end
function traceEnt:Data() return {} end
function traceEnt:GetClass() return "pcmod_router" end
function traceEnt:GetSubnet() return 5 end
function traceEnt:GetFullIP() return "192.168.5.1" end
function traceEnt:GetBSubnet() return 3 end
function traceEnt:GetFullBIP() return "10.0.1.5" end
function traceEnt:IsAddressedTo( a ) return a == "10.0.1.4" end
traceDrv.Entity = traceEnt
local traceSent
traceDrv.Process = function( self, data ) traceSent = data return true end

-- A packet above one TTL continues and is decremented exactly once.
local ttlPkt = { TTL = 4, Body = { "netTrace", "nettools", 1, 4 } }
assertTrue( traceDrv:CheckTTL( ttlPkt, "lan" ), "ttl above one is forwarded" )
assertEq( ttlPkt.TTL, 3, "ttl decremented once per hop" )

-- A TTL of one dies at the router and reports the hop to the sender.
local expired = { Source = "192.168.5.2", Port = 0, SourcePort = 0, TTL = 1, Body = { "netTrace", "nettools", 1, 1 } }
assertTrue( not traceDrv:CheckTTL( expired, "lan" ), "ttl of one expires" )
assertTrue( traceSent and traceSent[ 1 ] == "sendpacket", "expired trace probe reports a hop" )
assertEq( traceSent[ 2 ][ 1 ], "192.168.5.1", "LAN probe reports from the LAN gateway" )
assertEq( traceSent[ 2 ][ 3 ], 0, "hop reply preserves the probe source port" )
assertEq( traceSent[ 2 ][ 4 ][ 1 ], "netTraceHop", "hop report body type" )
assertEq( traceSent[ 2 ][ 4 ][ 4 ], "192.168.5.1", "hop report carries the reporting address" )
assertEq( traceSent[ 2 ][ 4 ][ 5 ], "RTR", "hop report carries the router label" )
assertEq( traceSent[ 2 ][ 4 ][ 6 ], 1, "hop report carries the probe number" )

-- A probe arriving from the backbone reports from the WAN address and keeps
-- the source port so it can pass back through the sender's NAT.
traceSent = nil
local expiredWan = { Source = "10.0.1.3", Port = 0, SourcePort = 40003, TTL = 1, Body = { "netTrace", "nettools", 1, 1 } }
assertTrue( not traceDrv:CheckTTL( expiredWan, "wan" ), "WAN ttl of one expires" )
assertEq( traceSent[ 2 ][ 1 ], "10.0.1.5", "WAN probe reports from the backbone address" )
assertEq( traceSent[ 2 ][ 3 ], 40003, "WAN hop keeps the source port for NAT" )

-- A probe addressed to the router itself is the final hop.
traceSent = nil
PCMod.Network.Packets[ 301 ] = {
	Source = "10.0.1.3", Dest = "10.0.1.4", Port = 0, SourcePort = 40002,
	Body = { "netTrace", "nettools", 2, 3 }, TTL = 1, Delivered = false,
}
traceDrv:ProcessPacket( 301, nil, "wan" )
assertTrue( traceSent and traceSent[ 2 ][ 4 ][ 1 ] == "netTraceResponse", "router answers a trace probe to itself" )
assertEq( traceSent[ 2 ][ 1 ], "10.0.1.4", "trace reply comes from the traced address" )
assertEq( traceSent[ 2 ][ 2 ], "10.0.1.3", "trace reply goes to the probe source" )
assertEq( traceSent[ 2 ][ 3 ], 40002, "trace reply preserves the source port" )

-- A probe for a remote target with TTL 1 reports the first hop instead of
-- forwarding, exactly like an ICMP time-exceeded.
traceSent = nil
PCMod.Network.Packets[ 302 ] = {
	Source = "192.168.5.2", Dest = "10.0.1.9", Port = 0, SourcePort = 0,
	Body = { "netTrace", "nettools", 3, 1 }, TTL = 1, Delivered = false,
}
traceDrv:ProcessPacket( 302, nil, "lan" )
assertTrue( traceSent and traceSent[ 2 ][ 4 ][ 1 ] == "netTraceHop", "first hop reports at ttl 1" )
assertEq( traceSent[ 2 ][ 4 ][ 6 ], 1, "first hop number" )

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

-- A LAN router behind a switch gets the same backbone /64 + WAN address as a
-- directly cabled one; the switch passes a synthetic linked event with the
-- far-side entity in data[3].
table.ToString = function() return "" end
PCMod.Msg = function() end
PCMod.Data = PCMod.Data or {}
local bdrv = {}
for k, v in pairs( DRV ) do bdrv[ k ] = v end
local bport = { Connected = true }
local fakeSwitch = { IsSwitch = true }
function fakeSwitch:GetBridgePeers() return {} end
bport.ConEnt = fakeSwitch
local bent = {}
function bent:GetClass() return "pcmod_brouter" end
function bent:Ports() return { [ 1 ] = bport } end
function bent:GetBSubnet() return 7 end
bdrv.Entity = bent
bdrv.BLAN = {}
bdrv.Children = {}
bdrv.ChildLan = {}
bdrv.Neighbors = {}
bdrv.Leases = {}
local childEnt = {}
function childEnt:IsValid() return true end
function childEnt:EntIndex() return 60 end
function childEnt:GetClass() return "pcmod_router" end
function childEnt:SetUpBB( v ) self.UpBB = v end
function childEnt:SetLanID( v ) self.LanID = v end
PCMod.Data[ 60 ] = { Drivers = { webgr_router = {
	SetLinkToEntity = function() end,
	ReconfigureClients = function() end,
} } }
local registered
PCMod.Network.RegisterPC = function( ent, bb ) registered = { ent = ent, bb = bb } end

bdrv:CallEvent( { Event = "linked", [ 1 ] = 1, [ 2 ] = fakeSwitch, [ 3 ] = childEnt } )
assertTrue( bdrv.Children[ 60 ] == 1, "LAN router behind switch is tracked as a child" )
assertEq( childEnt.UpBB, 7, "LAN router gets the backbone id" )
assertEq( childEnt.LanID, 1, "LAN router gets a /64 id" )
assertTrue( registered and registered.ent == childEnt and registered.bb == 7, "LAN router registered on the backbone" )
assertTrue( bdrv.ChildLan[ 1 ] == bport, "child route uses the switch port for delivery" )

print( "ALL ROUTER IPV6 TESTS PASSED" )