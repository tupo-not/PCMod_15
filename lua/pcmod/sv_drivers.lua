
// ---------------------------------------------------------------------------------------------------------
// sv_drivers.lua - Revision 1
// Server-Side
// Loads drivers
// ---------------------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------------------------
// Define our library
// ---------------------------------------------------------------------------------------------------------

PCMod.Drivers = {}
PCMod.Msg( "Loading all drivers...", true )



// ---------------------------------------------------------------------------------------------------------
// Add the base file
// ---------------------------------------------------------------------------------------------------------

DRV = {}
include( "pcmod/drivers/drv_base.lua" )
PCMod.Drivers[ "base" ] = table.Copy( DRV )

function PCMod.DeriveDriver( dname )
	local tmp = PCMod.Drivers[ dname ]
	if (!tmp) then tmp = {} end
	return table.Copy( tmp )
end


// ---------------------------------------------------------------------------------------------------------
// Loads all drivers
// ---------------------------------------------------------------------------------------------------------

function PCMod.LoadAllDrivers()
	// ---------------------------------------------------------------------------------------------------------
	// Get driver file list
	// ---------------------------------------------------------------------------------------------------------

	local files = file.Find( "pcmod/drivers/drv_*", "LUA")
	if ((!files) || (table.Count( files ) == 0)) then
		PCMod.Error( "No drivers to load!" )
		return
	end
	for k, v in pairs( files ) do
		PCMod.LoadDriver( v )
	end
end

// ---------------------------------------------------------------------------------------------------------
// Loads selected driver
// ---------------------------------------------------------------------------------------------------------

function PCMod.LoadDriver( driver )
	DRV = {}
	if (driver == "base") then
		include( "pcmod/drivers/drv_base.lua" )
		PCMod.Drivers[ "base" ] = table.Copy( DRV )
		return
	end
	DRV.Name = ""
	local fn = "pcmod/drivers/" .. driver
	DRV.FileName = fn
	
	include( fn )
	
	PCMod.Drivers[ DRV.Name ] = table.Copy( DRV )
	
	PCMod.Msg( "Loading driver '" .. DRV.Name .. "'", true )
end
PCMod.LoadAllDrivers()

concommand.Add( "pc_drv_reload", function( pl, com, args )
	// Round 26 (M-12): in a concommand the player argument is NULL when the
	// command is typed in the SERVER CONSOLE - calling pl:IsAdmin() on NULL
	// raises "attempt to index a nil value". The server console is allowed
	// (same pattern as pc_prog_reload / pc_sv_debugmode).
	if (IsValid( pl ) && !pl:IsAdmin()) then
		PCMod.Notice( "You are not an admin!", pl )
		return
	end
	// SECURITY (stage 3, fix 2.1): validate the driver file name the same way
	// pc_prog_reload / pc_os_reload do, before include() sees it.
	local id = args[1]
	if (!id || !string.match( id, "^[%w_]+%.lua$")) then return end
	if (!file.Exists( "pcmod/drivers/" .. id, "LUA" )) then return end
	PCMod.LoadDriver( id )
end )
concommand.Add( "pc_drv_reloadall", function( pl, com, args )
	// Round 26 (M-12): NULL player = server console - see pc_drv_reload above.
	if (IsValid( pl ) && !pl:IsAdmin()) then
		PCMod.Notice( "You are not an admin!", pl )
		return
	end
	PCMod.LoadAllDrivers()
end )