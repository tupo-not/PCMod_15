-- IPv6 emulation + subnet helper tests (plain Lua after translation).
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
	for i = 1, #str do
		if (string.sub( str, i, i ) == char) then r = r + 1 end
	end
	return r
end
function table.HasValue( t, v )
	for _, x in pairs( t ) do if (x == v) then return true end end
	return false
end

PCMod = {}

dofile( "pcmod_sh_common.lua" )

local v6 = PCMod.IPv6
local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

-- Address generation: one /64 per LAN, gateway at ::1, hosts from ::2.
assertEq( v6.FromIPv4( "192.168.5.1" ), "fd00:c0:a8:5::1", "FromIPv4 LAN gateway (.1)" )
assertEq( v6.FromIPv4( "192.168.5.2" ), "fd00:c0:a8:5::2", "FromIPv4 LAN host 1 (.2)" )
assertEq( v6.FromIPv4( "192.168.5.3" ), "fd00:c0:a8:5::3", "FromIPv4 LAN host 2 (.3)" )
assertEq( v6.FromIPv4( "10.0.3.0" ), "fd00:a:0:3::1", "FromIPv4 backbone gateway" )
assertEq( v6.FromIPv4( "10.0.3.1" ), "fd00:a:0:3::2", "FromIPv4 backbone host 1" )
assertEq( v6.FromIPv4( "127.0.0.1" ), "::1", "FromIPv4 loopback" )
assertEq( v6.FromIPv4( "8.8.8.8" ), "::ffff:808:808", "FromIPv4 mapped public" )
assertEq( v6.FromIPv4( "not an ip" ), nil, "FromIPv4 rejects junk" )
assertEq( v6.FromIPv4( "1.2.3.300" ), nil, "FromIPv4 rejects >255" )

-- Parsing / compression.
assertEq( v6.Format( v6.Expand( "fd00:0:c0a8:0005:0:0:0:3" ) ), "fd00:0:c0a8:5::3", "Expand/Format round trip" )
assertEq( v6.Format( v6.Expand( "::" ) ), "::", "Expand all zero" )
assertEq( v6.Format( v6.Expand( "::1" ) ), "::1", "Expand loopback" )
assertEq( v6.Format( v6.Expand( "FD00:C0:A8:5::3" ) ), "fd00:c0:a8:5::3", "case insensitive" )
assertEq( v6.Expand( "1::2::3" ), nil, "rejects two :: groups" )
assertEq( v6.Expand( "1:2:3:4:5:6:7" ), nil, "rejects short address" )
assertEq( v6.Expand( "1:2:3:4:5:6:7:8:9" ), nil, "rejects long address" )
assertEq( v6.Expand( "12345::1" ), nil, "rejects overlong group" )
assertEq( v6.Expand( "1:::2" ), nil, "rejects triple colon" )

-- Translation back to the IPv4 routing core.
assertEq( v6.ToIPv4( "192.168.5.2" ), "192.168.5.2", "ToIPv4 passthrough" )
assertEq( v6.ToIPv4( "fd00:c0:a8:5::3" ), "192.168.5.3", "ToIPv4 LAN host" )
assertEq( v6.ToIPv4( "fd00:c0:a8:5::2" ), "192.168.5.2", "ToIPv4 LAN host 1" )
assertEq( v6.ToIPv4( "fd00:c0:a8:5::1" ), "192.168.5.1", "ToIPv4 LAN gateway" )
assertEq( v6.ToIPv4( "fd00:c0:a8:5:0:0:0:3" ), "192.168.5.3", "ToIPv4 expanded form" )
assertEq( v6.ToIPv4( "fd00:a:0:3::2" ), "10.0.3.1", "ToIPv4 backbone form" )
assertEq( v6.ToIPv4( "FD00:C0:A8:5::3" ), "192.168.5.3", "ToIPv4 case-insensitive" )
assertEq( v6.ToIPv4( "[fd00:c0:a8:5::3]" ), "192.168.5.3", "ToIPv4 brackets" )
assertEq( v6.ToIPv4( "::ffff:192.168.5.2" ), "192.168.5.2", "ToIPv4 mapped dotted" )
assertEq( v6.ToIPv4( "::ffff:c0a8:0502" ), "192.168.5.2", "ToIPv4 mapped hex" )
assertEq( v6.ToIPv4( "::1" ), "127.0.0.1", "ToIPv4 loopback" )
assertEq( v6.ToIPv4( "localhost" ), "127.0.0.1", "ToIPv4 localhost" )
assertEq( v6.ToIPv4( "fe80::3" ), nil, "ToIPv4 link-local not routable" )
assertEq( v6.ToIPv4( "fd00:1:2:3::1" ), nil, "ToIPv4 rejects foreign ULA" )

-- Validation and equality.
assertTrue( v6.IsIP( "192.168.5.2" ), "IsIP v4" )
assertTrue( v6.IsIP( "fd00:c0:a8:5::3" ), "IsIP v6" )
assertTrue( v6.IsIP( "[::1]" ), "IsIP bracketed loopback" )
assertTrue( v6.IsIP( "localhost" ), "IsIP localhost" )
assertTrue( not v6.IsIP( "hello" ), "IsIP rejects text" )
assertTrue( not v6.IsIP( nil ), "IsIP rejects nil" )
assertTrue( v6.IsIPv6( "fd00:c0:a8:5::3" ), "IsIPv6 true" )
assertTrue( not v6.IsIPv6( "192.168.5.2" ), "IsIPv6 false for v4" )
assertTrue( v6.IsIPv4( "192.168.5.2" ), "IsIPv4 true" )
assertTrue( not v6.IsIPv4( "fd00:c0:a8:5::3" ), "IsIPv4 false for v6" )
assertTrue( v6.Equal( "fd00:c0:a8:5::3", "fd00:c0:a8:5:0:0:0:3" ), "Equal compressed/expanded" )
assertTrue( not v6.Equal( "fd00:c0:a8:5::3", "fd00:c0:a8:5::4" ), "Equal different hosts" )

