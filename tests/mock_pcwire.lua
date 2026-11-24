-- PCWire server entry points require the active tool, proximity, LOS and rate.
SERVER = true
CLIENT = false
TOOL = {}
handlers = {}
now = 100
function CurTime() return now end
function IsValid( ent ) return (ent != nil) && (ent.Valid ~= false) end
function IsFirstTimePredicted() return true end
game = { SinglePlayer = function() return false end }
cleanup = { Register = function() end }
util = { AddNetworkString = function() end }
net = {
	Receive = function( name, fn ) handlers[ name ] = fn end,
	ReadEntity = function() return table.remove( readq, 1 ) end,
	ReadUInt = function() return table.remove( readq, 1 ) end,
	ReadVector = function() return table.remove( readq, 1 ) end,
	ReadString = function() return table.remove( readq, 1 ) end,
	ReadFloat = function() return table.remove( readq, 1 ) end,
}
local function V( x )
	return setmetatable( { x = x }, { __sub = function( a, b )
		return { Length = function() return math.abs( a.x - b.x ) end }
	end } )
end
local function MakeEnt( idx )
	return {
		Valid = true, IsPCMod = true, Index = idx, Pos = V( 0 ),
		ports = { [ 1 ] = { Type = "network", Connected = false }, [ 2 ] = { Type = "network", Connected = false } },
		GetClass = function() return "pcmod_tower" end,
		GetPos = function( self ) return self.Pos end,
		Ports = function( self ) return self.ports end,
	}
end
local ply = {
	mode = "pcwire", los = true, Pos = V( 0 ),
	IsPlayer = function() return true end,
	GetTool = function( self )
		return { GetMode = function() return self.mode end }
	end,
	GetPos = function( self ) return self.Pos end,
	IsLineOfSightClear = function( self ) return self.los end,
}
PCMod = {
	Cfg = { ReachDistance = 256 },
	Notice = function() end,
	Wiring = {
		CreateRopeTable = function() return {} end,
		LinkPorts = function( a, ap, b, bp )
			a.ports[ ap ].Connected = true
			b.ports[ bp ].Connected = true
			links = (links || 0) + 1
			return true
		end,
		UnlinkPort = function()
			unlinks = (unlinks || 0) + 1
			return true
		end,
	},
}
function PC_BeamPorts() end
local entA, entB = MakeEnt( 1 ), MakeEnt( 2 )
dofile( "pcwire.lua" )

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local resetPair = true
local function Upload()
	if (resetPair) then
		entA, entB = MakeEnt( 1 ), MakeEnt( 2 )
		resetPair = false
	end
	readq = { entA, 1, entB, 2, V( 0 ), V( 0 ), "cable/rope", 2, 255, 210, 90 }
	handlers.pcwire_upload( 0, ply )
end

ply.mode = "other"
Upload()
assertEq( links || 0, 0, "inactive tool cannot create links" )
ply.mode = "pcwire"
Upload()
assertEq( links, 1, "active nearby tool creates a link" )
Upload()
assertEq( links, 1, "immediate duplicate is rate limited" )
now = now + 1
entB.Pos = V( 1000 )
Upload()
assertEq( links, 1, "distant endpoint is rejected" )
resetPair = true
entB.Pos = V( 0 )
now = now + 1
ply.los = false
Upload()
assertEq( links, 1, "blocked line of sight is rejected" )
ply.los = true
now = now + 1
resetPair = true
Upload()
assertEq( links, 2, "valid link works after the rate interval" )
readq = { entA, 1 }
handlers.pcwire_unlink( 0, ply )
assertEq( unlinks || 0, 0, "immediate unlink is rate limited" )
now = now + 1
readq = { entA, 1 }
handlers.pcwire_unlink( 0, ply )
assertEq( unlinks, 1, "valid unlink works" )

print( "mock_pcwire PASSED" )
