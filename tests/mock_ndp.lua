-- IPv6 neighbor discovery tests.
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
function istable( v ) return type( v ) == "table" end

local Now = 0
function CurTime() return Now end

PCMod = {}
PCMod.Msg = function() end
PCMod.Cfg = {}
PCMod.MAC = {
	BROADCAST = "FF:FF:FF:FF:FF:FF",
	Normalize = function( mac )
		if (type( mac ) ~= "string") then return nil end
		return string.upper( mac )
	end,
}

dofile( "pcmod_sh_common.lua" )
dofile( "pcmod_sh_netproto.lua" )
dofile( "pcmod_sh_ndp.lua" )

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

local hostMAC = "AA:BB:CC:DD:EE:05"
local routerMAC = "AA:BB:CC:DD:EE:01"

local function NewEnt( addrs, mac )
	local e = { Addrs = addrs, MAC = mac, Sent = {} }
	function e:GetMAC() return self.MAC end
	function e:IsAddressedTo( a )
		for _, x in ipairs( self.Addrs ) do
			if (PCMod.IPv6.Normalize( x ) == PCMod.IPv6.Normalize( a )) then return true end
		end
		return false
	end
	function e:GetSourceAddress( dest )
		if (self:IsAddressedTo( dest )) then return dest end
		return self.Addrs[ 1 ]
	end
	function e:PushData( port, data )
		table.insert( self.Sent, { port = port, data = data } )
	end
	return e
end

-- Wire format.
assertTrue( PCMod.Net.IsNDP( PCMod.Net.NDPSolicit( "fd00:1::2", "fd00:1::1", routerMAC ) ), "solicitation is NDP" )
assertTrue( PCMod.Net.IsNDP( PCMod.Net.NDPAdvertise( "fd00:1::2", "fd00:1::2", hostMAC ) ), "advertisement is NDP" )
assertTrue( not PCMod.Net.IsNDP( PCMod.Net.ARPRequest( "10.0.0.1", "0.0.0.0", hostMAC ) ), "ARP is not NDP" )

-- A host answers a solicitation for an address it owns, from that address and
-- on the ingress port.
local target = "fd00:1:0:5::5"
local host = NewEnt( { target }, hostMAC )
local hostDrv = { Entity = host }
local ok = PCMod.NDP.Handle( hostDrv, 3, PCMod.Net.NDPSolicit( target, "fd00:1::1", routerMAC ), { SourceMAC = routerMAC } )
assertTrue( ok, "solicitation consumed" )
assertEq( #host.Sent, 1, "owner answers a solicitation" )
local frame = host.Sent[ 1 ]
assertEq( frame.port, 3, "answer goes out the ingress port" )
assertEq( frame.data[ 1 ], "sendpacket", "answer is a frame" )
local advertised = frame.data[ 2 ][ 4 ]
assertEq( advertised[ 1 ], "ndp", "answer is NDP" )
assertEq( advertised[ 2 ], "advertise", "answer is an advertisement" )
assertEq( advertised[ 3 ], target, "advertisement names the address" )
assertEq( advertised[ 4 ], target, "advertisement source is the address" )
assertEq( advertised[ 5 ], hostMAC, "advertisement carries the MAC" )

-- The requester learns MAC and port from the advertisement.
local router = NewEnt( { "fd00:1::1" }, routerMAC )
local routerDrv = { Entity = router }
PCMod.NDP.Handle( routerDrv, 3, advertised, { SourceMAC = hostMAC } )
assertEq( PCMod.NDP.MACFor( routerDrv, target ), hostMAC, "advertisement fills the neighbor cache" )
local rec = PCMod.NDP.Lookup( routerDrv, target )
assertEq( rec.port, 3, "cache remembers the port" )

-- An address the entity does not own is ignored.
local other = NewEnt( { "fd00:1:0:5::7" }, "AA:BB:CC:DD:EE:07" )
PCMod.NDP.Handle( { Entity = other }, 1, PCMod.Net.NDPSolicit( "fd00:1:0:5::99", "fd00:1::1", routerMAC ), { SourceMAC = routerMAC } )
assertEq( #other.Sent, 0, "an address we do not own is ignored" )

-- Resolve prefers the cache and sends nothing.
local before = #router.Sent
local hit = PCMod.NDP.Resolve( routerDrv, target, { 1, 2 }, "fd00:1::1" )
assertTrue( hit ~= nil, "resolve uses the cache" )
assertEq( #router.Sent, before, "cached resolution sends nothing" )

-- Resolve broadcasts a solicitation on every candidate port when unknown.
local fresh = NewEnt( { "fd00:1::1" }, routerMAC )
local miss = PCMod.NDP.Resolve( { Entity = fresh }, "fd00:2::9", { 1, 2 }, "fd00:1::1" )
assertTrue( miss == nil, "unknown neighbor returns nil" )
assertEq( #fresh.Sent, 2, "solicitation is broadcast on every candidate port" )
local sentBody = fresh.Sent[ 1 ].data[ 2 ][ 4 ]
assertEq( sentBody[ 2 ], "solicit", "request is a solicitation" )
assertEq( sentBody[ 3 ], "fd00:2::9", "solicitation names the target" )
assertEq( fresh.Sent[ 1 ].data[ 2 ][ 2 ], "ff02::1", "solicitation goes to all-nodes multicast" )

-- Entries expire after the neighbor-cache lifetime.
Now = (PCMod.Net.NdpTime or 60) + 1
assertTrue( PCMod.NDP.Lookup( routerDrv, target ) == nil, "stale neighbor entries expire" )

print( "ALL NDP TESTS PASSED" )
