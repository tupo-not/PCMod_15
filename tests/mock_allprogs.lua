-- All Programs menu state must be isolated per screen/PC.
function istable( v ) return type( v ) == "table" end
function IsValid( v ) return v ~= nil end
function string.Explode( sep, str )
	local out = {}
	local start = 1
	while true do
		local a, b = string.find( str, sep, start, true )
		if (!a) then table.insert( out, string.sub( str, start ) ) break end
		table.insert( out, string.sub( str, start, a - 1 ) )
		start = b + 1
	end
	return out
end

local receiver
local readEnt, readTable
net = {
	Receive = function( name, fn ) if (name == "programyolla") then receiver = fn end end,
	ReadEntity = function() return readEnt end,
	ReadTable = function() return readTable end,
}
DEV = {}
dofile( "pcmod_allprogs.lua" )
local prototype = DEV

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg ) if (!v) then error( "FAILED: " .. msg, 2 ) end end
local function shortcut( name ) return { "app", name, "sys_openprog " .. string.lower( name ) } end
local function makeMenu( progs, ent )
	local dev = {}
	for k, v in pairs( prototype ) do dev[ k ] = v end
	dev.Progs = progs
	dev.Entity = ent or {}
	dev.commands = {}
	function dev:CreateButton2() end
	function dev:SubmitCommand( ... ) self.commands[ #self.commands + 1 ] = { ... } end
	return dev
end

local a = makeMenu( { shortcut( "Alpha" ) } )
local b = makeMenu( { shortcut( "Beta" ) } )
a:Initialize( 0, 0, 1, 1 )
b:Initialize( 0, 0, 1, 1 )
a:ButtonClick( "btn_p_1" )
assertEq( #a.commands, 2, "menu A submits close + launch" )
assertEq( a.commands[ 2 ][ 2 ], "sys_openprog", "menu A keeps its command verb" )
assertEq( a.commands[ 2 ][ 3 ], "alpha", "opening B does not replace A shortcuts" )
b:ButtonClick( "btn_p_1" )
assertEq( b.commands[ 2 ][ 3 ], "beta", "menu B keeps its own shortcuts" )

-- Legacy entity payloads are isolated too; a later network update for another
-- PC must not change an already-created menu.
local entA, entB = {}, {}
local legacyA = makeMenu( nil, entA )
local legacyB = makeMenu( nil, entB )
readEnt, readTable = entA, { shortcut( "Alpha" ) }
receiver()
readEnt, readTable = entB, { shortcut( "Beta" ) }
receiver()
legacyA:Initialize( 0, 0, 1, 1 )
legacyB:Initialize( 0, 0, 1, 1 )
readEnt, readTable = entB, { shortcut( "BetaNew" ) }
receiver()
legacyA:ButtonClick( "btn_p_1" )
assertEq( legacyA.commands[ 2 ][ 3 ], "alpha", "legacy menu A is independent of B updates" )
assertTrue( entA.Programlar ~= entB.Programlar, "network payloads remain on their own entities" )

print( "mock_allprogs PASSED" )
