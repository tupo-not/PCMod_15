-- Server-side pcwire handlers must not trust a client that skips the tool.
SERVER = true
CLIENT = false
ToolOnly = true
game = { SinglePlayer = function() return false end }
TOOL = {}

local handlers = {}
util = { AddNetworkString = function() end }
net = { Receive = function( name, fn ) handlers[ name ] = fn end }

local reads = {}
local function queue( ... )
	reads = { ... }
end
net.ReadEntity = function() return table.remove( reads, 1 ) end
net.ReadUInt = function() return table.remove( reads, 1 ) end
net.ReadVector = function() return table.remove( reads, 1 ) end
net.ReadString = function() return table.remove( reads, 1 ) end
net.ReadFloat = function() return table.remove( reads, 1 ) end

function IsValid( e ) return (e ~= nil) and (e.valid ~= false) end
function math.Clamp( v, lo, hi ) if (v < lo) then return lo end if (v > hi) then return hi end return v end

local now = 0
function CurTime() return now end

local function vec( x, y, z )
	local v = { x = x or 0, y = y or 0, z = z or 0 }
	function v:Length() return math.sqrt( self.x * self.x + self.y * self.y + self.z * self.z ) end
	return setmetatable( v, { __sub = function( a, b )
		return vec( a.x - b.x, a.y - b.y, a.z - b.z )
	end } )
end

local function weapon( mode )
	local w = { valid = true, mode = mode }
	function w:IsValid() return true end
	function w:GetClass() return "gmod_tool" end
	function w:GetMode() return self.mode end
	return w
end

local function player( wep, pos )
	local p = { valid = true, wep = wep, pos = pos or vec( 0, 0, 0 ) }
	function p:IsPlayer() return true end
	function p:IsValid() return true end
	function p:GetActiveWeapon() return self.wep end
	function p:GetShootPos() return self.pos end
	function p:GetPos() return self.pos end
	return p
end

local function entity( id, pos, ports )
	local e = { valid = true, id = id, pos = pos or vec( 0, 0, 0 ), ports = ports or {}, IsPCMod = true }
	function e:IsValid() return true end
	function e:EntIndex() return self.id end
	function e:GetPos() return self.pos end
	function e:Ports() return self.ports end
	function e:GetClass() return "pcmod_tower" end
	return e
end

local beams = 0
function PC_BeamPorts() beams = beams + 1 end

local linked = false
local wireRange = 256
PCMod = {
	Cfg = { ReachDistance = 256, WireTypes = { { Name = "network", SameType = false } } },
	Notice = function() end,
	Wiring = {
		LinkPorts = function( e1, p1, e2, p2 )
			local a = e1:Ports()[ p1 ]
			local b = e2:Ports()[ p2 ]
			if (a) then a.Connected = true end
			if (b) then b.Connected = true end
			linked = true
			return true
		end,
		WireRange = function() return wireRange end,
	},
}
constraint = { Rope = function() return "const", "rope" end }

dofile( "pcwire.lua" )

local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

assertTrue( handlers[ "pcmod_reqports" ] ~= nil, "reqports handler registered" )
assertTrue( handlers[ "pcwire_unlink" ] ~= nil, "unlink handler registered" )
assertTrue( handlers[ "pcwire_upload" ] ~= nil, "upload handler registered" )

local ent = entity( 1, vec( 0, 0, 0 ) )

-- A client without the wiring tool cannot scan ports.
queue( ent )
beams = 0
handlers[ "pcmod_reqports" ]( 0, player( weapon( "other" ), vec( 0, 0, 0 ) ) )
assertTrue( beams == 0, "non-tool client cannot request ports" )

-- The tool alone is not enough: the entity must be within reach.
queue( ent )
beams = 0
handlers[ "pcmod_reqports" ]( 0, player( weapon( "pcwire" ), vec( 1000, 0, 0 ) ) )
assertTrue( beams == 0, "out-of-reach entity is rejected" )

-- An honest request works.
queue( ent )
beams = 0
local p = player( weapon( "pcwire" ), vec( 0, 0, 0 ) )
handlers[ "pcmod_reqports" ]( 0, p )
assertTrue( beams == 1, "in-range tool request is accepted" )

-- ...and is rate limited.
queue( ent )
beams = 0
handlers[ "pcmod_reqports" ]( 0, p )
assertTrue( beams == 0, "repeated request is rate limited" )

