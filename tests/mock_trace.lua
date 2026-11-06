-- TTL-based traceroute state machine: the OS sends a probe with TTL 1, a
-- router reports itself when the TTL expires, and the OS retries with the next
-- TTL until the destination answers.
PCMod = {
	Msg = function() end,
	Cfg = { DefaultTTL = 64, TraceMaxHops = 30 },
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

OS = {}
dofile( "pcmod_os_base.lua" )
function OS:DoPacket() end

local function assertEq( a, b, msg )
	if (a != b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end

local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

local sent = {}
local net = {}
function net:SendPacket( dest, port, body, ttl )
	table.insert( sent, { dest = dest, port = port, body = body, ttl = ttl } )
	return true
end

local os = table.Copy( OS )
os.TraceRouteData = {}
os.Progs = {}
os.NetPorts = {}
os.Network = function() return net end

local done
function os:TraceSuccess( ip, trace )
	done = { ip = ip, trace = trace }
end

-- Initial probe: TTL 1, carrying the trace handle and probe number.
os:NetTrace( "10.0.1.4", "os" )
assertEq( #sent, 1, "traceroute starts with one probe" )
assertEq( sent[ 1 ].body[ 1 ], "netTrace", "probe body type" )
assertEq( sent[ 1 ].body[ 3 ], 1, "probe carries the trace handle" )
assertEq( sent[ 1 ].body[ 4 ], 1, "first probe carries TTL 1" )
assertEq( sent[ 1 ].ttl, 1, "first probe is sent with TTL 1" )

-- Hop 1 expired at the first router: record it and probe again with TTL 2.
os:ProcessPacket( 0, { "netTraceHop", "os", 1, "192.168.5.1", "RTR", 1 }, { "192.168.5.1", 0 } )
assertEq( #sent, 2, "a hop report triggers the next probe" )
assertEq( sent[ 2 ].body[ 4 ], 2, "second probe carries TTL 2" )
assertEq( sent[ 2 ].ttl, 2, "second probe is sent with TTL 2" )

-- Hop 2 expired at the backbone router.
os:ProcessPacket( 0, { "netTraceHop", "os", 1, "10.0.1.1", "BRTR", 2 }, { "10.0.1.1", 0 } )
assertEq( #sent, 3, "second hop report triggers the third probe" )
assertEq( sent[ 3 ].ttl, 3, "third probe is sent with TTL 3" )

-- The destination is a router and answers as the final hop.
os:ProcessPacket( 0, { "netTraceResponse", "os", 1, "Router" }, { "10.0.1.4", 0 } )
assertTrue( done ~= nil, "destination response completes the trace" )
assertEq( done.ip, "10.0.1.4", "trace reports the destination address" )
assertEq( done.trace[ 1 ], "192.168.5.1 - RTR", "hop 1 result" )
assertEq( done.trace[ 2 ], "10.0.1.1 - BRTR", "hop 2 result" )
assertEq( done.trace[ 3 ], "10.0.1.4 - Router", "final hop result" )
assertTrue( os.TraceRouteData[ 1 ] == nil, "trace state released on completion" )
assertEq( #sent, 3, "no probe is sent after the destination answers" )

-- A late hop report for a finished trace is ignored.
os:ProcessPacket( 0, { "netTraceHop", "os", 1, "10.0.9.9", "RTR", 9 }, { "10.0.9.9", 0 } )
assertEq( #sent, 3, "late hop report ignored" )

print( "ALL TRACE CHECKS TESTS PASSED" )
