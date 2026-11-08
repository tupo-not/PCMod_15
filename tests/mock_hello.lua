-- Routing hellos between directly cabled backbones and across a chain.
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
		if (not a) then table.insert( out, string.sub( str, start ) ) break end
		table.insert( out, string.sub( str, start, a - 1 ) )
		start = b + 1
	end
	return out
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
function table.Count( t )
	local n = 0
	for _ in pairs( t ) do n = n + 1 end
	return n
end

PCMod = {
	Msg = function() end,
	Cfg = { MaxNetworkPid = 500, MaxNetworkPass = 10, WirelessRange = 0, DefaultTTL = 64 },
	Network = { Packets = {}, NextSwitchFrame = 0 },
	DeriveDriver = function() return {} end,
	Data = {},
}
math.Clamp = function( v, a, b ) if (v < a) then return a end if (v > b) then return b end return v end
function istable( v ) return type( v ) == "table" end
function Msg( s ) end
function ErrorNoHalt( s ) end
function IsValid( e ) return e ~= nil end
local NOW = 0
CurTime = function() return NOW end
timer = { Simple = function() end }

dofile( "pcmod_sh_common.lua" )
dofile( "pcmod_sh_dhcp.lua" )
dofile( "pcmod_sh_netproto.lua" )
dofile( "pcmod_sh_routing.lua" )
dofile( "pcmod_drv_router.lua" )

local function assertTrue( v, m )
	if (not v) then error( "FAILED: " .. m, 2 ) end
end
local function assertEq( a, b, m )
	if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end

local function newPort( typ )
	return { Type = typ, Connected = false, ConEnt = nil, RemotePort = nil }
end

local function makeBackbone( idx, bb )
	local o = { Idx = idx, BB = bb }
	o.PortList = { newPort( "optic" ) }
	function o:IsValid() return true end
	function o:EntIndex() return self.Idx end
	function o:GetClass() return "pcmod_brouter" end
	function o:Ports() return self.PortList end
	function o:GetMAC() return "AA:BB:CC:00:00:" .. tostring( self.Idx ) end
	function o:GetBSubnet() return self.BB end
	function o:GetFullBIP() return "10.0." .. tostring( self.BB ) .. ".1" end
	function o:GetFullIP() return false end
	function o:Data() return { IP = { WanBB = self.BB, WanHost = 0 } } end
	function o:PushData( port, data )
		local p = self.PortList[ port ]
		if ((!p) || (!p.Connected) || (!p.ConEnt)) then return 2 end
		return p.ConEnt:GivenData( p.RemotePort, data )
	end
	function o:GivenData( port, data ) return self.Driver:DataRecieved( port, data ) end
	return o
end

local function makeDriver( ent )
	local d = {}
	for k, v in pairs( DRV ) do d[ k ] = v end
	d.Entity = ent
	d.Neighbors = {}
	d.NeighborMAC = {}
	d.RouteAdv = {}
	d.Routes = {}
	d.PrefixRoutes = {}
	d.NPorts = {}
	d.OPorts = { 1 }
	ent.Driver = d
	PCMod.Data[ ent:EntIndex() ] = { Drivers = { webgr_router = d } }
	return d
end

local function link( a, b, ap, bp )
	ap = ap or 1
	bp = bp or 1
	a.PortList[ ap ].Connected = true
	a.PortList[ ap ].ConEnt = b
	a.PortList[ ap ].RemotePort = bp
	b.PortList[ bp ].Connected = true
	b.PortList[ bp ].ConEnt = a
	b.PortList[ bp ].RemotePort = ap
end

-- Two backbones, one direct optic cable.
local b1 = makeBackbone( 1, 1 )
local b2 = makeBackbone( 2, 2 )
link( b1, b2 )
local d1, d2 = makeDriver( b1 ), makeDriver( b2 )

PCMod.Routing.Send( d1, true )
assertEq( d2.Neighbors[ 1 ], 1, "B2 records B1 as a direct neighbour" )
assertTrue( d2.NeighborMAC[ 1 ] ~= nil, "B2 records B1's MAC" )
assertTrue( d2.Routes[ 1 ] ~= nil, "B2 routes /32 1" )
assertEq( d2.Routes[ 1 ].via, 1, "B2 routes /32 1 via B1" )

PCMod.Routing.Send( d2, true )
assertEq( d1.Neighbors[ 2 ], 1, "B1 records B2 as a direct neighbour" )
assertTrue( d1.Routes[ 2 ] ~= nil, "B1 routes /32 2" )

-- A three-backbone chain: 1 -- 2 -- 3 must be reachable end-to-end, and the
-- routes must survive repeated hello rounds (no count-to-infinity).
local b3 = makeBackbone( 3, 3 )
b2.PortList[ 2 ] = newPort( "optic" )
link( b2, b3, 2, 1 )
d1.OPorts = { 1 }
d2.OPorts = { 1, 2 }
d3 = makeDriver( b3 )
d3.OPorts = { 1 }

for _ = 1, 4 do
	PCMod.Routing.Send( d1, true )
	PCMod.Routing.Send( d2, true )
	PCMod.Routing.Send( d3, true )
end
assertTrue( d1.Routes[ 3 ] ~= nil, "B1 learns /32 3 two hops away" )
assertEq( d1.Routes[ 3 ].via, 2, "B1 routes /32 3 via B2" )
assertTrue( d3.Routes[ 1 ] ~= nil, "B3 learns /32 1 two hops away" )
assertEq( d3.Routes[ 1 ].via, 2, "B3 routes /32 1 via B2" )

-- Remove the 2--3 cable. Split horizon must drop the dead route instead of
-- letting B1 and B2 point at each other forever.
b2.PortList[ 2 ].Connected = false
b3.PortList[ 1 ].Connected = false
d2.Neighbors[ 3 ] = nil
d2.RouteAdv[ 3 ] = nil
for _ = 1, 4 do
	PCMod.Routing.Send( d1, true )
	PCMod.Routing.Send( d2, true )
	PCMod.Routing.Send( d3, true )
end
assertTrue( d1.Routes[ 3 ] == nil, "B1 drops /32 3 after the cable is removed" )
assertTrue( d1.Routes[ 2 ] ~= nil, "B1 keeps its direct neighbour" )

-- A LAN router's /64 is learned as a prefix and re-advertised by the backbone.
PCMod.Routing.Handle( d2, 1, PCMod.Net.Hello( 2, "10.0.2.1", "AA:BB:CC:00:00:02", nil, { [ "fd00:2:0:7::/64" ] = true } ), { SourceMAC = "AA:BB:CC:00:00:02" } )
assertTrue( d2.PrefixRoutes[ "fd00:2:0:7::/64" ] ~= nil, "backbone stores an advertised /64" )
assertTrue( d2.PrefixRoutes[ "fd00:2:0:7::/64" ].port == 1, "prefix remembers the ingress port" )

-- A neighbour backbone reflecting that same /64 back must not steal the local
-- route from the LAN router attached to us.
PCMod.Routing.Handle( d2, 2, PCMod.Net.Hello( 3, "10.0.3.1", "AA:BB:CC:00:00:03", { [ 3 ] = 0 }, { [ "fd00:2:0:7::/64" ] = { origin = 2, hops = 9 } } ), { SourceMAC = "AA:BB:CC:00:00:03" } )
assertEq( d2.PrefixRoutes[ "fd00:2:0:7::/64" ].port, 1, "own /64 stays on the attached LAN port" )

print( "mock_hello PASSED" )
