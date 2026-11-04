
// ---------------------------------------------------------------------------------------------------------
// sv_programs.lua - Revision 1
// Server-Side
// Loads and controls tower programs
// ---------------------------------------------------------------------------------------------------------


// ---------------------------------------------------------------------------------------------------------
// Define core tables
// ---------------------------------------------------------------------------------------------------------

PCMod.Progs = {}

PCMod.Msg( "Preparing to load all programs...", true )


// ---------------------------------------------------------------------------------------------------------
// Define the loading function
// ---------------------------------------------------------------------------------------------------------

function PCMod.Progs.Load( id )

	if (id == "base") then
		PROG = {}
		include( "pcmod/programs/base.lua" )
		PCMod.Progs[ "base" ] = table.Copy( PROG )
		PCMod.Msg( "Base program loaded!", true )
		return
	end
	local fn = "pcmod/programs/" .. id
	PROG = {}
	PROG = table.Copy( PCMod.Progs[ "base" ] )
	PROG.FileName = fn
	include( fn )
	PCMod.Progs[ PROG.Name ] = table.Copy( PROG )
	PCMod.Progs[ PROG.Name ]:Initialize()
	PCMod.Msg( "Program '" .. PROG.Name .. "' loaded!" )
end

concommand.Add( "pc_prog_reload", function( pl, com, args )
	if (IsValid( pl ) && !pl:IsAdmin()) then return end
	local id = args[1]
	if (!id || !string.match( id, "^[%w_]+%.lua$")) then return end
	if (!file.Exists( "pcmod/programs/" .. id, "LUA" )) then return end
	PCMod.Progs.Load( id )
end )

// ---------------------------------------------------------------------------------------------------------
// pc_prog_check - Compiles a program file without running it and reports syntax errors
// ---------------------------------------------------------------------------------------------------------
// CompileString understands GLua additions such as // comments and !/&&/||,
// so it is the only reliable way to validate a program file from inside GMod.
concommand.Add( "pc_prog_check", function( pl, com, args )
	local function Reply( text )
		if (IsValid( pl )) then PCMod.Notice( text, pl ) end
		// Always echo to the console too, otherwise the check is silent when
		// it is run from the server console (where pl is NULL).
		PCMod.Msg( text )
	end
	if (IsValid( pl ) && !pl:IsAdmin()) then
		PCMod.Notice( "You are not an admin!", pl )
		return
	end
	local id = args[1]
	if (!id) then
		Reply( "Usage: pc_prog_check <program.lua>" )
		return
	end
	if (!string.match( id, "^[%w_]+%.lua$")) then
		Reply( "Invalid program filename." )
		return
	end
	local path = "pcmod/programs/" .. id
	if (!file.Exists( path, "LUA" )) then
		Reply( "Program file not found: " .. path )
		return
	end
	local src = file.Read( path, "LUA" )
	if (!src) then
		Reply( "Could not read " .. path )
		return
	end
	local fn, err = CompileString( src, path, false )
	if (!fn) then
		Reply( "Syntax error in " .. id .. ": " .. tostring( err ) )
	else
		Reply( "No syntax errors found in " .. id .. "." )
	end
end )


// ---------------------------------------------------------------------------------------------------------
// Load the base program
// ---------------------------------------------------------------------------------------------------------

PROG = {}
PCMod.Progs.Load( "base" )


// ---------------------------------------------------------------------------------------------------------
// Load all other programs
// ---------------------------------------------------------------------------------------------------------

for _, v in pairs( file.Find( "pcmod/programs/pr_*", "LUA") ) do
	PROG = {}
	PCMod.Progs.Load( v )
end