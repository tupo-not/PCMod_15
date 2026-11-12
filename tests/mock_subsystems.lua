-- Hardware-subsystem storage: canonical names and lazy store creation.
function string.Trim( s )
	return (string.gsub( s, "^%s*(.-)%s*$", "%1" ))
end
function string.Explode( sep, str )
	local out = {}
	if (str == nil) then return out end
	if (sep == "") then
		for i = 1, #str do table.insert( out, string.sub( str, i, i ) ) end
		return out
	end
	local start = 1
	while true do
		local a, b = string.find( str, sep, start, true )
		if (not a) then
			table.insert( out, string.sub( str, start ) )
			break
		end
		table.insert( out, string.sub( str, start, a - 1 ) )
		start = b + 1
	end
	return out
end
function string.Count( str, char )
	local r = 0
	for i = 1, #str do if (string.sub( str, i, i ) == char) then r = r + 1 end end
	return r
end
function table.Copy( t )
	if (type( t ) ~= "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end
function table.HasValue( t, v )
	for _, x in pairs( t ) do if (x == v) then return true end end
	return false
end
function istable( v ) return type( v ) == "table" end

PCMod = { Cfg = {}, Msg = function() end, Warning = function() end, Error = function() end }
dofile( "pcmod_sh_common.lua" )

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

assertEq( PCMod.ResolveSubsystemName( "network" ), "network", "canonical name is unchanged" )
assertEq( PCMod.ResolveSubsystemName( "NETWORK" ), "network", "names are case-insensitive" )
assertEq( PCMod.ResolveSubsystemName( nil ), nil, "nil has no subsystem name" )

-- Reading does not create a store.
local empty = {}
assertEq( PCMod.GetSubsystemStore( empty, false ), nil, "reading does not create a store" )
assertEq( PCMod.GetSubsystem( empty, "network" ), nil, "missing data has no subsystem" )

-- Creating a store installs it under the canonical field.
local data = {}
local store = PCMod.GetSubsystemStore( data, true )
assertTrue( store == data.Subsystems, "Subsystems field is the store" )
assertEq( data.Drivers, nil, "no secondary store field" )

store[ "network" ] = { id = "net" }
assertEq( PCMod.GetSubsystem( data, "network" ).id, "net", "subsystem is returned" )
assertEq( PCMod.GetSubsystem( data, "Network" ).id, "net", "lookup normalizes case" )
assertEq( PCMod.GetSubsystem( data, "gen_network" ), nil, "old names are not subsystem names" )
assertEq( PCMod.GetSubsystem( data, "unknown" ), nil, "unknown subsystem is nil" )

print( "mock_subsystems PASSED" )
