-- Network Tester must reselect when its first entity has been removed.
SERVER = true
CLIENT = false
SWEP = { Primary = {}, Secondary = {} }
function AddCSLuaFile() end
function IsValid( ent ) return (ent != nil) && ent:IsValid() end
dofile( "pcmod_networktester.lua" )

local function makeEnt( idx )
	local ent = { IsPCMod = true, Index = idx, Valid = true }
	function ent:IsValid() return self.Valid end
	function ent:EntIndex() return self.Index end
	function ent:Ports() return {} end
	function ent:GetFullIP() return "192.168.0." .. tostring( idx ) end
	return ent
end
local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end

local target
local weapon = {}
for k, v in pairs( SWEP ) do weapon[ k ] = v end
weapon.Owner = {
	GetEyeTrace = function() return { Entity = target } end,
	PrintMessage = function() end,
}
local called
function weapon:DoStuff( a, b ) called = { a, b } end

local a, b, c = makeEnt( 1 ), makeEnt( 2 ), makeEnt( 3 )
target = a
weapon:PrimaryAttack()
assertEq( weapon.EntA, a, "first valid entity becomes A" )
a.Valid = false
called = nil
target = b
weapon:PrimaryAttack()
assertEq( weapon.EntA, b, "removed A is discarded and B becomes the new A" )
assertEq( called, nil, "invalid A never reaches DoStuff" )
target = c
weapon:PrimaryAttack()
if (!called || called[ 1 ] ~= b || called[ 2 ] ~= c) then error( "FAILED: second click uses the replacement A and C", 2 ) end
assertEq( weapon.EntA, nil, "successful pair selection resets state" )

print( "mock_networktester PASSED" )
