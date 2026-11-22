-- Packet id recycling must never overwrite an in-flight packet.
local now = 100
function CurTime() return now end
PCMod = {
    Msg = function() end,
    Cfg = { MaxNetworkPid = 3, NetworkPacketLifetime = 30 },
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
local oldGeneration = net.Packets[ 2 ].Generation
assertEq( net.CreatePacket( 1, 2, 58, "recycled" ), 2, "delivered slot is recycled" )
assertEq( net.Packets[ 2 ].Body, "recycled", "recycled slot holds new packet" )
assertTrue( net.Packets[ 2 ].Generation ~= oldGeneration, "recycled PID gets a fresh generation" )

net.Packets[ 1 ] = nil
assertEq( net.CreatePacket( 1, 2, 58, "free" ), 1, "empty slot is reused" )

-- A full table of abandoned packets applies backpressure only until their
-- retention deadline, then recovers instead of dying permanently.
net.Packets = {}
net.NextID = 1
now = 200
for i = 1, 3 do
	assertEq( net.CreatePacket( 1, 2, 58, "abandoned" .. i ), i, "fill abandoned slot" )
end
assertEq( net.CreatePacket( 1, 2, 58, "too early" ), nil, "live retention still backpressures" )
now = 231
local expiredID = net.CreatePacket( 1, 2, 58, "after expiry" )
assertTrue( expiredID ~= nil, "expired abandoned slot is reclaimed" )
assertTrue( net.Packets[ expiredID ].Generation > 3, "expiry also advances the global generation" )

-- Explicit terminal drops are immediately recyclable.
net.DropPacket( expiredID )
assertTrue( net.Packets[ expiredID ].Delivered, "drop helper retires the packet" )

print( "ALL NETWORK TESTS PASSED" )
