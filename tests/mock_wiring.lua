-- Wiring invalid-port handling, PCMod-owned ropes and unlink cleanup.
PCMod = {
	Msg = function() end,
	Cfg = { WireTypes = {} },
}
function IsValid( ent ) return (ent != nil) && (ent.Valid ~= false) end
local lastRope
constraint = {
	Rope = function( ... )
		local args = { ... }
		lastRope = args
		local const = {
			Type = "Rope", Ent1 = args[ 1 ], Ent2 = args[ 2 ],
			Bone1 = args[ 3 ], Bone2 = args[ 4 ], LPos1 = args[ 5 ], LPos2 = args[ 6 ],
			length = args[ 7 ], addlength = args[ 8 ], forcelimit = args[ 9 ],
			width = args[ 10 ], material = args[ 11 ], rigid = args[ 12 ], color = args[ 13 ],
		}
		local rope = {}
		for _, ent in ipairs( { const, rope } ) do
			function ent:IsValid() return self.Valid ~= false end
			function ent:Remove() self.Valid = false self.Removed = true end
		end
		return const, rope
	end,
}
dofile( "pcmod_wiring.lua" )

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg ) if (!v) then error( "FAILED: " .. msg, 2 ) end end
local function makeEnt( idx )
	local ent = { IsPCMod = true, Index = idx, ports = { [ idx ] = {} }, events = {} }
	function ent:IsValid() return true end
	function ent:Ports() return self.ports end
	function ent:UpdatePort( id, data ) self.ports[ id ] = data end
	function ent:FireEvent( event ) self.events[ #self.events + 1 ] = event end
	return ent
end

local ent = { IsPCMod = true }
function ent:IsValid() return true end
function ent:Ports() return {} end
local ok, result = pcall( PCMod.Wiring.UnlinkPort, ent, 99 )
assertTrue( ok, "invalid unlink does not raise" )
assertEq( result, false, "invalid unlink returns false" )

local a, b = makeEnt( 1 ), makeEnt( 2 )
local ropeTable = PCMod.Wiring.CreateRopeTable( a, b, {
	lpos1 = "A1", lpos2 = "B2", length = 120, width = 2, material = "cable/rope",
} )
assertEq( #ropeTable, 1, "rope table keeps the legacy nested shape" )
local const, visual = ropeTable[ 1 ][ 1 ], ropeTable[ 1 ][ 2 ]
assertEq( const.Type, nil, "PCMod-owned constraint is hidden from generic dupe" )
assertEq( lastRope[ 7 ], 120, "rope length is preserved" )
local forward = PCMod.Wiring.GetRopeData( ropeTable, a )
local reverse = PCMod.Wiring.GetRopeData( ropeTable, b )
assertTrue( forward && reverse, "rope parameters serialize from either endpoint" )
assertEq( forward.lpos1, "A1", "forward local attachment 1" )
assertEq( forward.lpos2, "B2", "forward local attachment 2" )
assertEq( reverse.lpos1, "B2", "reverse attachment order follows the owner" )
assertEq( reverse.lpos2, "A1", "reverse attachment order follows the peer" )
const.Type = "Rope"
assertEq( PCMod.Wiring.GetRopeData( ropeTable, a ), nil, "legacy generic rope is not manually duplicated" )
const.Type = nil

assertTrue( PCMod.Wiring.LinkPorts( a, 1, b, 2, ropeTable ), "ports link with a rope" )
assertTrue( PCMod.Wiring.UnlinkPort( a, 1 ), "linked ports unlink" )
assertTrue( const.Removed && visual.Removed, "unlink removes both constraint and visual rope" )
assertTrue( !a.ports[ 1 ].Connected && !b.ports[ 2 ].Connected, "unlink clears both logical ports" )

print( "ALL WIRING TESTS PASSED" )
