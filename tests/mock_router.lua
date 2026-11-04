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

-- Normal LAN router: owns fd00:c0:a8:5::/64, no backbone prefix.
ent.LanPrefix = "fd00:c0:a8:5::/64"
ent.BackPrefix = false
local r = DRV:ClassifyDestination( "fd00:c0:a8:5::3" )
assertTrue( r.IsIPv6, "own LAN is IPv6" )
assertTrue( r.LAN, "own LAN classified as LAN" )
assertTrue( r.OnLinkLAN, "own LAN is on-link" )
assertTrue( not r.Backbone, "own LAN is not backbone" )
assertEq( r.IPv4, "192.168.5.3", "own LAN translates to IPv4" )

r = DRV:ClassifyDestination( "fd00:c0:a8:5::99" )
assertTrue( r.OnLinkLAN, "unknown host on own LAN is still on-link (drop)" )

r = DRV:ClassifyDestination( "fd00:c0:a8:6::3" )
assertTrue( r.LAN, "other LAN classified as LAN" )
assertTrue( not r.OnLinkLAN, "other LAN is NOT on-link (must forward)" )
assertEq( r.IPv4, "192.168.6.3", "other LAN translates to IPv4" )

r = DRV:ClassifyDestination( "192.168.5.2" )
assertTrue( not r.IsIPv6, "IPv4 target" )
assertTrue( r.LAN, "IPv4 LAN target" )
assertTrue( not r.OnLinkLAN, "IPv4 does not use on-link drop" )

r = DRV:ClassifyDestination( "10.0.3.1" )
assertTrue( r.Backbone, "IPv4 backbone target" )
assertTrue( not r.OnLinkBackbone, "IPv4 backbone is not on-link" )

r = DRV:ClassifyDestination( "fd00:a:0:3::2" )
assertTrue( r.IsIPv6, "backbone IPv6 target" )
assertTrue( r.Backbone, "backbone IPv6 classified as backbone" )
assertTrue( not r.OnLinkBackbone, "other backbone is not on-link" )
assertEq( r.IPv4, "10.0.3.1", "backbone IPv6 translates to IPv4" )

r = DRV:ClassifyDestination( "::ffff:192.168.5.2" )
assertTrue( r.IsIPv6, "mapped target is IPv6" )
assertTrue( r.LAN, "mapped LAN target" )
assertEq( r.IPv4, "192.168.5.2", "mapped target translates" )

assertTrue( DRV:HasIPv6Subnet( "fd00:c0:a8:5::3" ), "HasIPv6Subnet own LAN" )
assertTrue( not DRV:HasIPv6Subnet( "fd00:c0:a8:6::3" ), "HasIPv6Subnet other LAN" )

-- Backbone router: owns fd00:a:0:3::/64, no LAN prefix.
ent.LanPrefix = false
ent.BackPrefix = "fd00:a:0:3::/64"
r = DRV:ClassifyDestination( "fd00:a:0:3::2" )
assertTrue( r.Backbone, "own backbone classified as backbone" )
assertTrue( r.OnLinkBackbone, "own backbone is on-link" )

r = DRV:ClassifyDestination( "fd00:a:0:4::2" )
assertTrue( r.Backbone, "other backbone classified as backbone" )
assertTrue( not r.OnLinkBackbone, "other backbone is not on-link (must flood)" )

r = DRV:ClassifyDestination( "fd00:c0:a8:6::3" )
assertTrue( r.LAN, "LAN target on backbone router classified as LAN" )
assertTrue( not r.OnLinkLAN, "backbone router has no on-link LAN (must flood)" )

print( "ALL ROUTER IPV6 TESTS PASSED" )
