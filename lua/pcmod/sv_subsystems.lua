
// ---------------------------------------------------------------------------------------------------------
// sv_subsystems.lua
// Server-Side
// Loads the hardware subsystems (BIOS, display, network, router, ...).
// ---------------------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------------------------
// Define our library
// ---------------------------------------------------------------------------------------------------------

PCMod.Subsystems = {}
PCMod.Msg( "Loading hardware subsystems...", true )



// ---------------------------------------------------------------------------------------------------------
// Add the base file
// ---------------------------------------------------------------------------------------------------------

SUBSYSTEM = {}
include( "pcmod/subsystems/base.lua" )
PCMod.Subsystems[ "base" ] = table.Copy( SUBSYSTEM )
SUBSYSTEM = nil

function PCMod.DeriveSubsystem( name )
	local key = PCMod.ResolveSubsystemName( name or "base" ) or "base"
	local tmp = PCMod.Subsystems[ key ]
	if (!tmp) then tmp = {} end
	return table.Copy( tmp )
end


// ---------------------------------------------------------------------------------------------------------
// Loads all subsystems
// ---------------------------------------------------------------------------------------------------------

function PCMod.LoadAllSubsystems()
	local files = file.Find( "pcmod/subsystems/*.lua", "LUA" )
	if ((!files) || (table.Count( files ) == 0)) then
		PCMod.Error( "No subsystems to load!" )
		return
	end
	for _, v in ipairs( files ) do
		if (v != "base.lua") then PCMod.LoadSubsystem( v ) end
	end
end

// ---------------------------------------------------------------------------------------------------------
// Loads one subsystem. file is a name below pcmod/subsystems (network.lua).
// ---------------------------------------------------------------------------------------------------------

function PCMod.LoadSubsystem( file )
	if (!file) then return end
	file = tostring( file )
	if (file == "base.lua") then
		SUBSYSTEM = {}
		include( "pcmod/subsystems/base.lua" )
		PCMod.Subsystems[ "base" ] = table.Copy( SUBSYSTEM )
		SUBSYSTEM = nil
		return
	end
	SUBSYSTEM = PCMod.DeriveSubsystem( "base" )
	local fn = "pcmod/subsystems/" .. file
	SUBSYSTEM.FileName = fn
	include( fn )
	local key = PCMod.ResolveSubsystemName( SUBSYSTEM.Name )
	if ((!key) || (key == "base")) then
		PCMod.Warning( "Subsystem '" .. file .. "' has no name; skipped." )
		SUBSYSTEM = nil
		return
	end
	PCMod.Subsystems[ key ] = table.Copy( SUBSYSTEM )
	PCMod.Msg( "Loading subsystem '" .. key .. "'", true )
	SUBSYSTEM = nil
end
PCMod.LoadAllSubsystems()

// ---------------------------------------------------------------------------------------------------------
// Reload commands.
// ---------------------------------------------------------------------------------------------------------

function PCMod.ReloadSubsystem( pl, file )
	// Round 26 (M-12): in a concommand the player argument is NULL when the
	// command is typed in the SERVER CONSOLE - calling pl:IsAdmin() on NULL
	// raises "attempt to index a nil value". The server console is allowed.
	if (IsValid( pl ) && !pl:IsAdmin()) then
		PCMod.Notice( "You are not an admin!", pl )
		return
	end
	// SECURITY (stage 3, fix 2.1): validate the file name before include() sees it.
	local id = tostring( file or "" )
	if (!string.match( id, "^[%w_]+%.lua$" )) then return end
	if (!file.Exists( "pcmod/subsystems/" .. id, "LUA" )) then return end
	PCMod.LoadSubsystem( id )
end

function PCMod.ReloadAllSubsystems( pl )
	// Round 26 (M-12): NULL player = server console.
	if (IsValid( pl ) && !pl:IsAdmin()) then
		PCMod.Notice( "You are not an admin!", pl )
		return
	end
	PCMod.LoadAllSubsystems()
end

concommand.Add( "pc_subsystem_reload", function( pl, com, args )
	PCMod.ReloadSubsystem( pl, args[1] )
end )
concommand.Add( "pc_subsystem_reloadall", function( pl, com, args )
	PCMod.ReloadAllSubsystems( pl )
end )
