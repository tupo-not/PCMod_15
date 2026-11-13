-- Packet id recycling must never overwrite an in-flight packet.
PCMod = {
    Msg = function() end,
    Cfg = { MaxNetworkPid = 3 },
    IPv6 = {
        ToIPv4 = function( addr ) return addr end,
        FromIPv4 = function() return nil end,
        GetPrefix = function() return nil end,
    },
}
function IsValid() return false end
dofile( "pcmod_network.lua" )

local function assertEq( a, b, m )
    if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
    if (not v) then error( "FAILED: " .. m, 2 ) end
end

local net = PCMod.Network
assertEq( net.CreatePacket( 1, 2, 58, "one" ), 1, "first packet id" )
assertEq( net.CreatePacket( 1, 2, 58, "two" ), 2, "second packet id" )
assertEq( net.CreatePacket( 1, 2, 58, "three" ), 3, "third packet id" )
assertEq( net.FindFreePacketSlot( 3, 1 ), nil, "full in-flight table has no slot" )

local original = net.Packets[ 1 ]
assertEq( net.CreatePacket( 1, 2, 58, "overflow" ), nil, "overflow is backpressured" )
assertTrue( net.Packets[ 1 ] == original, "in-flight packet was not replaced" )
assertEq( net.Packets[ 1 ].Body, "one", "in-flight body preserved" )

net.Packets[ 2 ].Delivered = true
assertEq( net.CreatePacket( 1, 2, 58, "recycled" ), 2, "delivered slot is recycled" )
assertEq( net.Packets[ 2 ].Body, "recycled", "recycled slot holds new packet" )

net.Packets[ 1 ] = nil
assertEq( net.CreatePacket( 1, 2, 58, "free" ), 1, "empty slot is reused" )

-- Router registry and /32 allocation. A released backbone id is reused before
-- the cursor advances, and FindSubByEnt does not scan the whole id space.
function IsValid( e ) return (e ~= nil) and (e.valid ~= false) end
PCMod.Data = {}
local function makeRouter( id, cls )
    local e = { valid = true, id = id, cls = cls, subnet = 0, bsubnet = 0, bip = 0, ip = 0 }
    function e:EntIndex() return self.id end
    function e:GetClass() return self.cls end
    function e:SetSubnet( v ) self.subnet = v end
    function e:SetIP( v ) self.ip = v end
    function e:SetBSubnet( v ) self.bsubnet = v end
    function e:SetBIP( v ) self.bip = v end
    function e:ForceRemove() self.removed = true end
    function e:Memory() return PCMod.Data[ self.id ] and PCMod.Data[ self.id ].Memory end
    function e:UpdateMemory( m ) PCMod.Data[ self.id ].Memory = m end
    return e
end

local back = makeRouter( 1, "pcmod_brouter" )
local lan = makeRouter( 2, "pcmod_router" )
assertTrue( net.RegisterRouter( back ), "backbone registers" )
assertTrue( net.RegisterRouter( lan ), "LAN router registers" )
assertEq( net.FindSubByEnt( back ), 1, "backbone /32 allocated" )
assertEq( net.FindSubByEnt( lan ), false, "LAN router has no global /32" )
assertTrue( net.Routers[ 1 ] ~= nil and net.Routers[ 2 ] ~= nil, "both routers tracked" )

-- Recycled pids are forgotten by LAN routers too, not only backbones.
PCMod.Data[ 1 ] = { Memory = { P = { [ 5 ] = true } } }
PCMod.Data[ 2 ] = { Memory = { P = { [ 5 ] = true, [ 6 ] = true } } }
net.ClearPacketMemory( 5 )
assertTrue( not PCMod.Data[ 1 ].Memory.P[ 5 ], "backbone pid forgotten" )
assertTrue( not PCMod.Data[ 2 ].Memory.P[ 5 ], "LAN router pid forgotten" )
assertTrue( PCMod.Data[ 2 ].Memory.P[ 6 ], "unrelated pid preserved" )

-- A released /32 is reused instead of advancing the cursor forever.
net.UnRegisterRouter( back )
assertEq( net.FindSubByEnt( back ), false, "unregistered backbone is gone" )
assertTrue( net.Routers[ 1 ] == nil, "unregistered router is untracked" )
local again = makeRouter( 3, "pcmod_brouter" )
assertTrue( net.RegisterRouter( again ), "replacement backbone registers" )
assertEq( net.FindSubByEnt( again ), 1, "released /32 is reused" )

-- Packet tracing is opt-in and prints source/destination plus the first 5 body
-- fields, so the console output stays useful on a large topology.
local logged = {}
PCMod.Msg = function( m ) logged[ #logged + 1 ] = m end
net.DebugPackets = function() return true end
net.LogPacket( "new", "10.0.1.2", "10.0.2.3", 0, { "netPing", "hk", 1, 2, 3, 4 }, "pid=7 ttl=64" )
assertTrue( #logged == 1, "packet trace prints once" )
assertTrue( string.find( logged[ 1 ], "10.0.1.2 -> 10.0.2.3", 1, true ) ~= nil, "packet trace has src/dest" )
assertTrue( string.find( logged[ 1 ], "body5=[netPing hk 1 2 3]", 1, true ) ~= nil, "packet trace has first 5 fields" )
assertTrue( string.find( logged[ 1 ], "pid=7 ttl=64", 1, true ) ~= nil, "packet trace has extra info" )

print( "ALL NETWORK TESTS PASSED" )
