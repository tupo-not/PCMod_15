-- OS shutdown must not leave runtime network state behind.
PCMod = { Cfg = {}, Msg = function() end }
util = { AddNetworkString = function() end }
OS = {}

dofile( "pcmod_os_base.lua" )

local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

local exited = {}
OS.Progs = {
	a = { Exit = function() table.insert( exited, "a" ) end },
	b = { Exit = function() table.insert( exited, "b" ) end },
	c = {},
}
OS.NetPorts = { [ 0 ] = { Dest = "osbase" }, [ 80 ] = { Dest = "prog" } }
OS.TraceRouteData = { [ 1 ] = { Dest = "10.0.0.1" } }
OS.State = 10
OS.NUpdate = 42
OS.Mode = "bios"

OS:ShutDown()

assertTrue( #exited == 2, "every program with Exit is closed" )
assertTrue( next( OS.Progs ) == nil, "program instances are dropped" )
assertTrue( next( OS.NetPorts ) == nil, "net ports are closed" )
assertTrue( next( OS.TraceRouteData ) == nil, "trace handles are dropped" )
assertTrue( OS.State == 0 and OS.NUpdate == 0, "boot state is reset" )
assertTrue( OS.Mode == nil, "OS no longer claims an active mode" )

print( "ALL OS SHUTDOWN TESTS PASSED" )