-- Subnet / prefix math.
assertEq( v6.GetPrefix( "fd00:c0:a8:5::3", 64 ), "fd00:c0:a8:5::/64", "GetPrefix /64" )
assertEq( v6.GetPrefix( "fd00:c0:a8:5::3" ), "fd00:c0:a8:5::3/128", "GetPrefix default /128" )
assertEq( v6.GetPrefix( "192.168.5.2", 64 ), "fd00:c0:a8:5::/64", "GetPrefix from IPv4" )
assertEq( v6.GetPrefix( "fd00:c0:a8:5::3/48" ), "fd00:c0:a8::/48", "GetPrefix CIDR input" )
assertEq( v6.Network( "fd00:c0:a8:5::3", 64 ), "fd00:c0:a8:5::", "Network strips host bits" )
assertEq( v6.SubnetOf( "fd00:a:0:3::2", 64 ), "fd00:a:0:3::/64", "SubnetOf" )

assertTrue( v6.InSubnet( "fd00:c0:a8:5::3", "fd00:c0:a8:5::/64" ), "InSubnet same /64" )
assertTrue( not v6.InSubnet( "fd00:c0:a8:6::3", "fd00:c0:a8:5::/64" ), "InSubnet other /64" )
assertTrue( v6.InSubnet( "fd00:c0:a8:5::3", "fd00:c0:a8::/48" ), "InSubnet /48" )
assertTrue( v6.InSubnet( "fd00:c0:a8:5::3", "::/0" ), "InSubnet /0" )
assertTrue( v6.InSubnet( "192.168.5.2", "fd00:c0:a8:5::/64" ), "InSubnet IPv4 maps into LAN /64" )
assertTrue( v6.InSubnet( "10.0.3.2", "fd00:a:0:3::/64" ), "InSubnet IPv4 maps into backbone /64" )
assertTrue( v6.InSubnet( "fd00:c0:a8:5::3", "fd00:c0:a8:5::3" ), "InSubnet /128 exact" )
assertTrue( not v6.InSubnet( "fd00:c0:a8:5::4", "fd00:c0:a8:5::3" ), "InSubnet /128 different" )
assertTrue( v6.InSubnet( "fd00:c0:a8:5::3", "fd00:c0:a8:5::", 64 ), "InSubnet separate length" )

assertEq( v6.Gateway( "fd00:c0:a8:5::/64" ), "fd00:c0:a8:5::1", "Gateway /64" )
assertEq( v6.Gateway( "fd00:a:0:3::/64" ), "fd00:a:0:3::1", "Gateway backbone /64" )
assertEq( v6.Gateway( "fd00:c0:a8:5::3/128" ), nil, "Gateway outside /128" )

-- Link-local and classification.
assertEq( v6.LinkLocal( "fd00:c0:a8:5::3" ), "fe80::3", "LinkLocal from global" )
assertEq( v6.LinkLocal( "192.168.5.2" ), "fe80::2", "LinkLocal from IPv4" )
assertEq( v6.LinkLocal( 2 ), "fe80::2", "LinkLocal from number" )
assertEq( v6.AddressType( "fd00:c0:a8:5::3" ), "unique-local", "type unique-local" )
assertEq( v6.AddressType( "fe80::3" ), "link-local", "type link-local" )
assertEq( v6.AddressType( "::1" ), "loopback", "type loopback" )
assertEq( v6.AddressType( "127.0.0.1" ), "loopback", "type loopback v4" )
assertEq( v6.AddressType( "::ffff:192.168.5.2" ), "ipv4-mapped", "type mapped" )
assertEq( v6.AddressType( "8.8.8.8" ), "ipv4", "type ipv4" )
assertEq( v6.AddressType( "nope" ), "invalid", "type invalid" )

assertTrue( v6.IsLoopback( "127.0.0.1" ), "loopback v4" )
assertTrue( v6.IsLoopback( "::1" ), "loopback v6" )
assertTrue( v6.IsLoopback( "localhost" ), "loopback localhost" )
assertTrue( not v6.IsLoopback( "fd00:c0:a8:5::1" ), "gateway is not loopback" )

assertTrue( v6.Matches( "fd00:c0:a8:5::3", "192.168.5.2", "fd00:c0:a8:5::3" ), "Matches v6->v4" )
assertTrue( v6.Matches( "192.168.5.2", "192.168.5.2", nil ), "Matches v4" )
assertTrue( v6.Matches( "::ffff:192.168.5.2", "192.168.5.2", nil ), "Matches mapped" )
assertTrue( not v6.Matches( "192.168.5.3", "192.168.5.2", nil ), "Matches rejects other" )
assertTrue( not v6.Matches( nil, "192.168.5.2", nil ), "Matches rejects nil" )

print( "ALL IPV6 TESTS PASSED" )
