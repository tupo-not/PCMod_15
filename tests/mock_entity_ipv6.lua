-- Entity dual-stack + IPv6 subnet integration test (plain Lua after translation).
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
function istable( v ) return type( v ) == "table" end

PCMod = {}
PCMod.Data = {}
PCMod.Msg = function() end
PCMod.Warning = function() end
PCMod.Cfg = {}
function AddCSLuaFile() end

SERVER = true
CLIENT = false

dofile( "pcmod_sh_common.lua" )

ENT = {}
dofile( "pcmod_shared.lua" )

local ent = setmetatable( {}, { __index = ENT } )
local nw = {}
function ent:EntIndex() return 1 end
function ent:IsValid() return true end
function ent:SetNWString( k, v ) nw[ k ] = v end
PCMod.Data[ 1 ] = {
	HardDrive = {},
	IP = {
		Add = false, Sub = false, Full = false, V6 = false,
		Back = { Add = false, Sub = false, Full = false, V6 = false },
	},
}

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

-- LAN: 192.168.5.2 -> fd00:c0:a8:5::3 (gateway .0 -> ::1, hosts .1+ -> ::2+)
ent:SetSubnet( 5 )
ent:SetIP( 2 )
assertEq( ent:GetFullIP(), "192.168.5.2", "IPv4 LAN address" )
assertEq( ent:GetIPv6(), "fd00:c0:a8:5::3", "emulated IPv6 LAN address" )
assertEq( ent:GetIPv6Prefix(), "fd00:c0:a8:5::/64", "LAN /64 prefix" )
assertEq( ent:GetIPv6Gateway(), "fd00:c0:a8:5::1", "LAN gateway" )
assertEq( ent:GetIPv6LinkLocal(), "fe80::3", "LAN link-local" )
assertEq( nw[ "IP" ], "192.168.5.2", "IPv4 NW string" )
assertEq( nw[ "IPv6" ], "fd00:c0:a8:5::3", "IPv6 NW string" )
assertEq( nw[ "IPv6.Prefix" ], "fd00:c0:a8:5::/64", "IPv6 prefix NW string" )
assertEq( nw[ "IPv6.LinkLocal" ], "fe80::3", "IPv6 link-local NW string" )

-- Backbone: 10.0.3.1 -> fd00:a:0:3::2
ent:SetBSubnet( 3 )
ent:SetBIP( 1 )
assertEq( ent:GetFullBIP(), "10.0.3.1", "IPv4 backbone address" )
assertEq( ent:GetBIPv6(), "fd00:a:0:3::2", "emulated IPv6 backbone address" )
assertEq( ent:GetBIPv6Prefix(), "fd00:a:0:3::/64", "backbone /64 prefix" )
assertEq( ent:GetBIPv6Gateway(), "fd00:a:0:3::1", "backbone gateway" )
assertEq( ent:GetBIPv6LinkLocal(), "fe80::2", "backbone link-local" )

-- Exact-address matching accepts every supported representation.
assertTrue( ent:IsAddressedTo( "192.168.5.2" ), "LAN IPv4 matches" )
assertTrue( ent:IsAddressedTo( "fd00:c0:a8:5::3" ), "LAN IPv6 matches" )
assertTrue( ent:IsAddressedTo( "fd00:c0:a8:5:0:0:0:3" ), "expanded LAN IPv6 matches" )
assertTrue( ent:IsAddressedTo( "[fd00:c0:a8:5::3]" ), "bracketed LAN IPv6 matches" )
assertTrue( ent:IsAddressedTo( "::ffff:192.168.5.2" ), "mapped LAN IPv4 matches" )
assertTrue( ent:IsAddressedTo( "10.0.3.1" ), "backbone IPv4 matches" )
assertTrue( ent:IsAddressedTo( "fd00:a:0:3::2" ), "backbone IPv6 matches" )
assertTrue( not ent:IsAddressedTo( "192.168.5.3" ), "other LAN host rejected" )
assertTrue( not ent:IsAddressedTo( "fd00:c0:a8:5::4" ), "other LAN IPv6 host rejected" )
assertTrue( not ent:IsAddressedTo( "::1" ), "loopback is not this entity" )
assertTrue( not ent:IsAddressedTo( nil ), "nil rejected" )

-- Subnet membership (what a router uses for on-link decisions).
assertTrue( ent:IsInIPv6Subnet( "fd00:c0:a8:5::99" ), "LAN prefix contains other host" )
assertTrue( ent:IsInIPv6Subnet( "192.168.5.99" ), "LAN prefix contains mapped/IPv4 host" )
assertTrue( not ent:IsInIPv6Subnet( "fd00:c0:a8:6::3" ), "other LAN subnet rejected" )
assertTrue( not ent:IsInIPv6Subnet( "fd00:c0:a8:5::3", true ), "backbone flag uses backbone prefix" )
assertTrue( ent:IsInIPv6Subnet( "fd00:a:0:3::99", true ), "backbone prefix membership" )

-- Lazy derivation for a data slot made before these fields existed.
PCMod.Data[ 1 ].IP.V6 = nil
PCMod.Data[ 1 ].IP.V6Prefix = nil
PCMod.Data[ 1 ].IP.V6Link = nil
assertEq( ent:GetIPv6(), "fd00:c0:a8:5::3", "lazy IPv6 derivation" )
assertEq( ent:GetIPv6Prefix(), "fd00:c0:a8:5::/64", "lazy prefix derivation" )
assertEq( ent:GetIPv6LinkLocal(), "fe80::3", "lazy link-local derivation" )
PCMod.Data[ 1 ].IP.Back.V6 = nil
PCMod.Data[ 1 ].IP.Back.V6Prefix = nil
PCMod.Data[ 1 ].IP.Back.V6Link = nil
assertEq( ent:GetBIPv6(), "fd00:a:0:3::2", "lazy backbone IPv6 derivation" )
assertEq( ent:GetBIPv6Prefix(), "fd00:a:0:3::/64", "lazy backbone prefix" )

-- Router-style host 0 becomes the ::1 gateway.
ent:SetIP( 0 )
assertEq( ent:GetFullIP(), "192.168.5.0", "IPv4 gateway address" )
assertEq( ent:GetIPv6(), "fd00:c0:a8:5::1", "IPv6 gateway address" )

-- Clearing an address must clear every derived field.
ent:SetIP( false )
assertEq( ent:GetIPv6(), false, "cleared IPv6" )
assertEq( ent:GetIPv6Prefix(), false, "cleared prefix" )
assertEq( ent:GetIPv6Gateway(), false, "cleared gateway" )
assertEq( ent:GetIPv6LinkLocal(), false, "cleared link-local" )
assertEq( nw[ "IPv6" ], "", "cleared IPv6 NW string" )
assertEq( nw[ "IPv6.Prefix" ], "", "cleared prefix NW string" )

print( "ALL ENTITY IPV6 TESTS PASSED" )
