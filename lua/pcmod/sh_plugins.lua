
// ---------------------------------------------------------------------------------------------------------
// sh_plugins.lua - Revision 1
// Shared
// Loads plugin functionality
// ---------------------------------------------------------------------------------------------------------


// ---------------------------------------------------------------------------------------------------------
// Define core tables
// ---------------------------------------------------------------------------------------------------------

PCMod.Plugins = {}


// ---------------------------------------------------------------------------------------------------------
// RegisterPlugin - Adds a plugin to the master table
// ---------------------------------------------------------------------------------------------------------
function PCMod.RegisterPlugin( id, tbl )
	if (!id) then return end
	if (!tbl) then return end
	PCMod.Plugins[ id ] = table.Copy( tbl )
	PCMod.Msg( "Loaded plugin '" .. id .. "'!" )
end

// ---------------------------------------------------------------------------------------------------------
// CallHook - Calls a named handler on every plugin until one returns a value.
// The plugin table is passed as self, so plugins can keep state on themselves.
// ---------------------------------------------------------------------------------------------------------
function PCMod.CallHook( hookname, ... )
	if (!hookname) then return nil end
	local ids = {}
	for id, _ in pairs( PCMod.Plugins ) do table.insert( ids, id ) end
	table.sort( ids, function( a, b ) return tostring( a ) < tostring( b ) end )
	for _, id in ipairs( ids ) do
		local plugin = PCMod.Plugins[ id ]
		local handler = plugin && plugin[ hookname ]
		if (type( handler ) == "function") then
			local ok, result = pcall( handler, plugin, ... )
			if (!ok) then
				PCMod.Warning( "Plugin '" .. tostring( id ) .. "' failed in '" .. tostring( hookname ) .. "': " .. tostring( result ) )
			elseif (result != nil) then
				return result
			end
		end
	end
	return nil
end


// ---------------------------------------------------------------------------------------------------------
// Load all plugins
// ---------------------------------------------------------------------------------------------------------

for _, v in pairs( file.Find( "pcmod/plugins/*.lua", "LUA") ) do
	PLUGIN = {}
	local fn = "pcmod/plugins/" .. v
	PLUGIN.FileName = fn
	PLUGIN.Name = "base"
	if (SERVER) then AddCSLuaFile( fn ) end
	include( fn )
	PCMod.RegisterPlugin( PLUGIN.Name, PLUGIN )
end
PCMod.CallHook( "pre_load" )


// ---------------------------------------------------------------------------------------------------------
// Setup the timed delay
// ---------------------------------------------------------------------------------------------------------
timer.Create( "PCMod_TimedDelay", 5, 1, function()
	PCMod.CallHook( "timed_delay" )
end )