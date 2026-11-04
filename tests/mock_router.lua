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

r = DRV:ClassifyDestination( "10.0.3.1" )
assertTrue( r.Backbone, "IPv4 backbone target" )
assertTrue( not r.OnLinkBackbone, "IPv4 backbone is not on-link" )

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
function ent:Data() return { WirePass = "abc" } end
PCMod.Cfg.DHCPStart = 2
PCMod.Cfg.DHCPEnd = 250
DRV.Wireless = true
DRV.WirelessClients = { [10] = true, [11] = true }
local page = DRV:GetWebPage()
assertTrue( string.find( page, "192.168.5.1", 1, true ) ~= nil, "page shows IPv4 LAN" )
assertTrue( string.find( page, "fd00:3:0:5::/64", 1, true ) ~= nil, "page shows IPv6 prefix" )
assertTrue( string.find( page, "password abc", 1, true ) ~= nil, "page shows Wi-Fi password" )
assertTrue( string.find( page, "Wi-Fi clients: 2", 1, true ) ~= nil, "page shows client count" )

local sent
PCMod.Network.CreatePacket = function( src, dst, port, body ) sent = { src = src, dst = dst, port = port, body = body } end
DRV:HandleWebRequest( { Source = "10.0.1.2" } )
assertTrue( sent and sent.port == 80 and sent.body[1] == "http-response", "web reply packet created" )
assertEq( sent.src, "192.168.5.1", "web reply sourced from router" )

print( "ALL ROUTER IPV6 TESTS PASSED" )