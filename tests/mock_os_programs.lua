-- OS boot restores program instances from the saved start-menu list.
PCMod = {
	Msg = function() end,
	Cfg = {},
	Progs = {},
	TableToString = function( t ) return t end,
	StringToTable = function( s ) return s end,
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

local function assertEq( a, b, m )
	if (a != b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
	if (not v) then error( "FAILED: " .. m, 2 ) end
end

local function makeProg( name, osname, usable )
	return {
		Name = name,
		OS = osname,
		CanUse = function() return usable != false end,
		OnInstall = function( self ) self.Installed = true end,
	}
end

PCMod.Progs[ "mycomputer" ] = makeProg( "mycomputer", "personal" )
PCMod.Progs[ "files" ] = makeProg( "files", "personal" )
PCMod.Progs[ "nettools" ] = makeProg( "nettools", "personal" )
PCMod.Progs[ "nettools" ].NoShortcut = true
PCMod.Progs[ "deviceman" ] = makeProg( "deviceman", "personal" )
PCMod.Progs[ "deviceman" ].NoShortcut = true
PCMod.Progs[ "serverhidden" ] = makeProg( "serverhidden", "server" )
PCMod.Progs[ "serverhidden" ].NoShortcut = true
PCMod.Progs[ "serverprog" ] = makeProg( "serverprog", "server" )
PCMod.Progs[ "broken" ] = makeProg( "broken", "personal", false )
-- PCMod.Progs also carries helper functions (sv_programs.lua adds Load).
PCMod.Progs.Load = function() end

local list = {
	{ "app", "Control Panel", "sys_openprog mycomputer" },
	{ "app", "Files", "sys_openprog files" },
	{ "app", "Other OS", "sys_openprog serverprog" },
	{ "app", "Missing", "sys_openprog nope" },
	{ "app", "Broken", "sys_openprog broken" },
}
local ent = {}
function ent:ReadFile( fn )
	if (fn == "system/data/allprogs.dat") then return list end
	return nil
end

local os = {}
for k, v in pairs( OS ) do os[ k ] = v end
os.IntName = "personal"
os.Progs = {}
os.Entity = ent

-- The runtime table starts empty, as it does on a freshly booted/duplicated PC.
assertEq( os.Progs[ "mycomputer" ], nil, "no programs before restore" )
os:LoadPrograms()
assertTrue( os.Progs[ "mycomputer" ] != nil, "control panel restored from allprogs" )
assertTrue( os.Progs[ "files" ] != nil, "files restored from allprogs" )
assertTrue( os.Progs[ "serverprog" ] == nil, "other OS program rejected" )
assertTrue( os.Progs[ "nope" ] == nil, "missing program skipped" )
assertTrue( os.Progs[ "broken" ] == nil, "unusable program skipped" )
assertTrue( os.Progs[ "nettools" ] != nil, "NoShortcut sub-program restored" )
assertTrue( os.Progs[ "deviceman" ] != nil, "NoShortcut control-panel program restored" )
assertTrue( os.Progs[ "serverhidden" ] == nil, "NoShortcut for another OS rejected" )
assertTrue( os.Progs[ "mycomputer" ].Entity == ent, "restored program bound to the PC" )
assertTrue( os.Progs[ "mycomputer" ] != PCMod.Progs[ "mycomputer" ], "program is an instance, not the prototype" )
assertTrue( os.Progs[ "mycomputer" ].Installed == nil, "OnInstall is not run again" )

-- Running programs survive a later state change (only missing ones are added).
local running = os.Progs[ "mycomputer" ]
running.Running = true
os:LoadPrograms()
assertTrue( os.Progs[ "mycomputer" ] == running, "existing program instance kept" )
assertTrue( os.Progs[ "mycomputer" ].Running == true, "existing program state kept" )

-- The server OS saves bare program names instead of sys_openprog commands.
local slist = { { "app", "Server", "serverprog" } }
function ent:ReadFile( fn )
	if (fn == "system/data/allprogs.dat") then return slist end
	return nil
end
local sos = {}
for k, v in pairs( OS ) do sos[ k ] = v end
sos.IntName = "server"
sos.Progs = {}
sos.Entity = ent
sos:LoadPrograms()
assertTrue( sos.Progs[ "serverprog" ] != nil, "bare command name restored" )

-- A PC with no saved program list simply has nothing to restore.
function ent:ReadFile( fn ) return nil end
local eos = {}
for k, v in pairs( OS ) do eos[ k ] = v end
eos.IntName = "personal"
eos.Progs = {}
eos.Entity = ent
eos:LoadPrograms()
assertTrue( eos.Progs[ "mycomputer" ] == nil, "no saved list leaves shortcuts empty" )
assertTrue( eos.Progs[ "nettools" ] != nil, "NoShortcut programs still available without a saved list" )

print( "ALL OS PROGRAM TESTS PASSED" )
