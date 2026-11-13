-- One ICMP mechanism for ping and traceroute: wire-format helpers plus the OS
-- ping path (echo request out, echo reply in, port-closed abort).
PCMod = {
	Msg = function() end,
	Cfg = { DefaultTTL = 64 },
	Progs = {},
	OSys = {},
	Data = {},
}
util = { AddNetworkString = function() end }

function table.Copy( t )
	if (type( t ) != "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end

dofile( "pcmod_sh_icmp.lua" )

local ICMP = PCMod.ICMP
local function assertEq( a, b, msg )
	if (a != b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

-- Wire format. Both pings and traceroutes use an echo request.
local req = ICMP.Request( "p1", 1, 64 )
assertTrue( ICMP.Is( req ), "request is ICMP" )
assertTrue( ICMP.IsEcho( req ), "request is an echo" )
assertTrue( not ICMP.IsEchoReply( req ), "request is not a reply" )
assertTrue( not ICMP.IsTimeExceeded( req ), "request is not time-exceeded" )
assertEq( ICMP.Session( req ), "p1", "request keeps the session" )
assertEq( ICMP.Seq( req ), 1, "request keeps the sequence" )

local reply = ICMP.Reply( "p1", 1, "Host" )
assertTrue( ICMP.IsEchoReply( reply ), "reply is an echo reply" )
assertEq( ICMP.ReplyLabel( reply ), "Host", "reply carries the label" )

local expired = ICMP.Expired( 4, 2, "10.0.0.1", "BRTR" )
assertTrue( ICMP.IsTimeExceeded( expired ), "expired is time-exceeded" )
assertEq( ICMP.Session( expired ), 4, "expired keeps the trace handle" )
assertEq( ICMP.Address( expired ), "10.0.0.1", "expired carries the reporting address" )
assertEq( ICMP.ExpiredLabel( expired ), "BRTR", "expired carries the router label" )
assertTrue( not ICMP.Is( { "netPing", "hk" } ), "legacy ping body is not ICMP" )

-- OS ping path.
OS = {}
dofile( "pcmod_os_base.lua" )
function OS:DoPacket() end

local sent = {}
local net = {}
function net:SendPacket( dest, port, body, ttl )
	table.insert( sent, { dest = dest, port = port, body = body, ttl = ttl } )
	return true
end

local os = table.Copy( OS )
os.TraceRouteData = {}
os.PingData = {}
os.Progs = {}
os.NetPorts = { [ 0 ] = { Dest = "osbase" } }
os.Network = function() return net end

local pinged
local failed
os.Progs[ "nettools" ] = {
	PingSuccess = function( self, ip, label ) pinged = { ip = ip, label = label } end,
	MessageFailed = function( self, hdl, code, data ) failed = { code = code, data = data } end,
}

os:NetPing( "10.0.0.9", "nettools" )
assertEq( #sent, 1, "a ping sends one echo request" )
assertEq( sent[ 1 ].body[ 1 ], "icmp", "ping body is ICMP" )
assertEq( sent[ 1 ].body[ 2 ], "echo", "ping is an echo request" )
assertEq( sent[ 1 ].body[ 3 ], "p1", "ping uses a string session" )
assertEq( sent[ 1 ].body[ 4 ], 1, "ping sequence starts at one" )
assertEq( sent[ 1 ].ttl, nil, "ping uses the default TTL" )

os:ProcessPacket( 0, ICMP.Reply( "p1", 1, "Computer Tower OS" ), { "10.0.0.9", 0 } )
assertTrue( pinged ~= nil, "echo reply completes the ping" )
assertEq( pinged.ip, "10.0.0.9", "ping reports the responder" )
assertEq( pinged.label, "Computer Tower OS", "ping reports the responder label" )
assertTrue( os.PingData[ "p1" ] == nil, "ping state released on success" )

-- Sessions do not repeat, so a late reply cannot finish a newer ping.
os:NetPing( "10.0.0.9", "nettools" )
assertEq( sent[ #sent ].body[ 3 ], "p2", "second ping gets a fresh session" )
pinged = nil
os:ProcessPacket( 0, ICMP.Reply( "p1", 1, "Stale" ), { "10.0.0.9", 0 } )
assertTrue( pinged == nil, "late reply for an old ping is ignored" )

-- A host answers an echo request addressed to it.
local before = #sent
os:ProcessPacket( 0, ICMP.Request( "p7", 1, 64 ), { "10.0.0.1", 0, "10.0.0.9" } )
assertEq( #sent, before + 1, "host answers an incoming echo" )
assertEq( sent[ #sent ].body[ 2 ], "echo-reply", "host answer is an echo reply" )
assertEq( sent[ #sent ].body[ 3 ], "p7", "host answer keeps the session" )
assertEq( sent[ #sent ].body[ 5 ], "Computer Tower OS", "host answer carries the OS label" )

-- A closed port must still abort the owning program's ping. The ICMP body has
-- no program handle, so the OS resolves it from the probe state.
os:NetPing( "10.0.0.9", "nettools" )
local last = sent[ #sent ].body
os:ProcessPacket( 0, { "netPortClosed", last }, { "10.0.0.9", 0 } )
assertTrue( failed ~= nil, "port-closed reaches the ping's program" )
assertEq( failed.code, "netPortClosed", "port-closed code is preserved" )
assertTrue( os.PingData[ "p3" ] == nil, "port-closed releases the ping state" )

print( "ALL ICMP TESTS PASSED" )