-- Uploads reject out-of-reach endpoints before touching the wire.
local e1 = entity( 2, vec( 0, 0, 0 ), { { Type = "network", Connected = false } } )
local e2 = entity( 3, vec( 10, 0, 0 ), { { Type = "network", Connected = false } } )
local function uploadReads( a, b, l1, l2, mat )
	queue( a, 1, b, 1, l1, l2, mat or "cable/rope", 2, 255, 210, 90 )
end
local far = player( weapon( "pcwire" ), vec( 1000, 0, 0 ) )
uploadReads( e1, e2, vec(), vec() )
linked = false
handlers[ "pcwire_upload" ]( 0, far )
assertTrue( not linked, "out-of-reach upload is rejected" )

-- A normal upload links the ports.
now = 10
local near = player( weapon( "pcwire" ), vec( 0, 0, 0 ) )
uploadReads( e1, e2, vec(), vec() )
linked = false
handlers[ "pcwire_upload" ]( 0, near )
assertTrue( linked, "in-range upload links the ports" )

-- Wild local cable coordinates are clamped away.
now = 20
local near2 = player( weapon( "pcwire" ), vec( 0, 0, 0 ) )
uploadReads( e1, e2, vec( 900, 0, 0 ), vec() )
linked = false
handlers[ "pcwire_upload" ]( 0, near2 )
assertTrue( not linked, "absurd cable endpoint is rejected" )

-- Oversized material strings are rejected.
now = 30
local near3 = player( weapon( "pcwire" ), vec( 0, 0, 0 ) )
uploadReads( e1, e2, vec(), vec(), string.rep( "x", 200 ) )
linked = false
handlers[ "pcwire_upload" ]( 0, near3 )
assertTrue( not linked, "oversized material string is rejected" )

-- A long cable is valid: the player picks the first port while standing at
-- one device, then walks to the other. The first end is out of reach by then.
now = 40
local farA = entity( 4, vec( 0, 0, 0 ), { { Type = "network", Connected = false } } )
local farB = entity( 5, vec( 5000, 0, 0 ), { { Type = "network", Connected = false } } )
local atB = player( weapon( "pcwire" ), vec( 5000, 0, 0 ) )
uploadReads( farA, farB, vec(), vec() )
linked = false
handlers[ "pcwire_upload" ]( 0, atB )
assertTrue( linked, "long cable accepted when standing at the second device" )

-- A rapid burst of links is not silently dropped by the upload rate limit.
-- Rejected/duplicate uploads must not consume the burst either: hammer an
-- already-connected link first, then create a full hub's worth of fresh ones.
now = 45
local spam = player( weapon( "pcwire" ), vec( 0, 0, 0 ) )
for _ = 1, 40 do
	uploadReads( e1, e2, vec(), vec() )
	handlers[ "pcwire_upload" ]( 0, spam )
end
now = 50
local burstPlayer = player( weapon( "pcwire" ), vec( 0, 0, 0 ) )
local accepted = 0
local burstCount = 24
for i = 1, burstCount do
	local a = entity( 100 + i, vec( 0, 0, 0 ), { { Type = "network", Connected = false } } )
	local b = entity( 200 + i, vec( 10, 0, 0 ), { { Type = "network", Connected = false } } )
	uploadReads( a, b, vec(), vec() )
	linked = false
	handlers[ "pcwire_upload" ]( 0, burstPlayer )
	if (linked) then accepted = accepted + 1 end
end
assertTrue( accepted == burstCount, "a burst of " .. burstCount .. " links is accepted after rejected uploads" )

-- pcmod_wire_maxdist 0 removes the distance check: wire from anywhere.
wireRange = 0
now = 60
local cmA = entity( 30, vec( 0, 0, 0 ), { { Type = "network", Connected = false } } )
local cmB = entity( 31, vec( 20000, 0, 0 ), { { Type = "network", Connected = false } } )
local anywhere = player( weapon( "pcwire" ), vec( 9000, 0, 0 ) )
uploadReads( cmA, cmB, vec(), vec() )
linked = false
handlers[ "pcwire_upload" ]( 0, anywhere )
assertTrue( linked, "unlimited wire range allows a cross-map cable" )
wireRange = 256

print( "ALL PCWIRE SECURITY TESTS PASSED" )
