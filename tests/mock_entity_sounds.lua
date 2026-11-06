-- Prop impact sound mock test (plain Lua after translation).
SERVER = true
CLIENT = false

function table.Count( t )
	local n = 0
	for _ in pairs( t ) do n = n + 1 end
	return n
end
function Msg() end
function IsValid( v ) return v != nil end
function CurTime() return 100 end
math.Clamp = function( v, lo, hi )
	if (v < lo) then return lo end
	if (v > hi) then return hi end
	return v
end

util = {}
util.GetSurfaceIndex = function( mat ) return mat end
util.GetSurfaceData = function( idx )
	if (idx == "metal") then return { impactHardSound = "physics/metal/metal_solid_impact_hard.wav" } end
	if (idx == "dirt") then return { impactSoftSound = "physics/plastic/plastic_box_impact_soft.wav" } end
	return nil
end

PCMod = {}
PCMod.Data = {}
PCMod.Cfg = {}
function AddCSLuaFile() end

dofile( "pcmod_sh_common.lua" )

// Keep sh_common's real helpers, but silence its logging for the harness.
PCMod.Msg = function() end

ENT = {}
dofile( "pcmod_shared.lua" )

local function assertEq( a, b, msg )
	if (a != b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (!v) then error( "FAILED: " .. msg, 2 ) end
end

local function makeEnt()
	local ent = setmetatable( {}, { __index = ENT } )
	ent.sounds = {}
	function ent:EmitSound( snd, level, pitch, volume )
		table.insert( self.sounds, { snd = snd, level = level, pitch = pitch, volume = volume } )
	end
	return ent
end

local physobj = { GetMaterial = function() return "metal" end }

// A hard collision emits the surface's hard impact sound.
local ent = makeEnt()
ent:PhysicsCollide( { Speed = 400 }, physobj )
assertEq( #ent.sounds, 1, "hard collision should emit one sound" )
assertEq( ent.sounds[1].snd, "physics/metal/metal_solid_impact_hard.wav", "hard impact sound" )
assertEq( ent.sounds[1].level, 75, "sound level" )
assertEq( ent.sounds[1].volume, 1, "full volume at high speed" )

// The cooldown suppresses a second impact immediately afterwards.
ent:PhysicsCollide( { Speed = 400 }, physobj )
assertEq( #ent.sounds, 1, "cooldown should suppress the second sound" )

// A slow bump is silent.
local slow = makeEnt()
slow:PhysicsCollide( { Speed = 50 }, physobj )
assertEq( #slow.sounds, 0, "slow collision should be silent" )

// Soft-only surfaces use the soft impact sound.
local soft = makeEnt()
soft:PhysicsCollide( { Speed = 200 }, { GetMaterial = function() return "dirt" end } )
assertEq( #soft.sounds, 1, "soft surface should emit one sound" )
assertEq( soft.sounds[1].snd, "physics/plastic/plastic_box_impact_soft.wav", "soft impact sound" )
assertTrue( soft.sounds[1].volume < 1, "soft impact volume scales with speed" )

// Unknown surfaces are silent and do not error.
local unknown = makeEnt()
unknown:PhysicsCollide( { Speed = 400 }, { GetMaterial = function() return "unknown" end } )
assertEq( #unknown.sounds, 0, "unknown surface should be silent" )

// A missing physics object is ignored.
local nophys = makeEnt()
nophys:PhysicsCollide( { Speed = 400 }, nil )
assertEq( #nophys.sounds, 0, "missing physics object should be silent" )

print( "mock_entity_sounds PASSED" )
