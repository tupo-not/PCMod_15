-- mock_install.lua: server-side OS:InstallProgram checks used by the install
-- disk: no running OS, invalid program, duplicate install, program/OS type
-- compatibility (personal vs server), setup bypass, and successful install.
PCMod = { Msg = function() end, Progs = {}, OSys = {}, Data = {} }
util = { AddNetworkString = function() end }

function table.Copy( t )
	if (type( t ) != "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end

OS = {}
dofile( "pcmod_os_base.lua" )

local function assertEq( a, b, msg )
	if (a != b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")" ) end
end

local function newOS( intname, state )
	local os = table.Copy( OS )
	os.IntName = intname
	os.State = state
	os.Progs = {}
	os.Entity = { EntIndex = function() return 1 end, IsValid = function() return true end }
	return os
end

PCMod.Progs[ "myprog" ] = { OS = "personal", CanUse = function() return true end, OnInstall = function() end }
PCMod.Progs[ "srvprog" ] = { OS = "server", CanUse = function() return true end, OnInstall = function() end }

-- B: no running OS (State != 10) blocks normal installs...
local os = newOS( "personal", 5 )
assertEq( os:InstallProgram( "myprog" ), "Installation denied!", "install blocked without running OS" )
-- ...but the initial OS setup itself must not be blocked
assertEq( os:InstallProgram( "myprog", true ), true, "setup bypass allowed" )

-- invalid program name
os = newOS( "personal", 10 )
assertEq( os:InstallProgram( "nope" ), "Installation invalid!", "invalid program rejected" )
assertEq( os.Progs[ "nope" ] != nil, false, "invalid program not registered" )

-- successful install registers the program
assertEq( os:InstallProgram( "myprog" ), true, "successful install" )
assertEq( os.Progs[ "myprog" ] != nil, true, "program present after install" )

-- C: duplicate install rejected without duplicating
assertEq( os:InstallProgram( "myprog" ), "Program already installed!", "duplicate rejected" )
local cnt = 0
for k in pairs( os.Progs ) do cnt = cnt + 1 end
assertEq( cnt, 1, "no duplicate program entries" )

-- A: server program on a personal OS and vice versa are rejected by category
assertEq( os:InstallProgram( "srvprog" ), "Wrong operating system!", "server prog on personal OS rejected" )
local sos = newOS( "server", 10 )
assertEq( sos:InstallProgram( "myprog" ), "Wrong operating system!", "personal prog on server OS rejected" )
assertEq( sos:InstallProgram( "srvprog" ), true, "server prog on server OS ok" )

print( "ALL INSTALL CHECKS TESTS PASSED" )
