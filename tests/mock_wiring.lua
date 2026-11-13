-- Wiring invalid-port handling must fail cleanly instead of indexing nil.
PCMod = {
    Msg = function() end,
    Cfg = { WireTypes = {} },
}
dofile( "pcmod_wiring.lua" )

local ent = { IsPCMod = true }
function ent:IsValid() return true end
function ent:Ports() return {} end

local ok, result = pcall( PCMod.Wiring.UnlinkPort, ent, 99 )
if (not ok) then error( "FAILED: invalid unlink raised an error: " .. tostring( result ) ) end
if (result ~= false) then error( "FAILED: invalid unlink did not return false" ) end

-- A real unlink must report the destination's own port id to the destination
-- event; zeroing it first broke per-interface lease release.
local function makeEnt( ports, events )
    local e = { IsPCMod = true, ports = ports }
    function e:IsValid() return true end
    function e:Ports() return self.ports end
    function e:UpdatePort( i, p ) self.ports[ i ] = p end
    function e:FireEvent( ev ) table.insert( events, ev ) end
    return e
end

local eventsA, eventsB = {}, {}
local pA = { Type = "network", Connected = true, RemotePort = 2 }
local pB = { Type = "network", Connected = true, RemotePort = 1 }
local a = makeEnt( { pA }, eventsA )
local b = makeEnt( { [ 1 ] = false, [ 2 ] = pB }, eventsB )
pA.ConEnt = b
pB.ConEnt = a

local unlinked = PCMod.Wiring.UnlinkPort( a, 1 )
if (not unlinked) then error( "FAILED: valid unlink returned false" ) end
if (#eventsA ~= 1 or eventsA[ 1 ][ 1 ] ~= "unlinked") then error( "FAILED: source unlinked event missing" ) end
if (#eventsB ~= 1 or eventsB[ 1 ][ 1 ] ~= "unlinked") then error( "FAILED: destination unlinked event missing" ) end
if (eventsB[ 1 ][ 2 ] ~= 2) then
    error( "FAILED: destination event got port " .. tostring( eventsB[ 1 ][ 2 ] ) .. ", want 2" )
end

-- Only the cable end being clicked now must be in range. The first end was
-- selected earlier and may be behind the player, but a far second device must
-- still be rejected so the ray limit cannot be bypassed.
PCMod.Cfg.WireRange = 256
local vecmt = {}
vecmt.__index = {
    Length = function( self ) return math.sqrt( (self.x * self.x) + (self.y * self.y) + (self.z * self.z) ) end,
}
vecmt.__sub = function( a, b )
    return setmetatable( { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vecmt )
end
local function Vec( x, y, z ) return setmetatable( { x = x, y = y, z = z }, vecmt ) end
local function at( pos ) return { IsValid = function() return true end, GetPos = function() return pos end } end
local hub = at( Vec( 0, 0, 0 ) )
local far = at( Vec( 5000, 0, 0 ) )
local plyAtHub = { GetShootPos = function() return Vec( 32, 0, 0 ) end }
local plyAtFar = { GetShootPos = function() return Vec( 5000, 0, 0 ) end }
local plyNowhere = { GetShootPos = function() return Vec( 9000, 0, 0 ) end }

if (PCMod.Wiring.WithinReach( plyAtHub, hub, far )) then
    error( "FAILED: far second device accepted from the first device" )
end
if (not PCMod.Wiring.WithinReach( plyAtFar, hub, far )) then
    error( "FAILED: wiring rejected the second device while standing at it" )
end
if (not PCMod.Wiring.WithinReach( plyAtHub, far, hub )) then
    error( "FAILED: the first end's distance blocked the clicked end" )
end
if (PCMod.Wiring.WithinReach( plyNowhere, hub, far )) then
    error( "FAILED: wiring accepted while standing near neither device" )
end

-- 0 disables the check, so devices can be cabled from anywhere.
PCMod.Cfg.WireRange = 0
if (not PCMod.Wiring.WithinReach( plyNowhere, hub, far )) then
    error( "FAILED: unlimited wire range still rejected a cross-map cable" )
end

print( "ALL WIRING TESTS PASSED" )
