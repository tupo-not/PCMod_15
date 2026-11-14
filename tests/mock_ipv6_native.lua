-- Native IPv6 address helpers and packet-family metadata.
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
function table.HasValue( t, v )
	for _, x in pairs( t ) do if (x == v) then return true end end
	return false
end
function istable( v ) return type( v ) == "table" end

PCMod = {
	Msg = function() end,
	Cfg = { MaxNetworkPid = 8, DefaultTTL = 64 },
	MAC = {
		BROADCAST = "FF:FF:FF:FF:FF:FF",
		Normalize = function( mac )
			if (type( mac ) ~= "string") then return nil end
			return string.upper( mac )
		end,
	},
}

dofile( "pcmod_sh_common.lua" )
dofile( "pcmod_sh_netproto.lua" )
PCMod.Msg = function() end
function CreateConVar() return nil end
dofile( "pcmod_network.lua" )

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

local v6 = PCMod.IPv6

-- Native allocation helpers.
assertEq( v6.BackboneAddress( 3, 2 ), "fd00:3::2", "native backbone host" )
assertEq( v6.BackboneAddress( 258, 5 ), "fd00:102::5", "native 16-bit backbone host" )
assertEq( v6.LANAddress( 3, 5, 2 ), "fd00:3:0:5::2", "native LAN host" )
assertEq( v6.LANAddress( 0, 7, 9 ), "fd00:0:0:7::9", "native standalone LAN host" )
assertEq( v6.Family( "fd00:3:0:5::2" ), "ipv6", "ULA is IPv6" )
assertEq( v6.Family( "192.168.5.2" ), "ipv4", "dotted quad is IPv4" )
assertEq( v6.Family( "nope" ), nil, "junk has no family" )

-- A packet keeps the family it was created with and stores the native IPv6
-- endpoint. It never fabricates an IPv4 address for a native IPv6 endpoint.
local pid = PCMod.Network.CreatePacket( "fd00:3:0:5::2", "fd00:3:0:6::9", 72, { "payload" } )
assertTrue( pid ~= nil, "IPv6 packet created" )
local pk = PCMod.Network.Packets[ pid ]
assertEq( pk.SourceFamily, "ipv6", "source family is IPv6" )
assertEq( pk.DestFamily, "ipv6", "destination family is IPv6" )
assertEq( pk.SourceIPv6, "fd00:3:0:5::2", "native source kept" )
assertEq( pk.DestIPv6, "fd00:3:0:6::9", "native destination kept" )
assertTrue( pk.SourceIPv4 == nil, "no IPv4 source fabricated" )
assertTrue( pk.DestIPv4 == nil, "no IPv4 destination fabricated" )
assertEq( pk.SourceIPv6Prefix, "fd00:3:0:5::/64", "source /64 metadata" )
assertEq( pk.DestIPv6Prefix, "fd00:3:0:6::/64", "destination /64 metadata" )

-- IPv4 stays a first-class compatibility family: its canonical fields are
-- populated, and the IPv6 form is only the informational mapped view.
local pid4 = PCMod.Network.CreatePacket( "192.168.5.2", "192.168.5.9", 72, { "payload" } )
local pk4 = PCMod.Network.Packets[ pid4 ]
assertEq( pk4.SourceFamily, "ipv4", "source family is IPv4" )
assertEq( pk4.DestFamily, "ipv4", "destination family is IPv4" )
assertEq( pk4.SourceIPv4, "192.168.5.2", "IPv4 source kept" )
assertEq( pk4.DestIPv4, "192.168.5.9", "IPv4 destination kept" )
assertEq( pk4.SourceIPv6, "::ffff:c0a8:502", "IPv4 source has a mapped view" )
assertEq( pk4.DestIPv6, "::ffff:c0a8:509", "IPv4 destination has a mapped view" )

-- Compressed and expanded native forms normalise to one stored value.
local pid3 = PCMod.Network.CreatePacket( "FD00:3:0:5:0:0:0:2", "fd00:3:0:6::9", 73, { "payload" } )
assertEq( PCMod.Network.Packets[ pid3 ].SourceIPv6, "fd00:3:0:5::2", "native source normalised" )

print( "ALL NATIVE IPV6 TESTS PASSED" )