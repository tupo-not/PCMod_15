-- Plugin hook dispatch: handlers run in a stable order, failures are isolated,
-- and the first non-nil result is returned.
function table.Copy( t )
	if (type( t ) ~= "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end
SERVER = true
CLIENT = false
function AddCSLuaFile() end
file = { Find = function() return {} end }
timer = { Create = function() end }
PCMod = { Msg = function() end, Warning = function( msg ) warnings = warnings or {}; table.insert( warnings, msg ) end }

dofile( "pcmod_sh_plugins.lua" )

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

local calls = {}
PCMod.RegisterPlugin( "gamma", {
	pre_load = function() table.insert( calls, "gamma" ) end,
	post_load = function() table.insert( calls, "gamma" ) end,
} )
PCMod.RegisterPlugin( "beta", {
	pre_load = function() table.insert( calls, "beta" ) end,
	post_load = function( self, value )
		assertTrue( self.post_load ~= nil, "plugin table is self" )
		table.insert( calls, "beta" )
		return "beta-result"
	end,
} )
PCMod.RegisterPlugin( "alpha", {
	pre_load = function( self, value )
		table.insert( calls, "alpha" )
		assertEq( value, 42, "arguments are forwarded" )
	end,
	post_load = function() table.insert( calls, "alpha" ) end,
	broken = function()
		error( "intentional failure" )
	end,
} )

-- nil results continue to every plugin, in sorted id order.
assertEq( PCMod.CallHook( "pre_load", 42 ), nil, "no result means nil" )
assertEq( #calls, 3, "all plugins ran" )
assertEq( calls[ 1 ], "alpha", "plugins run in sorted id order" )
assertEq( calls[ 2 ], "beta", "sorted order continues" )
assertEq( calls[ 3 ], "gamma", "sorted order ends" )

-- A non-nil result stops dispatch.
calls = {}
assertEq( PCMod.CallHook( "post_load", 42 ), "beta-result", "first non-nil result is returned" )
assertEq( #calls, 2, "dispatch stops after the first result" )
assertEq( calls[ 2 ], "beta", "the result came from beta" )

-- Errors are caught and do not escape the hook dispatcher.
PCMod.CallHook( "broken" )
assertTrue( warnings && #warnings > 0, "plugin failure is reported" )

print( "mock_plugins PASSED" )
